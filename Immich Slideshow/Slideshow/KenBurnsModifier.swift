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
//  with the transitions, and it keeps ticking while the outgoing photo fades away —
//  the drift never visibly stops across a swap.
//

import SwiftUI

struct KenBurnsModifier: ViewModifier {
    /// On only when Ken Burns is enabled and the show is actively playing (not paused).
    let isActive: Bool
    /// Per-photo duration; the pan/zoom spans the time the photo is on screen.
    let durationSeconds: Double

    /// Wall-clock start of this photo's drift. Fresh per photo (the modifier sits
    /// inside the image's `.id`), re-stamped when the show resumes from pause.
    @State private var startDate: Date?

    // Zoom OUT, not in: each photo starts tight (zoomed + nudged off-center) and settles
    // onto the full frame, so the motion keeps revealing more of the picture. Scale stays
    // >= 1 (the photo is rendered fill-framed while Ken Burns is on) and the pan offset
    // shrinks proportionally with the zoom, so the photo edge never enters the screen —
    // no letterbox gap at any point of the motion.
    private let startScale: CGFloat = 1.12
    private let endScale: CGFloat = 1.0
    private let pan: CGFloat = 16

    /// How far the drift runs past the slide's own length. Covers the 0.7s sequenced
    /// swap (see `imageTransition`) plus a cushion for image-load latency, so the
    /// outgoing photo is still in motion while it fades away (continuous all-over
    /// movement instead of move–stop–fade–stop–move). Constant rate for the same
    /// reason: an ease curve would decelerate to a visible standstill before the swap.
    private static let swapOverlapSeconds: Double = 1.0

    func body(content: Content) -> some View {
        // The schedule pauses (instead of the TimelineView being structurally removed)
        // when inactive, so toggling pause/Ken Burns never changes the view's identity —
        // an identity change here would re-trigger the photo's insertion transition.
        TimelineView(.animation(minimumInterval: nil, paused: !isActive)) { context in
            let progress = isActive ? progress(at: context.date) : 1
            content
                .scaleEffect(startScale + (endScale - startScale) * progress)
                .offset(x: pan * (1 - progress), y: -pan * (1 - progress))
        }
        .onAppear { startDate = Date() }
        .onChange(of: isActive) { _, active in
            if active { startDate = Date() }
        }
    }

    /// Linear 0→1 over the slide length + overlap; clamps at 1 (fully settled), and
    /// `progress == 1` is also the neutral state used while inactive (scale 1, no pan).
    private func progress(at date: Date) -> CGFloat {
        guard let startDate else { return 0 }
        let span = max(durationSeconds, 0.1) + Self.swapOverlapSeconds
        return CGFloat(min(max(date.timeIntervalSince(startDate) / span, 0), 1))
    }
}

extension View {
    func kenBurns(isActive: Bool, durationSeconds: Double) -> some View {
        modifier(KenBurnsModifier(isActive: isActive, durationSeconds: durationSeconds))
    }
}
