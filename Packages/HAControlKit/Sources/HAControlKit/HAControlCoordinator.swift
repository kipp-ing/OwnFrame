import Foundation
import Observation
import os

@MainActor
@Observable
public final class HAControlCoordinator {
    /// Free-telemetry / paid-control split (spec 1100 FR-1100-03 / FR-1100-03a).
    public enum Mode: Sendable {
        /// **Free tier.** Publish availability + read-only sensor entities so Home Assistant
        /// can *see* the frame. Never publish a controllable entity, never subscribe to a
        /// command topic, never act on a command.
        case telemetryOnly
        /// **Automation unlock.** Full read + control: controllable entities are published and
        /// their command topics subscribed and handled.
        case full
    }

    public private(set) var connection: ConnectionState = .disconnected

    // Diagnostic logging only. Logs topics, payloads and connection state — never
    // broker host/username/password (those never reach the coordinator's log calls).
    private let log = Logger(subsystem: "ing.kipp.Immich-Slideshow", category: "HAControl")

    private let transport: any MQTTTransport
    private let control: any PlaybackControlling
    private let settings: (any SettingsControlling)?
    private let photoReporter: (any PhotoReporting)?
    /// Optional battery telemetry source (spec 710 FR-710-23). `nil` (or `hasBattery ==
    /// false`, e.g. Apple TV) means the `battery`/`charging` entities are omitted entirely.
    private let battery: (any BatteryReporting)?
    private let configStore: any BrokerConfigStore
    private let deviceName: String
    private let enabledEntities: Set<HAEntity>
    private let mode: Mode
    private var deviceID: String?
    private var incomingTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var settingsEchoTask: Task<Void, Never>?
    private var lastSettingsSnapshot: ThemeSettingsSnapshot?

    public init(
        transport: any MQTTTransport,
        control: any PlaybackControlling,
        settings: (any SettingsControlling)? = nil,
        photoReporter: (any PhotoReporting)? = nil,
        configStore: any BrokerConfigStore,
        deviceName: String,
        battery: (any BatteryReporting)? = nil,
        enabledEntities: Set<HAEntity> = [.playback],
        mode: Mode = .full
    ) {
        self.transport = transport
        self.control = control
        self.settings = settings
        self.photoReporter = photoReporter
        self.battery = battery
        self.configStore = configStore
        self.deviceName = deviceName
        self.enabledEntities = enabledEntities
        self.mode = mode
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
        // A clean MQTT DISCONNECT (below) suppresses the Will, so a graceful stop
        // (backgrounding, leaving the slideshow) would never otherwise show up as
        // "offline" in HA — only an unclean drop fires the LWT. Publish it explicitly.
        if let deviceID {
            try? await transport.publish(MQTTMessage(
                topic: HATopics.availability(deviceID: deviceID),
                payload: Data("offline".utf8),
                retain: true
            ))
        }
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

        let modeLabel = mode == .full ? "full" : "telemetry"

        // A frame upgrading from the pre-gate build left a *retained* discovery config on
        // the broker for every controllable entity. Merely skipping the publish below does
        // not remove those: the broker replays them to Home Assistant forever, and because
        // every entity shares the one availability topic just set to "online", HA would
        // render them as live, interactive controls that silently do nothing — the app no
        // longer subscribes to their command topics. An empty retained payload is the
        // documented way to retract a discovery config, so sweep them before announcing
        // (FR-1100-03a / SC-1100-06 "zero controllable entities"). The sweep covers
        // `allCases`, not just the enabled set, because a stale config can survive from any
        // earlier run whose entity selection differed.
        if mode == .telemetryOnly {
            for entity in HAEntity.allCases where entity.isControllable {
                try? await transport.publish(MQTTMessage(
                    topic: HATopics.discoveryConfigTopic(deviceID: deviceID, entity: entity),
                    payload: Data(),
                    retain: true
                ))
            }
            log.info("announce: retracted controllable discovery [telemetry]")
        }

        for entity in orderedEnabledEntities {
            // Free telemetry publishes read-only sensors only; controllable entities and
            // their command topics require the Automation unlock (FR-1100-03 / FR-1100-03a).
            if mode == .telemetryOnly && entity.isControllable { continue }
            // Battery/charging exist only on a battery-bearing device with a source — omit
            // both entirely otherwise (no discovery, no state) so Apple TV shows neither
            // (FR-710-23).
            if entity.isBatteryEntity && !hasBatterySource { continue }

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
            if mode == .full {
                try? await transport.subscribe(HATopics.commandTopic(deviceID: deviceID, entity: entity))
            }
            await echo(entity)
            log.info("announce: published \(entity.rawValue, privacy: .public) [\(modeLabel, privacy: .public)]")
        }

        // announce() just echoed every published entity — that is the baseline the
        // scoped settings diff compares against.
        lastSettingsSnapshot = settings?.themeSettings

        // Control + settings echoes only matter when controllable entities are published.
        if mode == .full {
            control.onLocalChange = { [weak self] in
                Task { @MainActor in
                    await self?.echoAll()
                }
            }

            settings?.onSettingsChange = { [weak self] in
                self?.scheduleSettingsEcho()
            }
        }

        // Photo telemetry (read-only sensors) is free — always wired (FR-1100-03a).
        photoReporter?.onPhotoChange = { [weak self] report in
            self?.schedulePhotoPublish(report)
        }

        // Battery telemetry (read-only sensors) is free too, but only wired on a
        // battery-bearing device — the source pushes a fresh reading and we re-echo
        // both entities (FR-710-23).
        if hasBatterySource {
            battery?.onBatteryChange = { [weak self] in
                self?.scheduleBatteryEcho()
            }
        }
    }

