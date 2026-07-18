import Foundation
import Observation

@MainActor
@Observable
public final class UserDefaultsThemeStore: ThemeSettingsStore {
    private let defaults: UserDefaults

    /// Stored (not a computed wrapper over a private backing field) so that every mutation
    /// — including the deep SwiftUI bindings the live clock rows use, e.g.
    /// `$store.settings.clock.style` — reliably persists via `didSet`, regardless of how
    /// the binding routes the write.
    public var settings: ThemeSettings {
        didSet {
            let clamped = Self.clamp(settings.duration)
            if settings.duration != clamped {
                settings.duration = clamped   // re-enters didSet once, then persists below
                return
            }
            persist(settings)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // didSet does not fire for the initial value assigned in init.
        self.settings = Self.load(from: defaults)
    }

    static func load(from defaults: UserDefaults) -> ThemeSettings {
        var settings = ThemeSettings()

        if let rawValue = defaults.string(forKey: Keys.order),
           let order = PlayOrder(rawValue: rawValue) {
            settings.order = order
        }

        if let object = defaults.object(forKey: Keys.durationSeconds),
           let seconds = secondsValue(from: object) {
            settings.duration = clamp(.seconds(seconds))
        }

        if let rawValue = defaults.string(forKey: Keys.transition),
           let transition = Transition(rawValue: rawValue) {
            settings.transition = transition
        }

        if defaults.object(forKey: Keys.kenBurns) != nil {
            settings.kenBurns = defaults.bool(forKey: Keys.kenBurns)
        }

        if let rawValue = defaults.string(forKey: Keys.fit),
           let fit = ImageFit(rawValue: rawValue) {
            settings.fit = fit
        }

        if let rawValue = defaults.string(forKey: Keys.quality),
           let quality = ImageQuality(rawValue: rawValue) {
            settings.quality = quality
        }

        if defaults.object(forKey: Keys.clockIsOn) != nil {
            settings.clock.isOn = defaults.bool(forKey: Keys.clockIsOn)
        }

        if let rawValue = defaults.string(forKey: Keys.clockStyle),
           let style = ClockStyle(rawValue: rawValue) {
            settings.clock.style = style
        }

        // The `theme.clock.corner` key now holds a `ClockPlace` raw. Legacy corner
        // raws are a subset, so they decode unchanged; an unknown raw leaves the
        // default place (never a startup failure).
        if let rawValue = defaults.string(forKey: Keys.clockCorner),
           let place = ClockPlace(rawValue: rawValue) {
            settings.clock.place = place
        }

        if let rawValue = defaults.string(forKey: Keys.clockSize),
           let size = ClockSize(rawValue: rawValue) {
            settings.clock.size = size
        }

        if defaults.object(forKey: Keys.clockShowDate) != nil {
            settings.clock.showDate = defaults.bool(forKey: Keys.clockShowDate)
        }

        return settings
    }

    static func clamp(_ duration: Duration) -> Duration {
        min(max(duration, ThemeSettings.durationRange.lowerBound), ThemeSettings.durationRange.upperBound)
    }

    private func persist(_ settings: ThemeSettings) {
        defaults.set(settings.order.rawValue, forKey: Keys.order)
        defaults.set(Self.seconds(from: settings.duration), forKey: Keys.durationSeconds)
        defaults.set(settings.transition.rawValue, forKey: Keys.transition)
        defaults.set(settings.kenBurns, forKey: Keys.kenBurns)
        defaults.set(settings.fit.rawValue, forKey: Keys.fit)
        defaults.set(settings.quality.rawValue, forKey: Keys.quality)
        defaults.set(settings.clock.isOn, forKey: Keys.clockIsOn)
        defaults.set(settings.clock.style.rawValue, forKey: Keys.clockStyle)
        defaults.set(settings.clock.place.rawValue, forKey: Keys.clockCorner)
        defaults.set(settings.clock.size.rawValue, forKey: Keys.clockSize)
        defaults.set(settings.clock.showDate, forKey: Keys.clockShowDate)
    }

    private static func seconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    private static func secondsValue(from object: Any) -> Double? {
        guard let number = object as? NSNumber else {
            return nil
        }

        let seconds = number.doubleValue
        return seconds.isFinite ? seconds : nil
    }

    private enum Keys {
        static let order = "theme.order"
        static let durationSeconds = "theme.durationSeconds"
        static let transition = "theme.transition"
        static let kenBurns = "theme.kenBurns"
        static let fit = "theme.fit"
        static let quality = "theme.quality"
        static let clockIsOn = "theme.clock.isOn"
        // Key name kept for back-compat; now holds a `ClockPlace` raw.
        static let clockCorner = "theme.clock.corner"
        static let clockStyle = "theme.clock.style"
        static let clockSize = "theme.clock.size"
        static let clockShowDate = "theme.clock.showDate"
    }
}
