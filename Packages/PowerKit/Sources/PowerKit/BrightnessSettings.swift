import Foundation

/// 410 (FR-410-01): whether OwnFrame leaves brightness to iOS or holds a level.
public enum BrightnessMode: String, Sendable, Equatable, Codable, CaseIterable {
    case automatic
    case fixed
}

/// 410 (FR-410-13): a from–to window in local wall-clock time inside which the frame is very
/// dim. Evaluated on every check, so midnight, DST and time-zone changes need no special case.
public struct NightWindow: Sendable, Equatable, Codable {
    /// The night level stays at the dark end of the range (plan P-3).
    public static let maxLevel = 0.3

    public var isEnabled: Bool
    /// Minutes after local midnight, 0..<1440.
    public var startMinute: Int
    public var endMinute: Int
    /// 0.0 is the darkest the frame shows: the hardware minimum plus the software dim the iOS
    /// screen controller turns on with every write.
    public var level: Double {
        didSet { level = Self.clampLevel(level) }
    }

    public init(isEnabled: Bool = false, startMinute: Int = 23 * 60, endMinute: Int = 7 * 60, level: Double = 0.0) {
        self.isEnabled = isEnabled
        self.startMinute = Self.clampMinute(startMinute)
        self.endMinute = Self.clampMinute(endMinute)
        self.level = Self.clampLevel(level)
    }

    /// Start is inside, end is outside; `start == end` means no window.
    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        guard isEnabled, startMinute != endMinute else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if startMinute < endMinute {
            return minute >= startMinute && minute < endMinute
        }
        return minute >= startMinute || minute < endMinute
    }

    private static func clampLevel(_ value: Double) -> Double { min(max(value, 0), maxLevel) }
    private static func clampMinute(_ value: Int) -> Int { min(max(value, 0), 24 * 60 - 1) }
}

/// 410: the remembered brightness choices — changed only through the in-app control
/// (D-410-2, FR-410-06). Ordinary settings, not secrets (FR-410-12).
public struct BrightnessSettings: Sendable, Equatable, Codable {
    public var mode: BrightnessMode
    public var preset: Double {
        didSet { preset = min(max(preset, 0), 1) }
    }
    public var night: NightWindow

    public init(mode: BrightnessMode = .automatic, preset: Double = 0.6, night: NightWindow = NightWindow()) {
        self.mode = mode
        self.preset = min(max(preset, 0), 1)
        self.night = night
    }
}

@MainActor
public protocol BrightnessSettingsStore: AnyObject {
    var settings: BrightnessSettings { get set }
    /// The brightness captured when a night began in Automatic; restored once at its end
    /// (FR-410-17). Survives relaunches so a night relaunch never restores the night level.
    var preNightBaseline: Double? { get set }
}

@MainActor
public final class InMemoryBrightnessStore: BrightnessSettingsStore {
    public var settings: BrightnessSettings
    public var preNightBaseline: Double?

    public init(settings: BrightnessSettings = BrightnessSettings(), preNightBaseline: Double? = nil) {
        self.settings = settings
        self.preNightBaseline = preNightBaseline
    }
}

@MainActor
public final class UserDefaultsBrightnessStore: BrightnessSettingsStore {
    private static let settingsKey = "brightness.settings.v1"
    private static let preNightKey = "brightness.preNightBaseline"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var settings: BrightnessSettings {
        get {
            guard let data = defaults.data(forKey: Self.settingsKey),
                  let decoded = try? JSONDecoder().decode(BrightnessSettings.self, from: data) else {
                return BrightnessSettings()
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.settingsKey)
            }
        }
    }

    public var preNightBaseline: Double? {
        get { defaults.object(forKey: Self.preNightKey) as? Double }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Self.preNightKey)
            } else {
                defaults.removeObject(forKey: Self.preNightKey)
            }
        }
    }
}
