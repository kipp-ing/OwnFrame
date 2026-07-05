import Foundation
import Testing
import MQTTNIO
import HAControlKit
@testable import HAControlMQTT

// Integration test for the plaintext (no-TLS) MQTT transport path against a
// locally spawned mosquitto broker. Gated behind `MQTT_LOCAL=1` and never runs
// in CI. This mirrors `NIOMQTTTransportIntegrationTests` almost exactly.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MQTT_LOCAL"] == "1"))
struct LocalPlaintextBrokerIntegrationTests {
    @Test
    func connectsPublishesAndReceivesOverPlaintext() async throws {
        func findMosquittoBinary() throws -> String {
            let candidates = [
                "/opt/homebrew/sbin/mosquitto",
                "/usr/local/sbin/mosquitto",
                "/usr/sbin/mosquitto",
                "/opt/homebrew/bin/mosquitto"
            ]
            for path in candidates {
                if FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
            struct NoMosquittoError: Error, CustomStringConvertible {
                var description: String { "mosquitto binary not found in expected locations" }
            }
            throw NoMosquittoError()
        }

        func startBroker() throws -> (Process, URL) {
            let mosquittoBin = try findMosquittoBinary()
            
            // Create a unique temp directory for the config
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("immich-slideshow-mqtt-test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            let confPath = tempDir.appendingPathComponent("mosquitto.conf").path
            let confContent = """
                listener 11883 127.0.0.1
                allow_anonymous true
                """
            try confContent.write(to: URL(fileURLWithPath: confPath), atomically: true, encoding: .utf8)
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: mosquittoBin)
            process.arguments = ["-c", confPath]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            
            return (process, tempDir)
        }

        // --- Boot the broker -------------------------------------------------
        let (broker, tempDir) = try startBroker()
        defer {
            broker.terminate()
            broker.waitUntilExit()
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await Task.sleep(for: .seconds(1)) // let it bind the plaintext listener

        // --- Build the transport for PLAINTEXT -------------------------------
        let deviceID = "immich-slideshow-localtest-\(UUID().uuidString.prefix(8))"
        let transport = NIOMQTTTransport(
            config: BrokerConfig(host: "127.0.0.1", port: 11883, username: "car", password: "carx1234", deviceID: deviceID),
            tlsConfiguration: nil,
            useSSL: false
        )

        let collector = Collector()
        let connectionTask = Task {
            for await up in transport.connectionEvents { await collector.addConnection(up) }
        }
        let incomingTask = Task {
            for await message in transport.incoming { await collector.addMessage(message) }
        }
        defer {
            connectionTask.cancel()
            incomingTask.cancel()
        }

        // --- Plaintext connect with LWT --------------------------------------
        let availability = HATopics.availability(deviceID: deviceID)
        try await transport.connect(will: MQTTMessage(
            topic: availability,
            payload: Data("offline".utf8),
            retain: true
        ))

        // --- Retained publish -------------------------------------------------
        try await transport.publish(MQTTMessage(
            topic: availability,
            payload: Data("online".utf8),
            retain: true
        ))

        // --- Subscribe + round-trip delivery ---------------------------------
        let commandTopic = HATopics.commandTopic(deviceID: deviceID, entity: .playback)
        try await transport.subscribe(commandTopic)
        
        let token = UUID().uuidString
        try await transport.publish(MQTTMessage(
            topic: commandTopic,
            payload: Data(token.utf8),
            retain: false
        ))
        
        let delivered = await waitUntil { await collector.hasMessage(topic: commandTopic, payload: token) }
        #expect(delivered, "subscribed command was not delivered back over plaintext")

        await transport.disconnect()
    }

    /// Polls `condition` until it holds or the timeout elapses.
    private func waitUntil(
        timeout: Duration = .seconds(10),
        _ condition: @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return await condition()
    }
}

private actor Collector {
    private var connections: [Bool] = []
    private var messages: [MQTTMessage] = []

    func addConnection(_ up: Bool) { connections.append(up) }
    func addMessage(_ message: MQTTMessage) { messages.append(message) }

    func connectionCount(of value: Bool) -> Int {
        connections.filter { $0 == value }.count
    }

    func hasMessage(topic: String, payload: String) -> Bool {
        messages.contains { $0.topic == topic && String(data: $0.payload, encoding: .utf8) == payload }
    }
}
