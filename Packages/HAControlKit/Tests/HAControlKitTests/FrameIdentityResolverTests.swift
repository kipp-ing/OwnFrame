import Foundation
import Testing
@testable import HAControlKit

// 700 US3 / FR-700-16…21 — how a frame decides who it is in Home Assistant.
//
// The shipped implementation used `UIDevice.current.identifierForVendor` directly, which iOS
// regenerates once the last app from a vendor is deleted. A reinstalled frame therefore
// re-registered as a NEW Home Assistant device and left its previous entities permanently
// `unavailable` — verified live on hardware 2026-07-21, where 19 orphaned entities had to be
// retracted by hand against the broker.
//
// The nastier half was the fallback: `?? "immich-slideshow-device"` is a *shared constant*, so
// two frames that both hit it (identifierForVendor is nil before the first unlock after a
// reboot — exactly a frame recovering from a power cut) collide on one topic namespace and one
// set of `unique_id`s, silently. Several tests below exist only to keep a constant from ever
// creeping back into that position.
//
// The resolver is pure and storage-injected so all of this is host-testable; the Keychain-backed
// storage is verified separately on device (SC-700-11).

/// In-memory storage standing in for the durable one. `saves` is recorded because "generated
/// once" is a claim about *writes*, not just about the value returned.
private final class FakeStorage: FrameIdentityStorage, @unchecked Sendable {
    private(set) var saves: [String] = []
    private var stored: String?

    init(stored: String? = nil) { self.stored = stored }

    func loadIdentity() -> String? { stored }
    func saveIdentity(_ identity: String) {
        stored = identity
        saves.append(identity)
    }
}

@Suite("Frame identity resolver")
struct FrameIdentityResolverTests {

    // FR-700-16: the whole point. Reinstall wipes the legacy platform identifier but not the
    // durable store, so a stored value must win outright — and must not be rewritten.
    @Test("A stored identity is returned unchanged and never regenerated")
    func storedIdentityWins() {
        let storage = FakeStorage(stored: "frame-abc")

        let id = FrameIdentityResolver.resolve(
            storage: storage,
            legacyIdentifier: "a-completely-different-idfv",
            makeNew: { "should-not-be-called" }
        )

        #expect(id == "frame-abc")
        #expect(storage.saves.isEmpty, "a stored identity must not be rewritten on every launch")
    }

    @Test("Repeated resolves return the same identity and generate only once")
    func stableAcrossRepeatedResolves() {
        let storage = FakeStorage()
        var counter = 0
        let make = { counter += 1; return "generated-\(counter)" }

        let first = FrameIdentityResolver.resolve(storage: storage, legacyIdentifier: nil, makeNew: make)
        let second = FrameIdentityResolver.resolve(storage: storage, legacyIdentifier: nil, makeNew: make)
        let third = FrameIdentityResolver.resolve(storage: storage, legacyIdentifier: nil, makeNew: make)

        #expect(first == second && second == third)
        #expect(counter == 1, "identity must be generated exactly once, then read")
        #expect(storage.saves == [first], "exactly one durable write")
    }

    // FR-700-21: the migration. An app *update* does not change identifierForVendor, so adopting
    // it on first run means every already-registered frame keeps its entities — the fix must not
    // itself cause the orphaning it exists to prevent.
    @Test("With nothing stored, an existing legacy identifier is adopted rather than replaced")
    func adoptsLegacyIdentifierOnFirstRun() {
        let storage = FakeStorage()

        let id = FrameIdentityResolver.resolve(
            storage: storage,
            legacyIdentifier: "7A6F1230-0E32-4967-855A-9942F175EE08",
            makeNew: { "brand-new" }
        )

        #expect(id == "7A6F1230-0E32-4967-855A-9942F175EE08")
        #expect(storage.saves == [id], "the adopted identity must be persisted, not re-derived")
    }

    // FR-700-18: no shared-constant fallback, ever.
    @Test("With nothing stored and no legacy identifier, a fresh identity is generated")
    func generatesWhenNothingToAdopt() {
        let storage = FakeStorage()

        let id = FrameIdentityResolver.resolve(
            storage: storage,
            legacyIdentifier: nil,
            makeNew: { "fresh-uuid" }
        )

        #expect(id == "fresh-uuid")
        #expect(storage.saves == ["fresh-uuid"])
    }

    // The collision case that motivated FR-700-18. Two frames, both with no stored identity and
    // both unable to read the platform identifier, must NOT converge on one value. With the real
    // `UUID()` default this is what stops them sharing a topic namespace.
    @Test("Two frames with no stored identity and no legacy value never collide")
    func distinctFramesNeverCollide() {
        let a = FrameIdentityResolver.resolve(storage: FakeStorage(), legacyIdentifier: nil)
        let b = FrameIdentityResolver.resolve(storage: FakeStorage(), legacyIdentifier: nil)

        #expect(a != b, "the default generator must be unique per frame, not a constant")
        #expect(!a.isEmpty && !b.isEmpty)
    }

    // Defensive: an empty or whitespace legacy value is absence, not an identity. Adopting "" and
    // persisting it would durably brick the frame's identity — the one failure the store cannot
    // recover from on its own.
    @Test("A blank legacy identifier counts as absent, not as an identity to adopt", arguments: ["", "   "])
    func blankLegacyIsTreatedAsAbsent(blank: String) {
        let storage = FakeStorage()

        let id = FrameIdentityResolver.resolve(
            storage: storage,
            legacyIdentifier: blank,
            makeNew: { "fresh" }
        )

        #expect(id == "fresh")
        #expect(storage.saves == ["fresh"])
    }

    // FR-1000-08: the iPad and Apple TV frames must stay distinct devices on one broker.
    @Test("The platform suffix distinguishes frames sharing a legacy identifier")
    func platformSuffixKeepsPlatformsDistinct() {
        let ipad = FrameIdentityResolver.resolve(
            storage: FakeStorage(), legacyIdentifier: "shared-idfv"
        )
        let tv = FrameIdentityResolver.resolve(
            storage: FakeStorage(), legacyIdentifier: "shared-idfv", platformSuffix: "-appletv"
        )

        #expect(ipad == "shared-idfv")
        #expect(tv == "shared-idfv-appletv")
        #expect(ipad != tv)
    }

    // The suffix is part of the stored value, so re-reading must not append it twice — that
    // would change identity on the second launch, which is the original bug wearing a hat.
    @Test("A stored identity that already carries the suffix is not suffixed again")
    func suffixIsNotDoubleApplied() {
        let storage = FakeStorage(stored: "abc-appletv")

        let id = FrameIdentityResolver.resolve(
            storage: storage, legacyIdentifier: nil, platformSuffix: "-appletv"
        )

        #expect(id == "abc-appletv")
        #expect(storage.saves.isEmpty)
    }

    // FR-700-17 as an executable guard: whatever the resolver returns for a fresh frame must not
    // be one of the constants that caused this defect. If someone reintroduces a literal default,
    // this fails.
    @Test("A fresh identity is never one of the retired shared constants")
    func neverTheRetiredConstants() {
        let retired = ["immich-slideshow-device", "immich-slideshow", "immich-slideshow-appletv"]

        for suffix in ["", "-appletv"] {
            let id = FrameIdentityResolver.resolve(
                storage: FakeStorage(), legacyIdentifier: nil, platformSuffix: suffix
            )
            #expect(!retired.contains(id))
        }
    }
}
