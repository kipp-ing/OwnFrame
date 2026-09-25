//
//  KeyboardFocus.swift
//  OwnFrameUITests
//
//  iOS 26+ (issue #75): while a text field keeps keyboard focus, a SYNTHESIZED tap on a button
//  in the same form or sheet is swallowed — the sheet stays open, nothing submits. A finger
//  works on the first tap (Jan, iPad jk 26.6.1, 2026-09-25), so this is a harness artifact:
//  tests release the focus before tapping the button, exactly where a person's keyboard would
//  already be irrelevant.
//
//  How: Return into the focused field. None of the app's link/password/name fields has an
//  `onSubmit`, so Return only resigns focus — verify that before using this on a new field.
//  Not the keyboard's hide key (on iOS 27 simulators it sits off-screen) and not a tap on a
//  "neutral" spot (on iPad, a tap outside a form sheet dismisses the sheet).
//

import XCTest

extension XCUIApplication {
    @MainActor
    func releaseKeyboardFocus() {
        guard keyboards.firstMatch.exists else { return }
        typeText("\n")
    }
}
