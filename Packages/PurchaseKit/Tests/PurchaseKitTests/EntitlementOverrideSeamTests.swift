import Foundation
import Testing
@testable import PurchaseKit

// Device test rig (1100 harness) — the predicate that lets the *production* launch path honour
// `--uitest-entitlements=` without also entering the hermetic `--uitest` world.
//
// Why this seam has to exist at all: the hermetic branch wires `makeCoordinator: { _ in nil }`,
// i.e. under `--uitest` there is no MQTT broker in the process. So the pre-existing entitlement
// seam could never be used to exercise the HA gating contract (FR-1100-03a) against a real
// broker on real hardware — the one thing a physical frame is uniquely able to prove. Seeding
// entitlements and stubbing the world were welded together; this predicate separates them.
//
// The distinction under test is precisely the one an `EntitlementSet`-valued API cannot express:
// an *absent* flag and `--uitest-entitlements=none` both mean "free tier", but only the second is
// an override. Reading `entitlements == .none` therefore cannot answer "did the launch ask?", and
// a production launch must fall through to StoreKit rather than to a stub that grants nothing.
@Suite("Entitlement override seam")
struct EntitlementOverrideSeamTests {

    @Test("An absent flag is not an override — production launches reach StoreKit")
    func absentFlagIsNotAnOverride() {
        #expect(PurchaseUITestSeams.hasEntitlementOverride(arguments: []) == false)
        #expect(
            PurchaseUITestSeams.hasEntitlementOverride(
                arguments: ["/path/to/app", "--uitest", "--uitest-slideshow"]
            ) == false
        )
    }

    // The case that motivates a dedicated predicate: same resulting EntitlementSet as an absent
    // flag, opposite meaning. A rig launched with `=none` is deliberately asserting the free tier
    // and must get the hermetic store, not StoreKit's real answer.
    @Test("An explicit =none IS an override, though it grants nothing")
    func explicitNoneIsAnOverride() {
        #expect(
            PurchaseUITestSeams.hasEntitlementOverride(
                arguments: ["/path/to/app", "--uitest-entitlements=none"]
            ) == true
        )
        #expect(PurchaseUITestSeams.entitlements(arguments: ["--uitest-entitlements=none"]) == .none)
    }

    @Test("A granting flag is an override regardless of position or neighbours")
    func grantingFlagIsAnOverride() {
        #expect(
            PurchaseUITestSeams.hasEntitlementOverride(
                arguments: ["/path/to/app", "--uitest-entitlements=all", "--uitest-store=stub"]
            ) == true
        )
        #expect(
            PurchaseUITestSeams.entitlements(arguments: ["--uitest-entitlements=all"])
                == EntitlementSet.all
        )
    }

    // A bare `--uitest-entitlements` with no `=` is a typo, not a request. Treating it as an
    // override would silently swap a real frame's StoreKit store for a stub granting nothing —
    // the failure mode being avoided is a *false* gate, so this fails closed toward production.
    @Test("A malformed flag without '=' is not an override")
    func malformedFlagIsNotAnOverride() {
        #expect(
            PurchaseUITestSeams.hasEntitlementOverride(
                arguments: ["/path/to/app", "--uitest-entitlements"]
            ) == false
        )
    }
}
