//
//  UITestWarmReturnLinkSeamTests.swift
//  OwnFrameTests
//
//  210 T061 (#65, SC-210-02): the warm-return seam. `--uitest-pending-link-after-background <url>`
//  must hand the link to the pending store only once the app has gone to the background, as the
//  Share Extension would while the person is in Safari, so the UI test proves the link is picked
//  up on the return to the foreground rather than on launch.
//

import Foundation
import OnboardingKit
import Testing
import UIKit
@testable import OwnFrame

@MainActor
struct UITestWarmReturnLinkSeamTests {

    @Test func linkArrivesOnlyAfterTheAppEntersTheBackground() {
        let link = URL(string: "https://demo.example.com/s/holiday")!
        let store = InMemoryPendingSharedLinkStore()
        let center = NotificationCenter()
        let seam = UITestWarmReturnLinkSeam(link: link, store: store, center: center)

        #expect(store.takePendingURL() == nil, "nothing may be pending at launch")

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        #expect(store.takePendingURL() == link)
        #expect(store.takePendingURL() == nil, "the link is handed over once")

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        #expect(store.takePendingURL() == nil, "a second trip to the background delivers nothing")
        withExtendedLifetime(seam) {}
    }

    @Test func flagParsesTheFollowingArgument() {
        let args = ["--uitest", "--uitest-pending-link-after-background", "https://demo.example.com/s/holiday"]
        #expect(UITestWarmReturnLinkSeam.link(from: args) == URL(string: "https://demo.example.com/s/holiday"))
        #expect(UITestWarmReturnLinkSeam.link(from: ["--uitest"]) == nil)
    }
}
