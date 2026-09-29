import Foundation
import Observation
import os

/// 410: decides **whether and when** OwnFrame writes brightness; `PowerManager` (400) keeps the
/// mechanics. At any moment there is one target — `.automatic` (write nothing, iOS is in control)
/// or a held level — derived from the newest event (D-410-5, last event wins): the in-app
/// control, a Home Assistant / Shortcuts command (session only, D-410-2), or a night-window
/// edge. A 1 s tick is the only writer outside those events (FR-410-04/05): it re-applies a held
/// level that iOS drifted away from (finding 2), crosses window edges and ends a peek.
@MainActor
@Observable
public final class BrightnessController {
    public enum RemoteMode: Sendable, Equatable {
        case automatic
        case fixed
    }

    enum Target: Equatable {
        case automatic
        case level(Double)
    }

    private enum Holder: Equatable {
        case setting
        case night
        case remoteLevel(Double)
        case remoteAutomatic
        case remotePreset
    }

    /// Half of iOS's 0.05 reporting step (plan P-2).
    static let holdTolerance = 0.025
    /// Automatic reporting: at least one step, at most every 5 s (FR-410-09, plan P-4).
    static let reportStep = 0.05
    static let reportInterval: TimeInterval = 5
    /// About a minute of day level after a tap at night (FR-410-18).
    public static let peekDuration: TimeInterval = 60

    private let power: PowerManager
    private let store: any BrightnessSettingsStore
    private let clock: any PowerClock
    private let now: @MainActor () -> Date
    private let calendar: Calendar
    private let tickInterval: Duration
    private let runsTickLoop: Bool

    public private(set) var settings: BrightnessSettings
    /// What every surface reports (Home Assistant, Get Frame State): the held target, or the
    /// value iOS shows in Automatic — published on a step and rate-limited there (FR-410-09).
    public private(set) var reportedBrightness: Double
    /// Whether the night window is active right now (FR-410-19).
    public private(set) var isNightActive = false
    /// Fired when the reported brightness, the effective mode or the night state changes.
    @ObservationIgnored public var onChange: (@MainActor () -> Void)?

    @ObservationIgnored private var holder: Holder = .setting
    @ObservationIgnored private var applied: Target = .automatic
    @ObservationIgnored private var peekUntil: Date?
    @ObservationIgnored private var isSessionActive = false
    @ObservationIgnored private var pendingHandovers = 0
    @ObservationIgnored private var lastReportAt: Date?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    // Event trail for device reports (Framepad 2026-09-29: a peek that never ended). Levels and
    // times only — nothing personal.
    @ObservationIgnored private let log = Logger(subsystem: "ing.kipp.Immich-Slideshow", category: "Brightness")

    public init(
        power: PowerManager,
        store: any BrightnessSettingsStore,
        clock: any PowerClock = RealClock(),
        now: @escaping @MainActor () -> Date = { Date() },
        calendar: Calendar = .current,
        tickInterval: Duration = .seconds(1),
        runsTickLoop: Bool = true
    ) {
        self.power = power
        self.store = store
        self.clock = clock
        self.now = now
        self.calendar = calendar
        self.tickInterval = tickInterval
        self.runsTickLoop = runsTickLoop
        self.settings = store.settings
        self.reportedBrightness = power.currentBrightness
    }

    /// `.automatic` while OwnFrame leaves brightness to iOS, `.fixed` while it holds a level.
    public var effectiveMode: BrightnessMode {
        currentTarget == .automatic ? .automatic : .fixed
    }

    // MARK: - Lifecycle (forwarded to PowerManager)

    /// The slideshow appeared. Derives the level from the time (FR-410-15). Idempotent within a
    /// session: a generation swap's successor appears on the same session and keeps its holder.
    public func activate() async {
        power.activate()
        log.notice("activate: session already active \(self.isSessionActive, privacy: .public), loop \(self.tickTask != nil, privacy: .public)")
        if isSessionActive {
            startTickLoop()
            return
        }
        isSessionActive = true
        holder = .setting
        applied = .automatic
        peekUntil = nil
        isNightActive = settings.night.contains(now(), calendar: calendar)

        if isNightActive {
            capturePreNightBaselineIfNeeded(before: settingTarget)
            holder = .night
            await transition(to: currentTarget, animated: true)
        } else if let missed = store.preNightBaseline {
            // A remembered pre-night value outside the window is a missed window end (the app
            // was not running at the end): hand the day back once.
            store.preNightBaseline = nil
            if settingTarget == .automatic {
                await power.restore(to: missed, animated: true)
            } else {
                await transition(to: currentTarget, animated: true)
            }
        } else {
            await transition(to: currentTarget, animated: true)
        }
        updateReport(force: true)
        // A lifecycle call may have landed while the level was fading in.
        guard isSessionActive, power.isForegroundActive else { return }
        startTickLoop()
    }

