import Foundation
import HAControlKit
import MQTTNIO
import NIOCore
import os

public final class NIOMQTTTransport: MQTTTransport, @unchecked Sendable {
    public let incoming: AsyncStream<MQTTMessage>
    public let connectionEvents: AsyncStream<Bool>

    private let config: BrokerConfig
    private let client: MQTTClient
    private let incomingContinuation: AsyncStream<MQTTMessage>.Continuation
    private let connectionContinuation: AsyncStream<Bool>.Continuation

    // Reconnect state guarded by `stateLock`: the close listener fires on a NIO
    // event-loop thread, while connect()/disconnect() run on the caller's task.
    private let stateLock = NSLock()
    private var storedWill: MQTTMessage?
    private var isShuttingDown = false
    private var reconnectTask: Task<Void, Never>?

    // Backoff bounds for the self-healing reconnect (FR-005): start at 1s, double
    // up to a 30s cap so a long broker outage keeps retrying without busy-looping.
    private let initialReconnectDelay: UInt64 = 1_000_000_000
    private let maxReconnectDelay: UInt64 = 30_000_000_000

    // Diagnostic logging only — connection lifecycle events, never broker credentials.
    private let log = Logger(subsystem: "ing.kipp.Immich-Slideshow", category: "HAControlMQTT")

    public convenience init(config: BrokerConfig) {
        self.init(config: config, tlsConfiguration: nil)
    }

    /// Designated initializer. `tlsConfiguration` is `nil` in production, which means
    /// `mqtt-nio` uses the default client TLS config: full certificate verification
    /// against the system trust store (Konstitution IV — never disabled). It exists
    /// only so the integration test can pin a *local* test CA as an additional trust
    /// anchor while keeping verification fully enabled (it never sets
    /// `certificateVerification = .none`).
    ///
    /// `useSSL` defaults to `true` and the only public entry point
    /// (`init(config:)`) leaves it there, so production traffic is *always* TLS.
    /// It is `internal` and exists solely so an integration test can connect to a
    /// local, no-TLS mosquitto (`useSSL: false`); it is never a runtime downgrade
    /// of the real, valid-certificate broker.
    init(config: BrokerConfig, tlsConfiguration: MQTTClient.TLSConfigurationType?, useSSL: Bool = true) {
        self.config = config
        self.client = MQTTClient(
            host: config.host,
            port: config.port,
            identifier: config.deviceID,
            eventLoopGroupProvider: .createNew,
            configuration: .init(
                version: .v3_1_1,
                keepAliveInterval: .seconds(30),
                userName: config.username,
                password: config.password,
                useSSL: useSSL,
                tlsConfiguration: tlsConfiguration
            )
        )

        var incomingContinuation: AsyncStream<MQTTMessage>.Continuation!
        self.incoming = AsyncStream { continuation in
            incomingContinuation = continuation
        }
        self.incomingContinuation = incomingContinuation

        var connectionContinuation: AsyncStream<Bool>.Continuation!
        self.connectionEvents = AsyncStream { continuation in
            connectionContinuation = continuation
        }
        self.connectionContinuation = connectionContinuation

        client.addPublishListener(named: "hacontrol") { [incomingContinuation] result in
            guard case .success(let info) = result else {
                return
            }

            incomingContinuation?.yield(MQTTMessage(
                topic: info.topicName,
                payload: Data(buffer: info.payload),
                retain: info.retain
            ))
        }

        client.addCloseListener(named: "hacontrol") { [weak self] _ in
            self?.handleClose()
        }
    }

    public func connect(will: MQTTMessage) async throws {
        stateLock.withLock {
            storedWill = will
            isShuttingDown = false
            reconnectTask?.cancel()
            reconnectTask = nil
        }
        try await rawConnect(will: will)
        // The initial connection is signalled to the coordinator by `connect()`
        // returning (it announces directly). `connectionEvents` carries only the
        // later false→true reconnect edges, so we don't yield `true` here.
    }

    public func disconnect() async {
        stateLock.withLock {
            isShuttingDown = true
            reconnectTask?.cancel()
            reconnectTask = nil
        }
        try? await client.disconnect().get()
        try? await client.shutdown()
    }

    public func publish(_ message: MQTTMessage) async throws {
        try await client.publish(
            to: message.topic,
            payload: ByteBuffer(bytes: message.payload),
            qos: .atLeastOnce,
            retain: message.retain
        ).get()
    }

    public func subscribe(_ topicFilter: String) async throws {
        _ = try await client.subscribe(to: [
            MQTTSubscribeInfo(topicFilter: topicFilter, qos: .atLeastOnce),
        ]).get()
    }

    private func rawConnect(will: MQTTMessage) async throws {
        _ = try await client.connect(
            cleanSession: true,
            will: (
                topicName: will.topic,
                payload: ByteBuffer(bytes: will.payload),
                qos: .atLeastOnce,
                retain: will.retain
            )
        ).get()
    }

    // Fired by mqtt-nio whenever the connection drops (broker restart, network
    // blip, missed keepalive). Report `offline` to the coordinator and, unless the
    // app intentionally disconnected, kick off a backoff reconnect (self-healing).
    private func handleClose() {
        connectionContinuation.yield(false)
        log.notice("connection closed")

        let will: MQTTMessage? = stateLock.withLock {
            guard !isShuttingDown else { return nil }
            return storedWill
        }
        guard let will else { return }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.reconnectLoop(will: will)
        }
        stateLock.withLock {
            guard !isShuttingDown else {
                task.cancel()
                return
            }
            reconnectTask?.cancel()
            reconnectTask = task
        }
    }

    private func reconnectLoop(will: MQTTMessage) async {
        var delay = initialReconnectDelay
        while !Task.isCancelled {
            if stateLock.withLock({ isShuttingDown }) { return }
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return  // cancelled while waiting
            }
            if Task.isCancelled || stateLock.withLock({ isShuttingDown }) { return }

            log.info("reconnect: attempting")
            do {
                try await rawConnect(will: will)
                // Reconnected: signal the coordinator to re-announce availability,
                // discovery and current state (idempotent, retained).
                connectionContinuation.yield(true)
                log.info("reconnect: success")
                return
            } catch {
                log.error("reconnect: failed: \(error.localizedDescription, privacy: .public)")
                delay = min(delay * 2, maxReconnectDelay)
            }
        }
    }
}
