//
//  NewPhotosCardCaptureTimingTests.swift
//  OwnFrameTests
//
//  9010 slot 5 capture seam. The arrival card fades itself out after `displayDuration`, so
//  forcing ONE arrival was only ever enough because the capture happened immediately after
//  `start()`. It stopped being enough the moment the rig had to walk to a chosen asset first
//  (slot 5 was landing on the retriever — the `frameContent` album's thumbnail — which slot 2
//  already carries). `SlideshowView` now re-publishes the forced arrival on an interval, and
//  the whole trick rests on that interval being strictly shorter than the card's own fade.
//
//  Nothing else in the app enforces that relationship: the two constants sit in different
//  concerns (a capture seam and an ambience timing), and the failure they would cause is a
//  screenshot that silently catches the gap between re-publishes — a blank tile nobody notices
//  until it is on the store page.
//

import Testing
@testable import OwnFrame

// @MainActor because both constants live on a SwiftUI View and inherit its isolation; reading
// them from a nonisolated test is a Swift 6 concurrency warning today and an error tomorrow.
@MainActor
struct NewPhotosCardCaptureTimingTests {

    @Test func republishOutpacesTheCardsOwnFade() {
        #expect(NewPhotosOverlayView.forcedArrivalRepublishInterval
                < NewPhotosOverlayView.displayDuration)
    }

    @Test func republishLeavesRoomForTheFadeAnimationToSettle() {
        // The card cross-fades over 0.3s at each end. An interval that only just undercuts the
        // display duration would re-publish mid-fade, which reads as a flicker on a capture.
        #expect(NewPhotosOverlayView.forcedArrivalRepublishInterval * 2
                < NewPhotosOverlayView.displayDuration)
    }

    @Test func republishIsPositive() {
        #expect(NewPhotosOverlayView.forcedArrivalRepublishInterval > .zero)
    }
}
