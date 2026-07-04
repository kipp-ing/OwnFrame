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
    private let settings: (any SettingsControlling)?
    private let configStore: any BrokerConfigStore
    private let deviceName: String
    private let enabledEntities: Set<HAEntity>
    private var deviceID: String?
    private var incomingTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var settingsEchoTask: Task<Void, Never>?
    private var lastSettingsSnapshot: ThemeSettingsSnapshot?

    public init(
        transport: any MQTTTransport,
        control: any PlaybackControlling,
        settings: (any SettingsControlling)? = nil,
        configStore: any BrokerConfigStore,
        deviceName: String,
        enabledEntities: Set<HAEntity> = [.playback]
    ) {
        self.transport = transport
        self.control = control
        self.settings = settings
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
        settingsEchoTask?.cancel()
        incomingTask = nil
        connectionTask = nil
        settingsEchoTask = nil
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

        // announce() just echoed every enabled entity — that is the baseline the
        // scoped settings diff compares against.
        lastSettingsSnapshot = settings?.themeSettings

        control.onLocalChange = { [weak self] in
            Task { @MainActor in
                await self?.echoAll()
            }
        }

        settings?.onSettingsChange = { [weak self] in
            self?.scheduleSettingsEcho()
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
            case .order, .duration, .transition, .kenBurns, .fit, .quality, .clock, .clockCorner, .clockDate:
                applySetting(entity, payload: payload)
            case .next, .previous, .currentPhoto, .currentPhotoImage, .phase, .photoCount, .version:
                break
            }

            // Always echo the actual state — even for invalid/unknown commands —
            // so HA mirrors the real app state (FR-009/FR-011/FR-013/FR-015).
            await echo(entity)
            if isSettingsEntity(entity) {
                // The command's echo is the fresh truth; without this, the
                // suppressed-callback diff would re-echo the same change.
                lastSettingsSnapshot = settings?.themeSettings
            }
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
        case .order:
            payload = settings?.themeSettings.order.rawValue ?? ""
        case .duration:
            payload = settings.map { String($0.themeSettings.durationSeconds) } ?? ""
        case .transition:
            payload = settings?.themeSettings.transition.rawValue ?? ""
        case .kenBurns:
            payload = switchPayload(settings?.themeSettings.kenBurns)
        case .fit:
            payload = settings?.themeSettings.fit.rawValue ?? ""
        case .quality:
            payload = settings?.themeSettings.quality.rawValue ?? ""
        case .clock:
            payload = switchPayload(settings?.themeSettings.clockOn)
        case .clockCorner:
            payload = settings?.themeSettings.clockCorner.rawValue ?? ""
        case .clockDate:
            payload = switchPayload(settings?.themeSettings.clockDate)
        case .next, .previous, .currentPhoto, .currentPhotoImage, .phase, .photoCount, .version:
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
        lastSettingsSnapshot = settings?.themeSettings
    }

    // MARK: - Scoped, coalesced settings echo (SC-710-02)

    /// A burst of local changes collapses into one pending echo task; the task
    /// reads the store when it runs, so the last value wins by construction.
    private func scheduleSettingsEcho() {
        guard settingsEchoTask == nil else { return }
        settingsEchoTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.settingsEchoTask = nil
            await self.echoChangedSettings()
        }
    }

    /// Echo only entities whose value differs from the last echoed snapshot —
    /// a local change to one setting must not republish the other eight.
    private func echoChangedSettings() async {
        guard let settings else { return }
        let current = settings.themeSettings
        defer { lastSettingsSnapshot = current }
        for entity in orderedEnabledEntities where isSettingsEntity(entity) {
            let previous = lastSettingsSnapshot.map { settingValue(entity, in: $0) }
            if previous != settingValue(entity, in: current) {
                await echo(entity)
            }
        }
    }

    private func isSettingsEntity(_ entity: HAEntity) -> Bool {
        switch entity {
        case .order, .duration, .transition, .kenBurns, .fit, .quality, .clock, .clockCorner, .clockDate:
            true
        case .playback, .brightness, .album, .next, .previous, .currentPhoto, .currentPhotoImage, .phase, .photoCount, .version:
            false
        }
    }

    private func settingValue(_ entity: HAEntity, in snapshot: ThemeSettingsSnapshot) -> String {
        switch entity {
        case .order:
            snapshot.order.rawValue
        case .duration:
            String(snapshot.durationSeconds)
        case .transition:
            snapshot.transition.rawValue
        case .kenBurns:
            snapshot.kenBurns ? "ON" : "OFF"
        case .fit:
            snapshot.fit.rawValue
        case .quality:
            snapshot.quality.rawValue
        case .clock:
            snapshot.clockOn ? "ON" : "OFF"
        case .clockCorner:
            snapshot.clockCorner.rawValue
        case .clockDate:
            snapshot.clockDate ? "ON" : "OFF"
        case .playback, .brightness, .album, .next, .previous, .currentPhoto, .currentPhotoImage, .phase, .photoCount, .version:
            ""
        }
    }

    private func applySetting(_ entity: HAEntity, payload: String) {
        guard let settings else {
            return
        }

        var snapshot = settings.themeSettings
        switch entity {
        case .order:
            guard let value = PlayOrderSetting(rawValue: payload) else { return }
            snapshot.order = value
        case .duration:
            guard let value = Int(payload), (3...600).contains(value) else { return }
            snapshot.durationSeconds = value
        case .transition:
            guard let value = TransitionSetting(rawValue: payload) else { return }
            snapshot.transition = value
        case .kenBurns:
            guard let value = switchBool(payload) else { return }
            snapshot.kenBurns = value
        case .fit:
            guard let value = FitSetting(rawValue: payload) else { return }
            snapshot.fit = value
        case .quality:
            guard let value = QualitySetting(rawValue: payload) else { return }
            snapshot.quality = value
        case .clock:
            guard let value = switchBool(payload) else { return }
            snapshot.clockOn = value
        case .clockCorner:
            guard let value = ClockCornerSetting(rawValue: payload) else { return }
            snapshot.clockCorner = value
        case .clockDate:
            guard let value = switchBool(payload) else { return }
            snapshot.clockDate = value
        case .playback, .brightness, .album, .next, .previous, .currentPhoto, .currentPhotoImage, .phase, .photoCount, .version:
            return
        }

        settings.apply(snapshot)
    }

    private func switchBool(_ payload: String) -> Bool? {
        switch payload.uppercased() {
        case "ON":
            true
        case "OFF":
            false
        default:
            nil
        }
    }

    private func switchPayload(_ value: Bool?) -> String {
        guard let value else {
            return ""
        }
        return value ? "ON" : "OFF"
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
