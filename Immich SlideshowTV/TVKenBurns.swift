//
//  TVKenBurns.swift
//  Immich SlideshowTV
//
//  Topic 1000 — the tvOS Ken Burns modifier. A direct mirror of the iOS `KenBurnsModifier`:
//  a slow rate-based zoom-out + pan sampled per frame from `KenBurnsDrift`, driven by
//  `TimelineView(.animation(paused:))` (wall-clock elapsed time), NOT `withAnimation`.
//  Driving the motion off the animation/transaction system keeps it from cancelling the
//  photo-swap cross-fade, and it keeps drifting while the outgoing photo fades away. The
//  schedule is paused (never structurally removed) when inactive so toggling pause/Ken Burns
//  never changes view identity and re-triggers the insertion transition.
//

import SlideshowKit
import SwiftUI

struct TVKenBurnsModifier: ViewModifier {
    /// On only when Ken Burns is enabled and the show is actively playing (not paused).
    let isActive: Bool
    /// Per-photo duration; sets the drift rate so every photo completes the same arc.
    let durationSeconds: Double

    /// Wall-clock start of this photo's drift. Fresh per photo (the modifier sits inside the
    /// image's `.id`), re-stamped when the show resumes from pause.
    @State private var startDate: Date?

    private static let drift = KenBurnsDrift()
    private let pan: CGFloat = 24

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isActive)) { context in
            let scale = isActive ? scale(at: context.date) : CGFloat(Self.drift.floorScale)
            let panFraction = CGFloat(Self.drift.panFraction(forScale: Double(scale)))
            content
                .scaleEffect(scale)
                .offset(x: pan * panFraction, y: -pan * panFraction)
        }
        .onAppear { startDate = Date() }
        .onChange(of: isActive) { _, active in
            if active { startDate = Date() }
        }
    }

    private func scale(at date: Date) -> CGFloat {
        guard let startDate else { return CGFloat(Self.drift.startScale) }
        return CGFloat(Self.drift.scale(
            elapsedSeconds: date.timeIntervalSince(startDate),
            durationSeconds: durationSeconds
        ))
    }
}

extension View {
    func tvKenBurns(isActive: Bool, durationSeconds: Double) -> some View {
        modifier(TVKenBurnsModifier(isActive: isActive, durationSeconds: durationSeconds))
    }
}
