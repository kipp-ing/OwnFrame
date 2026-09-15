//
//  View+Compat.swift
//  OwnFrame
//
//  iOS-version-compatibility shims so the slideshow chrome compiles and degrades
//  gracefully below iOS 26. The app supports iPadOS 17+, but the calm photo-frame
//  chrome uses iOS 26 Liquid Glass. Below 26 these helpers draw the "soft glass" tier of
//  the design record (`docs/design/quiet-glass-2026-07-18.html`): the same material with a
//  dark tint baked in, so white symbols always sit on a mid-dark ground (300, FR-300-34).
//

import SwiftUI

/// The soft-glass tier's tint (300 T003): the design record's soft-glass CSS value,
/// `rgba(24,24,27,.38)`. Jan chose it over the implementation map's "≈ 0.2 black" on
/// 2026-09-15, because only this one keeps a white glyph at 3:1 over a white photo.
nonisolated enum SoftGlass {
    static let tint: (red: Double, green: Double, blue: Double) = (24.0 / 255, 24.0 / 255, 27.0 / 255)
    static let tintOpacity: Double = 0.38

    static var tintColor: Color {
        Color(.sRGB, red: tint.red, green: tint.green, blue: tint.blue)
    }
}

extension View {
    /// Liquid Glass card on iOS 26; soft glass below. `scrim` adds one in-shape dark layer in the
    /// tint color at that opacity (310, FR-310-15): over the glass on iOS 26, and in place of the
    /// tier tint below it whenever it is darker, so the two never stack. Without a scrim the
    /// iOS 26 path is the plain glass card.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat, scrim: Double? = nil) -> some View {
        if #available(iOS 26, *) {
            if let scrim {
                background(SoftGlass.tintColor.opacity(scrim), in: RoundedRectangle(cornerRadius: cornerRadius))
                    .glassEffect(in: .rect(cornerRadius: cornerRadius))
            } else {
                glassEffect(in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            softGlass(in: RoundedRectangle(cornerRadius: cornerRadius), tint: max(SoftGlass.tintOpacity, scrim ?? 0))
        }
    }

    /// Capsule in the same tier, for caption and clock pills: Liquid Glass on iOS 26, soft glass below.
    @ViewBuilder
    func glassPill() -> some View {
        if #available(iOS 26, *) {
            glassEffect(in: .capsule)
        } else {
            softGlass(in: Capsule(), tint: SoftGlass.tintOpacity)
        }
    }

    /// Liquid Glass button style on iOS 26; the soft-glass button below.
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(SoftGlassButtonStyle())
        }
    }

    /// Page-sized sheet on iOS 18+; default sheet sizing below (iOS 17).
    @ViewBuilder
    func pageSizedSheet() -> some View {
        if #available(iOS 18, *) {
            presentationSizing(.page)
        } else {
            self
        }
    }

    /// The soft-glass ground: ultraThinMaterial with the tint baked into the same shape.
    fileprivate func softGlass<S: Shape>(in shape: S, tint: Double) -> some View {
        background {
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(SoftGlass.tintColor.opacity(tint)))
        }
    }
}

/// The soft-glass button (below iOS 26): a capsule of ultraThinMaterial plus the tier tint behind
/// a white label, dimmed while pressed. Its only caller is the chrome's round icon buttons, which
/// give the label a square frame, so the capsule draws a circle; the style adds no padding.
private struct SoftGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .softGlass(in: Capsule(), tint: SoftGlass.tintOpacity)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// Groups sibling Liquid Glass surfaces so they blend on iOS 26; a plain
/// pass-through of the content below.
@ViewBuilder
func glassGroup<Content: View>(
    spacing: CGFloat,
    @ViewBuilder content: () -> Content
) -> some View {
    if #available(iOS 26, *) {
        GlassEffectContainer(spacing: spacing) { content() }
    } else {
        content()
    }
}
