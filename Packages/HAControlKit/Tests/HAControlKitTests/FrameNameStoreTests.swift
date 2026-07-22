import Foundation
import Testing
@testable import HAControlKit

// 700 / FR-700-22 — the human-readable frame name.
//
// The counterpart to FrameIdentityResolver: this value is free-form, non-unique, changeable, and
// drives ONLY the Home Assistant display name. It is deliberately not part of any key, which is
// what lets a user rename a frame without orphaning a single entity — Home Assistant anchors on
// `unique_id` and treats the name as cosmetic.
//
// It exists because identity is opaque (FR-700-20): without a name, two frames on one broker are
// both "Photo Frame" and indistinguishable.
@Suite("Frame name store")
@MainActor
struct FrameNameStoreTests {

    private func makeDefaults() -> UserDefaults {
        // Unique suite per test so one test's name can never leak into the next.
        UserDefaults(suiteName: "frameName.test.\(UUID().uuidString)")!
    }

    @Test("A fresh install falls back to the supplied default")
    func defaultsWhenUnset() {
        let store = UserDefaultsFrameNameStore(defaults: makeDefaults(), defaultName: "Photo Frame")
        #expect(store.name == "Photo Frame")
    }

    @Test("The platform default is respected, so the TV frame is not named like the iPad")
    func platformDefaultIsHonoured() {
        let store = UserDefaultsFrameNameStore(
            defaults: makeDefaults(), defaultName: "Photo Frame (Apple TV)"
        )
        #expect(store.name == "Photo Frame (Apple TV)")
    }

    // @covers FR-700-22
    @Test("A set name persists and is read back by a new store over the same defaults")
    func persistsAcrossStores() {
        let defaults = makeDefaults()
        let store = UserDefaultsFrameNameStore(defaults: defaults, defaultName: "Photo Frame")

        // Non-ASCII on purpose: this is a display name, not a key, so it must round-trip intact
        // rather than being sanitised the way an identity would have to be.
        store.name = "Café"

        let reopened = UserDefaultsFrameNameStore(defaults: defaults, defaultName: "Photo Frame")
        #expect(reopened.name == "Café")
    }

    // A user clearing the field should get the sensible default back, not an unnamed device in
    // Home Assistant. Blank-but-present is the failure mode a plain `string(forKey:)` would miss.
    @Test("A blank name falls back to the default rather than naming the frame nothing",
          arguments: ["", "   ", "\n"])
    func blankFallsBackToDefault(blank: String) {
        let store = UserDefaultsFrameNameStore(defaults: makeDefaults(), defaultName: "Photo Frame")

        store.name = blank

        #expect(store.name == "Photo Frame")
    }

    @Test("Surrounding whitespace is trimmed so the HA display name is clean")
    func trimsWhitespace() {
        let store = UserDefaultsFrameNameStore(defaults: makeDefaults(), defaultName: "Photo Frame")

        store.name = "  Living Room  "

        #expect(store.name == "Living Room")
    }
}
