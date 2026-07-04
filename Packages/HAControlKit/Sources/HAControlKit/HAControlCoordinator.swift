import Foundation
import Observation
import os

@MainActor
@Observable
public final class HAControlCoordinator {
    public private(set) var connection: ConnectionState = .disconnected

    // Diagnostic logging only. Logs topics, payloads and connection state — never
    // broker host/username/password (those never reach the coordinator's log calls).
    private let log = Logger(subsystem: "ing.kipp.Immich-Slideshow", category: "HAControl")

    private let transport: any MQTTTransport
    private let control: any PlaybackControlling
    private let configStore: any BrokerConfigStore
    private let deviceName: String
    private let enabledEntities: Set<HAEntity>
    private var deviceID: String?
    private var incomingTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?

    public init(
        transport: any MQTTTransport,
        control: any PlaybackControlling,
        configStore: any BrokerConfigStore,
        deviceName: String,
        enabledEntities: Set<HAEntity> = [.playback]
    ) {
        self.transport = transport
        self.control = control
        self.configStore = configStore
        self.deviceName = deviceName
        self.enabledEntities = enabledEntities
    }

    public func start() async {
        guard let config = configStore.load() else {
            log.info("start: no broker config — remote control disabled")
            return
        }

        deviceID = config.deviceID
        connection = .connecting
        log.info("start: connecting (device=\(config.deviceID, privacy: .public), entities=\(self.enabledEntities.map(\.rawValue).sorted().joined(separator: ","), privacy: .public))")

        let will = MQTTMessage(
            topic: HATopics.availability(deviceID: config.deviceID),
            payload: Data("offline".utf8),
            retain: true
        )

        do {
            try await transport.connect(will: will)
        } catch {
            connection = .disconnected
            log.error("start: connect failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        connection = .connected
        log.info("start: connected")
        await announce()
        startConsumers()
    }

    public func stop() async {
        incomingTask?.cancel()
        connectionTask?.cancel()
        incomingTask = nil
        connectionTask = nil
        await transport.disconnect()
        connection = .disconnected
    }

    internal func announce() async {
        guard let deviceID = ensureDeviceID() else {
            return
        }

        try? await transport.publish(MQTTMessage(
            topic: HATopics.availability(deviceID: deviceID),
            payload: Data("online".utf8),
            retain: true
        ))

        for entity in orderedEnabledEntities {
            try? await transport.publish(MQTTMessage(
                topic: HATopics.discoveryConfigTopic(deviceID: deviceID, entity: entity),
                payload: HADiscovery.config(
                    for: entity,
                    deviceID: deviceID,
                    deviceName: deviceName,
                    albumOptions: control.albumOptions
                ),
                retain: true
            ))
            try? await transport.subscribe(HATopics.commandTopic(deviceID: deviceID, entity: entity))
            await echo(entity)
            log.info("announce: published discovery + subscribed \(entity.rawValue, privacy: .public)")
        }

        control.onLocalChange = { [weak self] in
            Task { @MainActor in
                await self?.echoAll()
            }
        }
    }

    internal func handleIncoming(_ message: MQTTMessage) async {
        guard let deviceID = ensureDeviceID() else {
            return
        }

        for entity in enabledEntities where message.topic == HATopics.commandTopic(deviceID: deviceID, entity: entity) {
            let payload = String(data: message.payload, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            log.info("command: \(entity.rawValue, privacy: .public) payload=\(payload, privacy: .public)")

            switch entity {
            case .playback:
                let command = payload.uppercased()
                if command == "ON" {
                    control.resume()
                } else if command == "OFF" {
                    control.pause()
                }
            case .brightness:
                // HA sends a 0–255 level (or "OFF" via on_command_type: brightness).
                // Map to 0.0–1.0 and clamp; non-numeric/unknown payloads change nothing.
                if let level = Int(payload) {
                    let clamped = min(max(level, 0), 255)
                    await control.setBrightness(Double(clamped) / 255)
                } else if payload.uppercased() == "OFF" {
                    await control.setBrightness(0)
                }
            case .album:
                // Only switch on a known album; unknown selections are a no-op.
                if control.albumOptions.contains(payload) {
                    control.selectAlbum(payload)
                }
            case .order, .duration, .transition, .kenBurns, .fit, .quality, .clock, .clockCorner, .clockDate, .next, .previous, .currentPhoto, .currentPhotoImage, .phase, .photoCount, .version:
                break
            }

            // Always echo the actual state — even for invalid/unknown commands —
            // so HA mirrors the real app state (FR-009/FR-011/FR-013/FR-015).
            await echo(entity)
            return
        }
    }

    internal func handleConnection(_ up: Bool) async {
        if up {
            connection = .connected
            log.info("connection: up — re-announcing")
            await announce()
        } else {
            connection = .disconnected
            log.notice("connection: down")
        }
    }

    internal func echo(_ entity: HAEntity) async {
        guard let deviceID = ensureDeviceID() else {
            return
        }

        let payload: String
        switch entity {
        case .playback:
            payload = control.playbackState == .playing ? "ON" : "OFF"
        case .brightness:
            payload = String(Int((control.brightness * 255).rounded()))
        case .album:
            payload = control.currentAlbum ?? ""
        case .order, .duration, .transition, .kenBurns, .fit, .quality, .clock, .clockCorner, .clockDate, .next, .previous, .currentPhoto, .currentPhotoImage, .phase, .photoCount, .version:
            payload = ""
        }

        try? await transport.publish(MQTTMessage(
            topic: HATopics.stateTopic(deviceID: deviceID, entity: entity),
            payload: Data(payload.utf8),
            retain: true
        ))
    }

    internal func echoAll() async {
        for entity in orderedEnabledEntities {
            await echo(entity)
        }
    }

    private var orderedEnabledEntities: [HAEntity] {
        HAEntity.allCases.filter { enabledEntities.contains($0) }
    }

    private func ensureDeviceID() -> String? {
        if let deviceID {
            return deviceID
        }
        guard let config = configStore.load() else {
            return nil
        }
        deviceID = config.deviceID
        return config.deviceID
    }

    private func startConsumers() {
        incomingTask?.cancel()
        connectionTask?.cancel()

        let incoming = transport.incoming
        incomingTask = Task { [weak self] in
            for await message in incoming {
                await self?.handleIncoming(message)
            }
        }

        let connectionEvents = transport.connectionEvents
        connectionTask = Task { [weak self] in
            for await up in connectionEvents {
                await self?.handleConnection(up)
            }
        }
    }
}
