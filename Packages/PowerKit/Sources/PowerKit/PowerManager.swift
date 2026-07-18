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

    public func deactivate() {
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
