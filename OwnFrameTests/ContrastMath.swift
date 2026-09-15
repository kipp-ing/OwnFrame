//
//  ContrastMath.swift
//  OwnFrameTests
//
//  WCAG 2.x relative luminance and contrast ratio, plus source-over alpha compositing in sRGB,
//  for the legibility bounds in SoftGlassTierTests (FR-300-34) and NewPhotosCardScrimTests
//  (FR-310-15). Blur and material are deliberately ignored, so every bound is a lower bound.
//

import Foundation

enum ContrastMath {
    typealias RGB = (red: Double, green: Double, blue: Double)

    static let white: RGB = (1, 1, 1)

    /// `layer` at `opacity` drawn over `base`, per channel, in sRGB (how SwiftUI blends fills).
    static func composite(_ layer: RGB, opacity: Double, over base: RGB) -> RGB {
        func mix(_ l: Double, _ b: Double) -> Double { l * opacity + b * (1 - opacity) }
        return (mix(layer.red, base.red), mix(layer.green, base.green), mix(layer.blue, base.blue))
    }

    static func relativeLuminance(_ color: RGB) -> Double {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    static func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
