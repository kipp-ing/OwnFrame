import Testing
@testable import PurchaseKit

// T015 — RED tests for `AmbienceGate`, the per-photo latch that gates the two `.pro` ambience
// features (data-model.md §Gated feature mapping: Ken Burns motion, clock overlay).
//
// The type is a pure value — no SwiftUI, no I/O, no clock — so the boundary rule of FR-1100-12
// is testable without a running slideshow. Its whole job is to *delay* an entitlement change
// until the caller re-latches at a natural boundary (photo advance, app foreground), so a photo
// that is already on screen never changes its motion or chrome underneath the viewer.
//
// The stored user settings (`ThemeSettings.kenBurnsEnabled`, `ClockSettings.isEnabled`) are
// passed in per call and never held by the gate — PurchaseKit must never read, write, or mask
// user configuration (FR-1100-14, data-model.md §Invariants).

// MARK: - Construction (the latch's initial value)

@Test func entitledGateLeavesBothSettingsOn() {
    let gate = AmbienceGate(entitled: true)

    #expect(gate.effectiveKenBurns(setting: true))
    #expect(gate.effectiveClock(setting: true))
}

@Test func unentitledGateBitesOnBothFeatures() {
    let gate = AmbienceGate(entitled: false)

    #expect(gate.effectiveKenBurns(setting: true) == false)
    #expect(gate.effectiveClock(setting: true) == false)
}

/// The gate only ever subtracts. Owning `.pro` must never switch on a feature the user has
/// deliberately turned off.
@Test func entitledGateNeverTurnsOnADisabledSetting() {
    let gate = AmbienceGate(entitled: true)

    #expect(gate.effectiveKenBurns(setting: false) == false)
    #expect(gate.effectiveClock(setting: false) == false)
}

// MARK: - FR-1100-12: the in-flight photo is never altered

/// The core boundary rule. A refund or revocation landing while a photo is on screen must not
/// freeze its pan or yank the clock — the effective flags hold until the next `relatch`.
@Test func entitlementLostMidPhotoDoesNotAlterTheInFlightPhoto() {
    let gate = AmbienceGate(entitled: true)

    // Entitlement is now gone, but no boundary has been reached: nothing re-latched.
    #expect(gate.effectiveKenBurns(setting: true))
    #expect(gate.effectiveClock(setting: true))
}

// @covers FR-1100-12
@Test func entitlementLostTakesEffectAtTheNextRelatch() {
    var gate = AmbienceGate(entitled: true)

    gate.relatch(entitled: false)

    #expect(gate.effectiveKenBurns(setting: true) == false)
    #expect(gate.effectiveClock(setting: true) == false)
}

/// Symmetric to the loss case: a purchase completing mid-photo must not make a still photo
/// suddenly start moving halfway through its display.
@Test func entitlementGainedMidPhotoDoesNotStartMotionOnTheInFlightPhoto() {
    let gate = AmbienceGate(entitled: false)

    #expect(gate.effectiveKenBurns(setting: true) == false)
    #expect(gate.effectiveClock(setting: true) == false)
}

@Test func entitlementGainedTakesEffectAtTheNextRelatch() {
    var gate = AmbienceGate(entitled: false)

    gate.relatch(entitled: true)

    #expect(gate.effectiveKenBurns(setting: true))
    #expect(gate.effectiveClock(setting: true))
}

// MARK: - Relatch behaviour

/// Re-latching happens on every photo advance and every foreground, so the overwhelmingly
/// common case is a no-op. It must stay one.
@Test func relatchWithAnUnchangedValueIsIdempotent() {
    var entitled = AmbienceGate(entitled: true)
    entitled.relatch(entitled: true)
    entitled.relatch(entitled: true)

    #expect(entitled == AmbienceGate(entitled: true))
    #expect(entitled.effectiveKenBurns(setting: true))
    #expect(entitled.effectiveClock(setting: true))

    var unentitled = AmbienceGate(entitled: false)
    unentitled.relatch(entitled: false)
    unentitled.relatch(entitled: false)

    #expect(unentitled == AmbienceGate(entitled: false))
    #expect(unentitled.effectiveKenBurns(setting: true) == false)
    #expect(unentitled.effectiveClock(setting: true) == false)
}

@Test func repeatedRelatchesTrackTheLatestValue() {
    var gate = AmbienceGate(entitled: false)

    gate.relatch(entitled: true)
    #expect(gate.effectiveKenBurns(setting: true))

    gate.relatch(entitled: false)
    #expect(gate.effectiveKenBurns(setting: true) == false)

    gate.relatch(entitled: true)
    #expect(gate.effectiveKenBurns(setting: true))
    #expect(gate.effectiveClock(setting: true))
}

/// The latch and the stored setting are independent inputs: re-latching must never be able to
/// override what the user chose.
@Test func settingIsHonouredIndependentlyOfTheLatchAcrossARelatchCycle() {
    var gate = AmbienceGate(entitled: false)

    gate.relatch(entitled: true)
    #expect(gate.effectiveKenBurns(setting: false) == false)
    #expect(gate.effectiveClock(setting: false) == false)
    #expect(gate.effectiveKenBurns(setting: true))
    #expect(gate.effectiveClock(setting: true))

    gate.relatch(entitled: false)
    #expect(gate.effectiveKenBurns(setting: false) == false)
    #expect(gate.effectiveClock(setting: false) == false)
}

// MARK: - Both features sit in the same tier

/// Ken Burns and the clock are both `.pro`, so the two accessors are the same truth table.
/// A future tier split would have to break this test deliberately.
@Test func kenBurnsAndClockAgreeForEveryInputCombination() {
    for latched in [true, false] {
        let gate = AmbienceGate(entitled: latched)
        for setting in [true, false] {
            #expect(gate.effectiveKenBurns(setting: setting) == gate.effectiveClock(setting: setting))
        }
    }
}
