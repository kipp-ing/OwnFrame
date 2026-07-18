//
//  UIScreenController.swift
//  Immich Slideshow
//
//  Real `ScreenControlling` implementation backing the PowerManager: maps onto
//  the live device screen brightness and the idle/auto-lock timer. Kept in the
//  app target so PowerKit stays UIKit-free and host-testable (Konstitution II).
//  Foreground-only effects (idle timer, brightness) are guaranteed by the
//  PowerManager's gating, not here (Konstitution V).
//

import PowerKit
import UIKit

@MainActor
final class UIScreenController: ScreenControlling {
    // iOS 26 deprecated `UIScreen.main`; resolve the screen from the app's active
    // window scene instead (Apple's recommended `windowScene.screen` path). This is
    // also correct under Stage Manager / external displays, where the window may not
    // be on the built-in screen. `UIScreen.brightness` only affects the built-in
    // screen, so brightness writes no-op elsewhere — by design.
    private var activeScreen: UIScreen? {
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        return (windowScenes.first { $0.activationState == .foregroundActive } ?? windowScenes.first)?.screen
    }

    var brightness: Double {
        // Fall back BRIGHT when no window scene resolves (scene activation, Stage
        // Manager/external-display transitions): consumers seed UI from this value
        // (settings slider) and a 0 fallback would read as — and then commit — black.
        get { Double(activeScreen?.brightness ?? 1.0) }
        set {
            guard let screen = activeScreen else { return }
            // Allow dimming below the hardware minimum (software-emulated) so the
            // slideshow can reach a near-black "night" level — we can dim the panel
            // but never power it off (Konstitution V / project constraints).
            screen.wantsSoftwareDimming = true
            screen.brightness = CGFloat(newValue)
        }
    }

    var isIdleTimerDisabled: Bool {
        get { UIApplication.shared.isIdleTimerDisabled }
        set { UIApplication.shared.isIdleTimerDisabled = newValue }
    }
}
