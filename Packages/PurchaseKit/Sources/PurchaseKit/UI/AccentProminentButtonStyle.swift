import SwiftUI

/// The filled accent button style: `.borderedProminent` with a near-black label pinned on top.
///
/// On the Messing accent fill `#E3A857` (FR-9000-14) SwiftUI may pick a white label, which fails
/// WCAG AA contrast. This style keeps every system metric of `.borderedProminent` — control size,
/// border shape, pressed highlight, focus and disabled treatment — and only overrides the label's
/// foreground to ``labelColor`` (FR-9000-38). It is the one shared style for filled accent
/// controls; call sites read `.buttonStyle(.accentProminent)`.
///
/// Pressed and disabled states stay the system's: the pressed highlight is drawn by
/// `.borderedProminent`, and while the button is disabled the label pin is lifted so the system's
/// dimmed label on its neutral disabled fill shows instead of a black label that reads as active.
public struct AccentProminentButtonStyle: PrimitiveButtonStyle {
    /// An sRGB color expressed as components in `0...1`, readable by contrast tests.
    public struct SRGB: Sendable, Equatable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// The SwiftUI color for these components in the sRGB color space.
        public var color: Color {
            Color(.sRGB, red: red, green: green, blue: blue)
        }
    }

    /// The pinned label color, `#000000`.
    public static let labelColor = SRGB(red: 0, green: 0, blue: 0)

    /// The accent fill the label is judged against: Messing `#E3A857` (FR-9000-14). A reference
    /// for contrast checks only — the fill itself still comes from the environment's tint.
    public static let accentReference = SRGB(
        red: Double(0xE3) / 255,
        green: Double(0xA8) / 255,
        blue: Double(0x57) / 255
    )

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            PinnedLabel(label: configuration.label)
        }
        .buttonStyle(.borderedProminent)
    }

    /// Applies the label pin innermost, so it wins over the foreground `.borderedProminent`
    /// sets from outside, and only while the button is enabled.
    private struct PinnedLabel: View {
        let label: Configuration.Label
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            if isEnabled {
                label.foregroundStyle(AccentProminentButtonStyle.labelColor.color)
            } else {
                label
            }
        }
    }
}

extension PrimitiveButtonStyle where Self == AccentProminentButtonStyle {
    /// The filled accent style with a near-black label (FR-9000-38).
    public static var accentProminent: AccentProminentButtonStyle { AccentProminentButtonStyle() }
}