    /// Foreground return: the holder stays (an override survives a short background); a window
    /// edge crossed meanwhile is picked up by the next tick (plan P-1). A held level is
    /// re-applied at once (FR-410-03).
    public func willEnterForeground() async {
        power.willEnterForeground()
        log.notice("foreground: session \(self.isSessionActive, privacy: .public), power \(self.power.isForegroundActive, privacy: .public)")
        guard isSessionActive else { return }
        if case .level(let value) = currentTarget {
            await power.setBrightness(value, animated: true)
            applied = currentTarget
        }
        guard isSessionActive, power.isForegroundActive else { return }
        startTickLoop()
    }

    public func didEnterBackground() {
        log.notice("background")
        stopTickLoop()
        power.didEnterBackground()
    }

    public func handOver() {
        pendingHandovers += 1
        power.handOver()
    }

    public func surfaceDisappeared() {
        log.notice("surface disappeared, hand-overs \(self.pendingHandovers, privacy: .public)")
        if pendingHandovers > 0 {
            pendingHandovers -= 1
            power.surfaceDisappeared()
            return
        }
        deactivate()
    }

    /// Exit: stop holding and hand back — the pre-night value outranks a baseline captured at
    /// night (plan P-6); nothing is written if the app never wrote this session.
    public func deactivate() {
        log.notice("deactivate")
        stopTickLoop()
        pendingHandovers = 0
        power.deactivate(restoringTo: store.preNightBaseline)
        // Consumed at exit (plan P-6): a re-entry at night captures afresh, and a daytime
        // launch never mistakes it for a missed window end.
        if isSessionActive {
            store.preNightBaseline = nil
        }
        isSessionActive = false
        peekUntil = nil
        applied = .automatic
        holder = .setting
    }

    // MARK: - In-app events (remembered, FR-410-06)

    public func setMode(_ mode: BrightnessMode) async {
        settings.mode = mode
        store.settings = settings
        await takeOver(.setting, animated: true)
    }

    /// The Fixed slider: follows the finger, so it is not soft-dimmed.
    public func setPreset(_ value: Double) async {
        settings.preset = value
        store.settings = settings
        await takeOver(.setting, animated: false)
    }

    /// A changed night window re-derives the night state from the time, like a launch.
    public func setNightWindow(_ window: NightWindow) async {
        let levelChanged = window.level != settings.night.level
        log.notice("night window: on \(window.isEnabled, privacy: .public) \(window.startMinute, privacy: .public)–\(window.endMinute, privacy: .public) level \(window.level, privacy: .public)")
        settings.night = window
        store.settings = settings
        guard isSessionActive, power.isForegroundActive else { return }
        let inside = window.contains(now(), calendar: calendar)
        if inside != isNightActive {
            await crossWindowEdge(into: inside)
        } else if inside, levelChanged, holder == .night, peekUntil == nil {
            await transition(to: currentTarget, animated: false)
            updateReport(force: true)
        }
    }

    // MARK: - Remote events (session only, FR-410-07)

    public func remoteSetLevel(_ value: Double) async {
        await takeOver(.remoteLevel(min(max(value, 0), 1)), animated: true)
    }

    public func remoteSetMode(_ mode: RemoteMode) async {
        await takeOver(mode == .automatic ? .remoteAutomatic : .remotePreset, animated: true)
    }

    /// Home Assistant's night-window switch (FR-410-19) turns the app's own window on or off.
    public func remoteSetNightWindowEnabled(_ isOn: Bool) async {
        var window = settings.night
        window.isEnabled = isOn
        await setNightWindow(window)
        notifyIfNeeded(force: true)
    }

    // MARK: - Peek (FR-410-18)

    /// A tap at night shows the day level for about a minute; repeated taps extend it.
    public func userTapped() async {
        log.notice("tap: session \(self.isSessionActive, privacy: .public), power \(self.power.isForegroundActive, privacy: .public), night \(self.isNightActive, privacy: .public), loop \(self.tickTask != nil, privacy: .public)")
        guard isSessionActive, power.isForegroundActive, isNightActive else { return }
        let wasPeeking = peekUntil != nil
        peekUntil = now().addingTimeInterval(Self.peekDuration)
        if !wasPeeking {
            await transition(to: currentTarget, animated: true)
            updateReport(force: true)
        }
    }

    // MARK: - The 1 s tick (FR-410-04)

