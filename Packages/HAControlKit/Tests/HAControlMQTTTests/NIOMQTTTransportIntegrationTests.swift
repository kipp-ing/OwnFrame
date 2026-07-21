import Foundation
import Testing
import MQTTNIO
import NIOSSL
import HAControlKit
@testable import HAControlMQTT

// Integration test for the real `NIOMQTTTransport` against a live mosquitto broker
// over TLS. It is **gated** behind `MQTT_INTEGRATION=1` and never runs in CI — the
// TLS transport is otherwise verified manually (plan.md). The companion script
// `Scripts/mqtt-integration.sh` generates the test CA + server cert, writes the
// mosquitto config, and runs `swift test` with the right environment.
//
// Required env when MQTT_INTEGRATION=1:
//   MQTT_MOSQUITTO_BIN  path to the mosquitto binary
//   MQTT_CONF           path to the mosquitto.conf (TLS listener + password_file)
//   MQTT_CA             path to the test CA certificate (PEM)
//   MQTT_HOST           broker host matching the server cert SAN (e.g. "localhost")
//   MQTT_PORT           TLS listener port (e.g. "18883")
//   MQTT_USER/MQTT_PASS broker credentials
//
// What it proves end to end: TLS handshake with full certificate verification
// (anchored to the test CA — verification is never disabled), connect with LWT,
// retained publish, subscribe + round-trip delivery, and self-healing reconnect
// after the broker drops and comes back.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MQTT_INTEGRATION"] == "1"))
struct NIOMQTTTransportIntegrationTests {
    // @covers FR-700-05
    @Test
    func connectsPublishesSubscribesAndReconnectsOverTLS() async throws {
        let env = ProcessInfo.processInfo.environment
        let mosquittoBin = try #require(env["MQTT_MOSQUITTO_BIN"])
        let confPath = try #require(env["MQTT_CONF"])
        let caPath = try #require(env["MQTT_CA"])
        let host = env["MQTT_HOST"] ?? "localhost"
        let port = Int(env["MQTT_PORT"] ?? "18883") ?? 18883
        let user = env["MQTT_USER"] ?? "hauser"
        let pass = env["MQTT_PASS"] ?? "hapass"

        func startBroker() throws -> Process {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: mosquittoBin)
            process.arguments = ["-c", confPath]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            return process
        }

        // --- Boot the broker -------------------------------------------------
        var broker = try startBroker()
        defer { broker.terminate() }
        try await Task.sleep(for: .seconds(1)) // let it bind the TLS listener

        // --- Build the transport with the test CA as trust anchor ------------
        // Full verification stays ON; we only add a known-good root so the local
        // self-signed chain validates (we never set certificateVerification = .none).
        var tls = TLSConfiguration.makeClientConfiguration()
        tls.trustRoots = .file(caPath)
        tls.certificateVerification = .fullVerification

        let deviceID = "it-device"
        let transport = NIOMQTTTransport(
            config: BrokerConfig(host: host, port: port, username: user, password: pass, deviceID: deviceID),
            tlsConfiguration: .niossl(tls)
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

        // --- TLS connect with LWT -------------------------------------------
        let availability = HATopics.availability(deviceID: deviceID)
        try await transport.connect(will: MQTTMessage(
            topic: availability,
            payload: Data("offline".utf8),
            retain: true
        ))

        // --- Retained publish ------------------------------------------------
        try await transport.publish(MQTTMessage(
            topic: availability,
            payload: Data("online".utf8),
            retain: true
        ))

        // --- Subscribe + round-trip delivery --------------------------------
        let commandTopic = HATopics.commandTopic(deviceID: deviceID, entity: .playback)
        try await transport.subscribe(commandTopic)
        try await transport.publish(MQTTMessage(
            topic: commandTopic,
            payload: Data("OFF".utf8),
            retain: false
        ))
        let delivered = await waitUntil { await collector.hasMessage(topic: commandTopic, payload: "OFF") }
        #expect(delivered, "subscribed command was not delivered back over TLS")

        // --- Reconnect: drop the broker, expect offline, bring it back ------
        broker.terminate()
        broker.waitUntilExit()
        let droppedOffline = await waitUntil { await collector.connectionCount(of: false) >= 1 }
        #expect(droppedOffline, "transport did not report a dropped connection")

        broker = try startBroker()
        try await Task.sleep(for: .seconds(1))
        let reconnected = await waitUntil(timeout: .seconds(25)) {
            await collector.connectionCount(of: true) >= 1
        }
        #expect(reconnected, "transport did not self-heal/reconnect after the broker returned")

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
