public struct ThemeSettings: Sendable, Equatable {
    public var order: PlayOrder
    public var duration: Duration
    public var transition: Transition
    public var kenBurns: Bool
    public var fit: ImageFit
    public var quality: ImageQuality
    public var clock: ClockSettings

    public static let durationRange: ClosedRange<Duration> = .seconds(3)...(.seconds(600))

    /// Quick-pick duration values surfaced in the settings picker — a curated subset
    /// of `durationRange`, kept sorted.
    public static let durationPresets: [Duration] = [
        .seconds(5), .seconds(10), .seconds(15), .seconds(30), .seconds(60), .seconds(300)
    ]

    /// Picker options that always include `current`, so the current selection is never
    /// unrepresentable. Home Assistant can set any integer in `durationRange` (min 3,
    /// max 600, step 1), and that value is retained on the MQTT broker across a device
    /// reinstall; a non-preset selection with no matching picker tag renders blank.
    /// Merging `current` into the presets (sorted) guarantees a matching tag.
    public static func durationOptions(including current: Duration) -> [Duration] {
        guard !durationPresets.contains(current) else { return durationPresets }
        return (durationPresets + [current]).sorted()
    }

    public init(
        order: PlayOrder = .shuffle,
        duration: Duration = .seconds(15),
        transition: Transition = .crossfade,
        kenBurns: Bool = false,
        fit: ImageFit = .fit,
        quality: ImageQuality = .preview,
        clock: ClockSettings = .off
    ) {
        self.order = order
        self.duration = duration
        self.transition = transition
        self.kenBurns = kenBurns
        self.fit = fit
        self.quality = quality
        self.clock = clock
    }
}

public enum PlayOrder: String, Sendable, Equatable, CaseIterable {
    case shuffle
    case sequential
}

public enum Transition: String, Sendable, Equatable, CaseIterable {
    case crossfade
    case slide
    case dissolve
    case `none`
}

public enum ImageFit: String, Sendable, Equatable, CaseIterable {
    case fit
    case fill
}

public enum ImageQuality: String, Sendable, Equatable, CaseIterable {
    case preview
    case original
}

public enum ClockStyle: String, Sendable, Equatable, CaseIterable {
    case digits   // default — bare rounded numerals on a soft halo
    case pill     // compact glass capsule (today's design language)
    case analog   // round glass face, hour + minute hands, no date line
}

/// Supersedes the old `ClockCorner`. The four corner cases keep their exact raw
/// values, so values stored under `theme.clock.corner` (and HA retained states)
/// decode unchanged (FR-510-05).
public enum ClockPlace: String, Sendable, Equatable, CaseIterable {
    case topLeading
    case topCenter
    case topTrailing
    case bottomLeading
    case bottomCenter
    case bottomTrailing  // default
    case random          // relocates per RandomPlacePicking (FR-510-03)

    /// The fixed places Random draws from: `allCases` minus `.random`.
    public static var fixedPlaces: [ClockPlace] { allCases.filter { $0 != .random } }
}

public enum ClockSize: String, Sendable, Equatable, CaseIterable {
    case room   // default — readable from ~1.5 m (SC-500-08 floor)
    case cozy   // arm's-reach placement
}

public struct ClockSettings: Sendable, Equatable {
    public var isOn: Bool
    public var style: ClockStyle
    public var place: ClockPlace
    public var size: ClockSize
    public var showDate: Bool

    public static let off = ClockSettings()

    public init(
        isOn: Bool = false,
        style: ClockStyle = .digits,
        place: ClockPlace = .bottomTrailing,
        size: ClockSize = .room,
        showDate: Bool = false
    ) {
        self.isOn = isOn
        self.style = style
        self.place = place
        self.size = size
        self.showDate = showDate
    }
}
