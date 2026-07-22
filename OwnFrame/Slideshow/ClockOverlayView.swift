//
//  ClockOverlayView.swift
//  OwnFrame
//
//  The optional clock overlay (510). An ambient layer over the running slideshow
//  in one of three styles — Digits (default) / Pill / Analog — placed in one of six
//  screen places (or Random), sized Room/Cozy per device. It is pure ambience: never
//  interactive (`allowsHitTesting(false)`) and it fades out whenever the chrome is
//  visible (FR-510-02, SC-500-07) so the clock and the controls never share the screen.
//  Minute-boundary updates only via `TimelineView(.everyMinute)` — no per-second timers
//  (FR-510-01/SC-510-02). Glass/legibility uses the existing `View+Compat` shims only
//  (FR-510-06).
//

import SwiftUI
import ThemeKit

struct ClockOverlayView: View {
    let settings: ClockSettings
    /// The place to render at. `.random` is resolved to a fixed place by the parent
    /// before it reaches here, so this view treats any residual `.random` defensively.
    let place: ClockPlace
    let idiom: ClockIdiom
    let chromeVisible: Bool

    var body: some View {
        ZStack(alignment: placeAlignment) {
            Color.clear
            // The clock is inserted/removed structurally with a 0.3s opacity transition —
            // the same fade the chrome itself uses (FR-510-02). While the chrome is up the
            // clock is simply gone from the tree, so the clock and chrome are never
            // co-present (SC-500-07); that removal is the vanish signal the UI tests read.
            if !chromeVisible {
                clockBody
                    // Chrome-parity insets (FR-300-33): the same 32/44 margins the chrome
                    // bars use, so the clock never crowds the screen edge.
                    .padding(.horizontal, 32)
                    .padding(.vertical, 44)
                    // One combined, non-overlapping element per clock: id `slideshow.clock`,
                    // with the style exposed as the accessibility value so the UI tests can
                    // assert it.
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("slideshow.clock")
                    .accessibilityValue(settings.style.rawValue)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.3), value: chromeVisible)
    }

    @ViewBuilder
    private var clockBody: some View {
        TimelineView(.everyMinute) { context in
            switch settings.style {
            case .digits:
                DigitsClock(date: context.date, showDate: settings.showDate, pointSize: digitSize)
            case .pill:
                PillClock(date: context.date, showDate: settings.showDate, pointSize: digitSize)
            case .analog:
                AnalogClock(date: context.date, diameter: analogSize)
            }
        }
    }

    private var digitSize: CGFloat { ClockMetrics.digitPointSize(idiom: idiom, size: settings.size) }
    private var analogSize: CGFloat { ClockMetrics.analogDiameter(idiom: idiom, size: settings.size) }

    private var placeAlignment: Alignment {
        switch place {
        case .topLeading: return .topLeading
        case .topCenter: return .top
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomCenter: return .bottom
        case .bottomTrailing, .random: return .bottomTrailing
        }
    }
}

/// 24-hour "HH:mm" time, matching the Quiet Glass mock. Built as a verbatim string on purpose:
/// a `Date.FormatStyle`'s locale is overridden by SwiftUI's environment locale, so a
/// format-style approach followed the device's 12/24-hour setting instead. Fixed 5-char width
/// keeps it on one line and compact on every screen (a 12-hour "10:58 AM" at the Room point
/// size overflowed/wrapped on the iPhone SE).
private func clockTimeString(_ date: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
}

// MARK: - Styles

/// Bare rounded numerals on a soft halo — no box. The halo + layered shadow keep the
/// white glyphs legible over both bright and dark photos without a glass surface.
private struct DigitsClock: View {
    let date: Date
    let showDate: Bool
    let pointSize: CGFloat

    var body: some View {
        VStack(spacing: pointSize * 0.05) {
            Text(verbatim: clockTimeString(date))
                .font(.system(size: pointSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if showDate {
                Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.system(size: pointSize * 0.24, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.55), radius: 8, y: 2)
        .shadow(color: .black.opacity(0.35), radius: 24)
        .padding(.horizontal, pointSize * 0.3)
        .padding(.vertical, pointSize * 0.16)
        .background(
            RadialGradient(
                colors: [.black.opacity(0.28), .black.opacity(0.10), .clear],
                center: .center,
                startRadius: 0,
                endRadius: pointSize * 1.3
            )
        )
    }
}

/// Compact glass capsule (today's chrome language). Deliberately arm's-reach scale; not
/// the default. Uses the shared glass shim (Liquid Glass on 26+, material below).
private struct PillClock: View {
    let date: Date
    let showDate: Bool
    let pointSize: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: pointSize * 0.16) {
            Text(verbatim: clockTimeString(date))
                .font(.system(size: pointSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if showDate {
                Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.system(size: pointSize * 0.34, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .opacity(0.82)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
        .padding(.horizontal, pointSize * 0.34)
        .padding(.vertical, pointSize * 0.18)
        .glassCard(cornerRadius: 999)
    }
}

/// Round glass face with hour + minute hands and four ticks (12/3/6/9). No date line.
private struct AnalogClock: View {
    let date: Date
    let diameter: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(0.55))
                    .frame(width: diameter * 0.032, height: diameter * 0.07)
                    .offset(y: -(diameter * 0.5 - diameter * 0.085))
                    .rotationEffect(.degrees(Double(i) * 90))
            }
            hand(width: diameter * 0.05, length: diameter * 0.25, angle: hourAngle)
            hand(width: diameter * 0.036, length: diameter * 0.37, angle: minuteAngle)
            Circle()
                .fill(.white)
                .frame(width: diameter * 0.08, height: diameter * 0.08)
        }
        .frame(width: diameter, height: diameter)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
        .glassCard(cornerRadius: diameter / 2)
    }

    private func hand(width: CGFloat, length: CGFloat, angle: Angle) -> some View {
        Capsule()
            .fill(.white)
            .frame(width: width, height: length)
            // `.offset` is render-only, so the layout frame centre (the ZStack centre)
            // stays the rotation pivot — the hand swings from the clock centre.
            .offset(y: -length / 2)
            .rotationEffect(angle)
    }

    private var hourAngle: Angle {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = Double((c.hour ?? 0) % 12)
        let m = Double(c.minute ?? 0)
        return .degrees((h + m / 60) / 12 * 360)
    }

    private var minuteAngle: Angle {
        .degrees(Double(Calendar.current.component(.minute, from: date)) / 60 * 360)
    }
}

// MARK: - Seedable RNG for the Random place picker

/// A small deterministic generator (SplitMix64) so `--uitest-clock-seed` makes Random
/// placement reproducible in UI tests; production seeds it from the system generator.
/// `nonisolated` so its `RandomNumberGenerator` conformance stays Sendable-safe under
/// the target's default main-actor isolation (the picker requires `RNG: Sendable`).
nonisolated struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