    public func tick() async {
        guard isSessionActive, power.isForegroundActive else { return }
        let date = now()

        let inside = settings.night.contains(date, calendar: calendar)
        if inside != isNightActive {
            await crossWindowEdge(into: inside)
            return
        }

        if let peekUntil, date >= peekUntil {
            log.notice("peek ended")
            self.peekUntil = nil
            await transition(to: currentTarget, animated: true)
            updateReport(force: true)
            return
        }

        if case .level(let target) = currentTarget, !power.isRamping,
           abs(power.currentBrightness - target) > Self.holdTolerance {
            await power.setBrightness(target, animated: false)
        }
        updateReport(force: false)
    }

    // MARK: - Policy

    private var settingTarget: Target {
        settings.mode == .fixed ? .level(settings.preset) : .automatic
    }

    private var holderTarget: Target {
        switch holder {
        case .setting: settingTarget
        case .night: .level(settings.night.level)
        case .remoteLevel(let value): .level(value)
        case .remoteAutomatic: .automatic
        case .remotePreset: .level(settings.preset)
        }
    }

    /// During a peek the day level shows: the preset, or in Automatic the brightness from
    /// before the night.
    private var dayTarget: Target {
        if settings.mode == .fixed { return .level(settings.preset) }
        return .level(automaticReturnValue ?? power.currentBrightness)
    }

    private var currentTarget: Target {
        peekUntil == nil ? holderTarget : dayTarget
    }

    /// Where Automatic hands back to: the remembered pre-night brightness, else the session
    /// baseline if the app wrote this session (FR-410-10/17).
    private var automaticReturnValue: Double? {
        store.preNightBaseline ?? (power.hasChangedBrightness ? power.baseline : nil)
    }

    private func takeOver(_ newHolder: Holder, animated: Bool) async {
        log.notice("take over: \(String(describing: newHolder), privacy: .public)")
        holder = newHolder
        peekUntil = nil
        guard isSessionActive, power.isForegroundActive else { return }
        await transition(to: currentTarget, animated: animated)
        updateReport(force: true)
    }

    private func crossWindowEdge(into inside: Bool) async {
        log.notice("window edge: night \(inside, privacy: .public)")
        isNightActive = inside
        peekUntil = nil
        if inside {
            capturePreNightBaselineIfNeeded(before: holderTarget)
            holder = .night
            await transition(to: currentTarget, animated: true)
        } else {
            let preNight = store.preNightBaseline
            store.preNightBaseline = nil
            holder = .setting
            await transition(to: currentTarget, animated: true, returnValue: preNight)
        }
        updateReport(force: true)
    }

    /// FR-410-17: remembered only when the night starts over Automatic and nothing is stored —
    /// a relaunch inside the window must not capture the night level (SC-410-09).
    private func capturePreNightBaselineIfNeeded(before target: Target) {
        guard target == .automatic, store.preNightBaseline == nil else { return }
        store.preNightBaseline = power.currentBrightness
    }

    /// `applied` is recorded before the await: a newer event arriving while this soft dim
    /// runs must see it, or a stale ramp would outlive the event that replaced it.
    private func transition(to target: Target, animated: Bool, returnValue: Double? = nil) async {
        let previous = applied
        applied = target
        switch target {
        case .level(let value):
            await power.setBrightness(value, animated: animated)
        case .automatic:
            let wasHolding: Bool = if case .level = previous { true } else { false }
            if wasHolding || power.isRamping, let value = returnValue ?? automaticReturnValue {
                await power.restore(to: value, animated: animated)
            }
        }
    }

    // MARK: - Reporting

    @ObservationIgnored private var lastNotified: (Double, BrightnessMode, Bool, Bool)?

    private func updateReport(force: Bool) {
        let date = now()
        switch currentTarget {
        case .level(let value):
            if reportedBrightness != value {
                reportedBrightness = value
                lastReportAt = date
            }
        case .automatic:
            let read = power.currentBrightness
            let movedAStep = abs(read - reportedBrightness) >= Self.reportStep - 1e-9
            let rested = lastReportAt.map { date.timeIntervalSince($0) >= Self.reportInterval } ?? true
            if force ? read != reportedBrightness : (movedAStep && rested) {
                reportedBrightness = read
                lastReportAt = date
            }
        }
        notifyIfNeeded(force: false)
    }

    private func notifyIfNeeded(force: Bool) {
        let snapshot = (reportedBrightness, effectiveMode, isNightActive, settings.night.isEnabled)
        if !force, let last = lastNotified, last == snapshot { return }
        let isFirst = lastNotified == nil
        lastNotified = snapshot
        if !isFirst || force {
            onChange?()
        }
    }

    // MARK: - Tick loop

    private func startTickLoop() {
        guard runsTickLoop, tickTask == nil else { return }
        let clock = clock
        let interval = tickInterval
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: interval)
                } catch {
                    return
                }
                guard let self else { return }
                await self.tick()
            }
        }
    }

    private func stopTickLoop() {
        tickTask?.cancel()
        tickTask = nil
    }
}
