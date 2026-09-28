import Observation

@MainActor
@Observable
public final class PowerManager {
    private let screen: any ScreenControlling
    private let clock: any PowerClock
    private let config: PowerConfig
    private var isForegroundActive = false
    private var baselineBrightness: Double?
    private var didChangeBrightness = false
    private var rampTask: Task<Void, Never>?
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

        await rampTask?.value
        if rampTask?.isCancelled == false {
            rampTask = nil
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
        pendingHandovers = 0
        rampTask?.cancel()
        rampTask = nil
        screen.isIdleTimerDisabled = false
        isKeepingAwake = false

        if didChangeBrightness, let baselineBrightness {
            screen.brightness = baselineBrightness
        }

        baselineBrightness = nil
        didChangeBrightness = false
        isForegroundActive = false
    }
}
