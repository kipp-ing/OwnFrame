import Foundation
import Testing
@testable import PurchaseKit

// T004 — the filled accent control's label must stay legible on Messing `#E3A857`.
//
// SwiftUI's `.borderedProminent` may pick a white label on the accent fill, which fails WCAG
// contrast. `AccentProminentButtonStyle` pins a near-black label; this test computes the WCAG 2.x
// contrast ratio from the style's public sRGB constants rather than asserting a literal ratio.

/// WCAG 2.x relative luminance of an sRGB color (components in 0...1).
private func relativeLuminance(_ color: AccentProminentButtonStyle.SRGB) -> Double {
    func linearize(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linearize(color.red)
        + 0.7152 * linearize(color.green)
        + 0.0722 * linearize(color.blue)
}

/// WCAG 2.x contrast ratio between two colors, always ≥ 1.
private func contrastRatio(
    _ first: AccentProminentButtonStyle.SRGB,
    _ second: AccentProminentButtonStyle.SRGB
) -> Double {
    let a = relativeLuminance(first)
    let b = relativeLuminance(second)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

/// The accent reference is Messing `#E3A857` (FR-9000-14) and the pinned label is `#000000`.
// @covers FR-9000-38
@Test func accentProminentConstantsMatchTheDecidedHexValues() {
    let accent = AccentProminentButtonStyle.accentReference
    #expect(accent.red == Double(0xE3) / 255)
    #expect(accent.green == Double(0xA8) / 255)
    #expect(accent.blue == Double(0x57) / 255)

    let label = AccentProminentButtonStyle.labelColor
    #expect(label.red == 0)
    #expect(label.green == 0)
    #expect(label.blue == 0)
}

/// The pinned label on the accent fill meets WCAG AA for normal text (≥ 4.5:1).
// @covers FR-9000-38
@Test func accentProminentLabelMeetsWCAGAAOnTheAccentFill() {
    let ratio = contrastRatio(
        AccentProminentButtonStyle.labelColor,
        AccentProminentButtonStyle.accentReference
    )
    #expect(ratio >= 4.5, "label/accent contrast is \(ratio):1")
}

/// Guard against the failure the style exists to prevent: a white label would not pass.
// @covers FR-9000-38
@Test func whiteLabelOnTheAccentFillWouldFailWCAGAA() {
    let white = AccentProminentButtonStyle.SRGB(red: 1, green: 1, blue: 1)
    #expect(contrastRatio(white, AccentProminentButtonStyle.accentReference) < 4.5)
}
