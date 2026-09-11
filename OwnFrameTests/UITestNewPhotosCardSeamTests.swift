//
//  UITestNewPhotosCardSeamTests.swift
//  OwnFrameTests
//
//  310/9010 slot 5 capture seam: the doc comment on `UITestNewPhotosCardSeam` claims only
//  "the one refreshNow() it drives" sees the expanded asset list. That only holds if the arm
//  is consumed on read — a plain `isArmed` boolean would stay true for every subsequent
//  fetch in the same process (e.g. a second `.task` run from a source-switch), silently
//  breaking the seam's one-shot guarantee.
//

import Testing
@testable import OwnFrame

struct UITestNewPhotosCardSeamTests {

    @Test func armIsConsumedByTheFirstCheckOnly() {
        UITestNewPhotosCardSeam.arm()

        #expect(UITestNewPhotosCardSeam.consumeIfArmed() == true)
        #expect(UITestNewPhotosCardSeam.consumeIfArmed() == false)
    }

    @Test func uncheckedSeamStartsUnarmed() {
        #expect(UITestNewPhotosCardSeam.consumeIfArmed() == false)
    }
}
