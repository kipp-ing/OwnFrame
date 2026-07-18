import Foundation

@MainActor
public protocol PlaybackControlling: AnyObject {
    var playbackState: PlaybackState { get }
    var brightness: Double { get }
    var albumOptions: [String] { get }
    var currentAlbum: String? { get }
    func pause()
    func resume()
    func setBrightness(_ value: Double) async
    func selectAlbum(_ name: String)
    var onLocalChange: (@MainActor () -> Void)? { get set }
}

@MainActor
public protocol SettingsControlling: AnyObject {
    var themeSettings: ThemeSettingsSnapshot { get }
    func apply(_ settings: ThemeSettingsSnapshot)
    var onSettingsChange: (@MainActor () -> Void)? { get set }
}

public struct ThemeSettingsSnapshot: Sendable, Equatable {
    public var order: PlayOrderSetting
    public var durationSeconds: Int
    public var transition: TransitionSetting
    public var kenBurns: Bool
    public var fit: FitSetting
    public var quality: QualitySetting
    public var clockOn: Bool
    public var clockPlace: ClockCornerSetting
    public var clockStyle: ClockStyleSetting
    public var clockSize: ClockSizeSetting
    public var clockDate: Bool

    public init(
        order: PlayOrderSetting,
        durationSeconds: Int,
        transition: TransitionSetting,
        kenBurns: Bool,
        fit: FitSetting,
        quality: QualitySetting,
        clockOn: Bool,
        clockPlace: ClockCornerSetting,
        clockStyle: ClockStyleSetting,
        clockSize: ClockSizeSetting,
        clockDate: Bool
    ) {
        self.order = order
        self.durationSeconds = durationSeconds
        self.transition = transition
        self.kenBurns = kenBurns
        self.fit = fit
        self.quality = quality
        self.clockOn = clockOn
        self.clockPlace = clockPlace
        self.clockStyle = clockStyle
        self.clockSize = clockSize
        self.clockDate = clockDate
    }
}

public enum PlayOrderSetting: String, Sendable, Equatable, CaseIterable {
    case shuffle
    case sequential
}

public enum TransitionSetting: String, Sendable, Equatable, CaseIterable {
    case crossfade
    case slide
    case dissolve
    case `none`
}

public enum FitSetting: String, Sendable, Equatable, CaseIterable {
    case fit
    case fill
}

public enum QualitySetting: String, Sendable, Equatable, CaseIterable {
    case preview
    case original
}

public enum ClockCornerSetting: String, Sendable, Equatable, CaseIterable {
    // Raw values of the four original corners stay identical (stored values + HA
    // retained states decode unchanged, FR-510-05); two centers and Random are added.
    case topLeading
    case topCenter
    case topTrailing
    case bottomLeading
    case bottomCenter
    case bottomTrailing
    case random
}

public enum ClockStyleSetting: String, Sendable, Equatable, CaseIterable {
    case digits
    case pill
    case analog
}

public enum ClockSizeSetting: String, Sendable, Equatable, CaseIterable {
    case room
    case cozy
}
