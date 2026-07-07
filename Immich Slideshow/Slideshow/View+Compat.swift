//
//  View+Compat.swift
//  Immich Slideshow
//
//  iOS-version-compatibility shims so the slideshow chrome compiles and degrades
//  gracefully below iOS 26. The app supports iPadOS 17+, but the calm photo-frame
//  chrome uses iOS 26 Liquid Glass; these helpers keep the 26 look where available
//  and fall back to a plain material / bordered style on iOS 17-25.
//

import SwiftUI

extension View {
    /// Liquid Glass card background on iOS 26; ultraThinMaterial fallback below.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26, *) {
            glassEffect(in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// Liquid Glass button style on iOS 26; bordered fallback below.
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
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