    /// Re-echo `battery`/`charging` after the source signals a change. Detached from the
    /// caller like `schedulePhotoPublish`, and guarded by the enabled set.
    private func scheduleBatteryEcho() {
        Task { [weak self] in
            guard let self else { return }
            if self.enabledEntities.contains(.battery) { await self.echo(.battery) }
            if self.enabledEntities.contains(.charging) { await self.echo(.charging) }
        }
    }

    // MARK: - Photo publish (US2)

    private func schedulePhotoPublish(_ report: PhotoReport) {
        // Detached from the caller so a slide advance returns immediately (SC-710-04).
        Task { [weak self] in
            guard let self else { return }
            await self.publishPhoto(report)
            // The phase / photo-count diagnostics track the same change (entering
            // empty/failed, a new album's count), so refresh them here too.
            if self.enabledEntities.contains(.phase) { await self.echo(.phase) }
            if self.enabledEntities.contains(.photoCount) { await self.echo(.photoCount) }
        }
    }

    private func publishPhoto(_ report: PhotoReport) async {
        await publishPhotoMetadata(report)
        await publishPhotoImage(report)
    }

    /// current_photo metadata (JSON), NOT retained (FR-710-11 privacy carve-out).
    /// Cleared to the all-null form when the show isn't playing.
    private func publishPhotoMetadata(_ report: PhotoReport) async {
        guard let deviceID = ensureDeviceID() else { return }
        let topic = HATopics.stateTopic(deviceID: deviceID, entity: .currentPhoto)
        let payload = report.phase == .playing ? Self.photoMetadata(for: report) : Self.clearedPhotoMetadata
        try? await transport.publish(MQTTMessage(topic: topic, payload: payload, retain: false))
    }

    /// current_photo_image bytes, NOT retained. Cleared (empty) when not playing;
    /// skipped + logged while playing if there is no image (disabled or over cap).
    private func publishPhotoImage(_ report: PhotoReport) async {
        guard let deviceID = ensureDeviceID() else { return }
        let topic = HATopics.stateTopic(deviceID: deviceID, entity: .currentPhotoImage)
        guard report.phase == .playing else {
            try? await transport.publish(MQTTMessage(topic: topic, payload: Data(), retain: false))
            return
        }
        if let image = report.imageData {
            try? await transport.publish(MQTTMessage(topic: topic, payload: image, retain: false))
        } else {
            log.info("photo: image publish skipped — no image data (asset=\(report.assetID ?? "nil", privacy: .public))")
        }
    }

    /// Metadata JSON for the `current_photo` sensor: its state (`value_json.id`)
    /// plus the `json_attributes` on the same topic (FR-710-06). `.sortedKeys`
    /// for deterministic output; nil fields serialize as JSON `null`.
    private static func photoMetadata(for report: PhotoReport) -> Data {
        func orNull(_ value: String?) -> Any { value.map { $0 as Any } ?? NSNull() }
        let object: [String: Any] = [
            "id": orNull(report.assetID),
            "taken_at": orNull(report.takenAt?.ISO8601Format()),
            "city": orNull(report.city),
            "state": orNull(report.state),
            "country": orNull(report.country),
            "album_id": orNull(report.albumID),
            "album_name": orNull(report.albumName),
        ]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            ?? Data("{}".utf8)
    }

