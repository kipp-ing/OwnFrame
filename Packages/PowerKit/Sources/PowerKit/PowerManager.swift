import Observation

@MainActor
@Observable
public final class PowerManager {
    private let screen: any ScreenControlling
    private let clock: any PowerClock
    private let config: PowerConfig
    public private(set) var isForegroundActive = false
    private var baselineBrightness: Double?
    private var didChangeBrightness = false
    private var rampTask: Task<Void, Never>?
    /// Bumped by every brightness request, so a restore can tell whether a newer write
    /// landed while its soft dim ran (410 review).
    private var writeGeneration = 0

    /// The brightness captured when this foreground session began (FR-400-10).
    public var baseline: Double? { baselineBrightness }
    /// Whether the app wrote brightness in this session, so an exit restores (FR-400-11).
    public var hasChangedBrightness: Bool { didChangeBrightness }
    /// A soft dim is in flight; a hold loop must not fight it (410, FR-410-04).
    public var isRamping: Bool { rampTask != nil }
    private var pendingHandovers = 0

    public private(set) var isKeepingAwake = false

    /// Current brightness read *through* the `ScreenControlling` seam — the live panel
    /// brightness on iOS, the software-dim level on tvOS. Lets UI (e.g. the settings
    /// brightness slider) seed itself without reaching past the seam to `UIScreen`
    /// directly (FR-1000-07: eliminate the bypass rather than duplicate it).
    public var currentBrightness: Double { screen.brightness }

    public init(
        screen: any ScreenControlling,
        clock: any PowerClock = RealClock(),
        config: PowerConfig = .default
    ) {
        self.screen = screen
        self.clock = clock
        self.config = config
    }

    public func activate() {
        if baselineBrightness == nil {
            baselineBrightness = screen.brightness
        }
        isForegroundActive = true
        screen.isIdleTimerDisabled = true
        isKeepingAwake = true
    }

    public func setBrightness(_ value: Double, animated: Bool) async {
        let target = min(max(value, 0.0), 1.0)

        guard isForegroundActive else {
            return
        }

        didChangeBrightness = true
        writeGeneration += 1
        rampTask?.cancel()
        rampTask = nil

        guard animated else {
            screen.brightness = target
            return
        }

        let start = screen.brightness
        let steps = config.softDimSteps
        let stepDuration = config.softDimDuration / steps
        let clock = clock
        rampTask = Task { @MainActor [weak self] in
            for index in 1...steps {
                do {
                    try await clock.sleep(for: stepDuration)
                } catch {
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                let progress = Double(index) / Double(steps)
                let nextValue = index == steps ? target : start + (target - start) * progress
                self?.screen.brightness = nextValue
            }
        }

        let task = rampTask
        await task?.value
        if rampTask == task {
            rampTask = nil
        }
    }

    /// 410 (FR-410-10): hand brightness back to iOS — move to `value` once, then the session
    /// counts as unchanged, so the exit restore does not write again.
    public func restore(to value: Double, animated: Bool) async {
        guard isForegroundActive else { return }
        // `setBrightness` bumps the generation before its first suspension.
        let generation = writeGeneration + 1
        await setBrightness(value, animated: animated)
        // Only if no newer write replaced this restore while it ran.
        if generation == writeGeneration, !isRamping {
            didChangeBrightness = false
        }
    }

    public func didEnterBackground() {
        isForegroundActive = false
        rampTask?.cancel()
        rampTask = nil
        screen.isIdleTimerDisabled = false
        isKeepingAwake = false
    }

    public func willEnterForeground() {
        guard baselineBrightness != nil else {
            return
        }
        isForegroundActive = true
        screen.isIdleTimerDisabled = true
        isKeepingAwake = true
    }

    /// A successor surface is about to replace the current one — a slideshow generation swap
    /// (issue #91). The outgoing surface's disappear then belongs to the swap, not to an exit:
    /// the session (baseline, the level set so far, keep-awake) passes to the successor.
    /// SwiftUI does not order the old disappear against the new appear, so this is announced
    /// up front instead of inferred from the order.
    public func handOver() {
        pendingHandovers += 1
    }

    /// The slideshow surface went away. Consumes a pending ``handOver()`` and keeps the
    /// session; without one it is a genuine exit and tears down like ``deactivate()``.
    public func surfaceDisappeared() {
        if pendingHandovers > 0 {
            pendingHandovers -= 1
            return
        }
        deactivate()
    }

    /// Unconditional teardown (e.g. reset): restores the baseline, releases keep-awake, and
    /// drops any hand-over whose outgoing disappear never fired (a swap under a modal cover).
    public func deactivate() {
        deactivate(restoringTo: nil)
    }

    /// Teardown that restores `value` instead of the session baseline (410: the pre-night
    /// brightness outranks a baseline captured during the night). Still only if the app wrote.
    public func deactivate(restoringTo value: Double?) {
        pendingHandovers = 0
        rampTask?.cancel()
        rampTask = nil
        screen.isIdleTimerDisabled = false
        isKeepingAwake = false

        if didChangeBrightness, let restore = value ?? baselineBrightness {
            screen.brightness = restore
        }

        baselineBrightness = nil
        didChangeBrightness = false
        isForegroundActive = false
    }
}
