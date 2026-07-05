import Foundation
import Testing
import MQTTNIO
import HAControlKit
@testable import HAControlMQTT

// Integration test against a REAL, already-running MQTT broker that has a valid
// public TLS certificate (e.g. home.kippings.de:8883). Unlike
// `NIOMQTTTransportIntegrationTests` (which spawns a local mosquitto and pins a
// test CA), this one exercises the exact PRODUCTION path: the convenience
// initializer with `tlsConfiguration == nil`, i.e. full certificate verification
// against the system trust store — no CA pinning, no downgrade, never disabled.
//
// Gated behind `MQTT_REAL=1` and never run in CI. Credentials come from the
// environment ONLY — never the repository (constitution III: no secrets in code):
//   MQTT_REAL=1            enable the suite
//   MQTT_HOST             broker host (e.g. home.kippings.de)
//   MQTT_PORT             TLS port (default 8883)
//   MQTT_USER / MQTT_PASS broker credentials
//
// Proves end to end against the live broker: TLS handshake with real cert
// verification, connect with LWT, retained publish, subscribe + round-trip
// delivery of our own message. It cleans up its retained availability so it
// leaves no state behind.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MQTT_REAL"] == "1"))
struct RealBrokerIntegrationTests {
    @Test
    func connectsPublishesAndReceivesOverRealTLS() async throws {
        let env = ProcessInfo.processInfo.environment
        let host = try #require(env["MQTT_HOST"], "set MQTT_HOST")
        let port = Int(env["MQTT_PORT"] ?? "8883") ?? 8883
        let user = try #require(env["MQTT_USER"], "set MQTT_USER")
        let pass = try #require(env["MQTT_PASS"], "set MQTT_PASS")

        // A unique, disposable device id so the test never collides with a real
        // slideshow device on the same broker.
        let deviceID = "immich-slideshow-realtest-\(UUID().uuidString.prefix(8))"
        let transport = NIOMQTTTransport(config: BrokerConfig(
            host: host, port: port, username: user, password: pass, deviceID: deviceID))

        let collector = RealCollector()
        let incomingTask = Task { for await message in transport.incoming { await collector.add(message) } }
        defer { incomingTask.cancel() }

        // --- TLS connect with LWT -------------------------------------------
        let availability = HATopics.availability(deviceID: deviceID)
        try await transport.connect(will: MQTTMessage(
            topic: availability, payload: Data("offline".utf8), retain: true))

        // --- Retained publish ------------------------------------------------
        try await transport.publish(MQTTMessage(
            topic: availability, payload: Data("online".utf8), retain: true))

        // --- Subscribe + round-trip delivery of our own message --------------
        let topic = HATopics.commandTopic(deviceID: deviceID, entity: .playback)
        try await transport.subscribe(topic)
        let token = UUID().uuidString
        try await transport.publish(MQTTMessage(
            topic: topic, payload: Data(token.utf8), retain: false))

        let delivered = await waitUntil(timeout: .seconds(10)) {
            await collector.has(topic: topic, payload: token)
        }
        #expect(delivered, "did not receive our own published message back over real TLS")

        // Leave no state on the broker: clear the retained availability.
        try await transport.publish(MQTTMessage(topic: availability, payload: Data(), retain: true))
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

private actor RealCollector {
    private var messages: [MQTTMessage] = []
    func add(_ message: MQTTMessage) { messages.append(message) }
    func has(topic: String, payload: String) -> Bool {
        messages.contains { $0.topic == topic && String(data: $0.payload, encoding: .utf8) == payload }
    }
}