    private static let clearedPhotoMetadata: Data = {
        let object: [String: Any] = [
            "id": NSNull(), "taken_at": NSNull(), "city": NSNull(), "state": NSNull(),
            "country": NSNull(), "album_id": NSNull(), "album_name": NSNull(),
        ]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            ?? Data("{}".utf8)
    }()

    internal func handleIncoming(_ message: MQTTMessage) async {
        // Telemetry-only never subscribes, so no command normally reaches here; guard anyway
        // so a stray retained command can never drive an unentitled frame (FR-1100-03).
        guard mode == .full else { return }
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
            case .order, .duration, .transition, .kenBurns, .fit, .quality, .clock, .clockCorner, .clockStyle, .clockSize, .clockDate:
                applySetting(entity, payload: payload)
            case .next:
                await photoReporter?.showNext()
            case .previous:
                await photoReporter?.showPrevious()
            case .currentPhoto, .currentPhotoImage, .phase, .photoCount, .version, .battery, .charging:
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

        // Entities that don't use the uniform retained-string state topic:
        switch entity {
        case .currentPhoto:
            // JSON metadata, not retained — republished so HA recovers the current
            // photo on (re)announce without relying on a retained message (FR-710-13).
            if let report = photoReporter?.currentPhotoReport { await publishPhotoMetadata(report) }
            return
        case .currentPhotoImage:
            if let report = photoReporter?.currentPhotoReport { await publishPhotoImage(report) }
            return
        case .next, .previous:
            return  // stateless buttons — nothing to echo
        default:
            break
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
            payload = settings?.themeSettings.clockPlace.rawValue ?? ""
        case .clockStyle:
            payload = settings?.themeSettings.clockStyle.rawValue ?? ""
        case .clockSize:
            payload = settings?.themeSettings.clockSize.rawValue ?? ""
        case .clockDate:
            payload = switchPayload(settings?.themeSettings.clockDate)
        case .phase:
            payload = photoReporter?.currentPhotoReport.phase.rawValue ?? ""
        case .photoCount:
            payload = photoReporter.map { String($0.currentPhotoReport.photoCount) } ?? ""
        case .version:
            payload = photoReporter?.version ?? ""
        case .battery:
            // Publish nothing until a real reading exists — never a misleading 0%
            // (data-model: `level == nil` → skip). The entity still exists in discovery.
            guard let level = battery?.current.level else { return }
            payload = String(level)
        case .charging:
            // On/off external power. No source → nothing to echo (announce already
            // omitted it, but guard so a stray echo can't publish a false "OFF").
            guard let battery else { return }
            payload = battery.current.isOnPower ? "ON" : "OFF"
        case .next, .previous, .currentPhoto, .currentPhotoImage:
            payload = ""  // routed above; kept for switch exhaustiveness
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
        case .order, .duration, .transition, .kenBurns, .fit, .quality, .clock, .clockCorner, .clockStyle, .clockSize, .clockDate:
            true
        case .playback, .brightness, .album, .next, .previous, .currentPhoto, .currentPhotoImage, .phase, .photoCount, .version, .battery, .charging:
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
            snapshot.clockPlace.rawValue
        case .clockStyle:
            snapshot.clockStyle.rawValue
        case .clockSize:
            snapshot.clockSize.rawValue
        case .clockDate:
            snapshot.clockDate ? "ON" : "OFF"
        case .playback, .brightness, .album, .next, .previous, .currentPhoto, .currentPhotoImage, .phase, .photoCount, .version, .battery, .charging:
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
            // Unknown option (e.g. a retained rollback value) is ignored gracefully.
            guard let value = ClockCornerSetting(rawValue: payload) else { return }
            snapshot.clockPlace = value
        case .clockStyle:
            guard let value = ClockStyleSetting(rawValue: payload) else { return }
            snapshot.clockStyle = value
        case .clockSize:
            guard let value = ClockSizeSetting(rawValue: payload) else { return }
            snapshot.clockSize = value
        case .clockDate:
            guard let value = switchBool(payload) else { return }
            snapshot.clockDate = value
        case .playback, .brightness, .album, .next, .previous, .currentPhoto, .currentPhotoImage, .phase, .photoCount, .version, .battery, .charging:
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

    /// Whether a battery source is present and reports a battery. Gates discovery/state/echo
    /// for `battery`/`charging` so batteryless devices (Apple TV) publish neither (FR-710-23).
    private var hasBatterySource: Bool {
        battery?.hasBattery ?? false
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

        // Only the control tier consumes commands; telemetry-only has no subscriptions.
        if mode == .full {
            let incoming = transport.incoming
            incomingTask = Task { [weak self] in
                for await message in incoming {
                    await self?.handleIncoming(message)
                }
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
