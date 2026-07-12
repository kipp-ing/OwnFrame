//
//  KenBurnsModifier.swift
//  Immich Slideshow
//
//  008 / US2 — opt-in slow pan/zoom over the current photo (off by default, calm
//  default preserved). Each photo gets a fresh modifier identity via the image's
//  `.id`, so the motion restarts per photo from its base; it resets cleanly when the
//  show is paused. The motion duration follows the live per-photo duration (review R4).
//
//  The motion is deliberately driven by TimelineView (wall-clock per frame), NOT by
//  `withAnimation` on @State: a state animation started while a photo swap is in
//  flight cancels the swap's transition animations — the outgoing photo popped out
//  instantly (hard cut to black) and the incoming fade froze mid-way. TimelineView
//  recomputes values outside the animation/transaction system, so it cannot interfere
//  with the transitions, and it keeps ticking while the outgoing photo fades away.
//
//  The zoom-out is rate-based (see KenBurnsDrift): a constant scale-per-second rate
//  that is still in motion at the expected swap moment and keeps drifting through the
//  grace headroom when the swap lands late (device image-load latency). The old
//  span-based progress clamped at scale 1.0 — every late swap left the photo standing
//  still, and the next photo's motion read as a fast "catch-up". Because the rate is
//  identical for the outgoing and the incoming photo, the perceived motion is one
//  continuous drift through every cross-fade.
//

import SlideshowKit
import SwiftUI

struct KenBurnsModifier: ViewModifier {
    /// On only when Ken Burns is enabled and the show is actively playing (not paused).
    let isActive: Bool
    /// Per-photo duration; sets the drift rate so every photo completes the same arc.
    let durationSeconds: Double

    /// Wall-clock start of this photo's drift. Fresh per photo (the modifier sits
    /// inside the image's `.id`), re-stamped when the show resumes from pause.
    @State private var startDate: Date?

    /// Zoom OUT, not in: each photo starts tight (zoomed + nudged off-center) and
    /// keeps revealing more of the picture. Scale stays >= 1 (the photo is rendered
    /// fill-framed while Ken Burns is on) and the pan offset shrinks proportionally
    /// with the zoom, so the photo edge never enters the screen.
    private static let drift = KenBurnsDrift()
    private let pan: CGFloat = 16

    func body(content: Content) -> some View {
        // The schedule pauses (instead of the TimelineView being structurally removed)
        // when inactive, so toggling pause/Ken Burns never changes the view's identity —
        // an identity change here would re-trigger the photo's insertion transition.
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

    /// Constant-rate zoom-out; `startScale` is also the pre-`onAppear` state so the
    /// first rendered frame matches the drift's own starting point (no jump).
    private func scale(at date: Date) -> CGFloat {
        guard let startDate else { return CGFloat(Self.drift.startScale) }
        return CGFloat(Self.drift.scale(
            elapsedSeconds: date.timeIntervalSince(startDate),
            durationSeconds: durationSeconds
        ))
    }
}

extension View {
    func kenBurns(isActive: Bool, durationSeconds: Double) -> some View {
        modifier(KenBurnsModifier(isActive: isActive, durationSeconds: durationSeconds))
    }
}
