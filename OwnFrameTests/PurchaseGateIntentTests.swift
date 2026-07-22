//
//  PurchaseGateIntentTests.swift
//  OwnFrameTests
//
//  1100 (T019) RED: the `.automation` guard on every App Intent
//  (data-model.md §Gated feature mapping — "each intent `perform()` guard").
//
//  Two rules are pinned here.
//
//  1. Every remote-control intent's `perform()` throws without `.automation`, with
//     the localized `unlock.required.automation` copy. The guard sits BEFORE the
//     registry resolution and before any verb reaches the control surface, so a
//     locked intent is inert — it must never move the frame and then complain.
//
//  2. The intents stay LISTED in Shortcuts. Hiding them would strand every shortcut
//     an owner already built and make the capability undiscoverable; the intended
//     behaviour is a discoverable intent that fails with a readable unlock message.
//     `GetFrameStateIntent` is included: reading the frame's state remotely is the
//     same Automation capability as driving it.
//

import AppIntents
import Foundation
import Testing
import AppIntentsKit
import AppIntentsTestSupport
import HAControlKit
import PurchaseKit
@testable import OwnFrame

@MainActor
struct PurchaseGateIntentTests {

    // MARK: - The locked copy

    /// The exact user-facing string behind `unlock.required.automation`.
    static let automationLockedCopy = "Remote control requires the Automation unlock."

    @Test func automationLockedErrorCarriesTheContractCopy() {
        #expect(
            String(localized: FrameIntentError.automationLocked.localizedStringResource)
                == Self.automationLockedCopy
        )
    }

    // MARK: - Every control intent is guarded

    @Test func pauseIntentThrowsWithoutAutomation() async throws {
        let fixture = try IntentGateFixture(entitlements: EntitlementSet.none)
        defer { fixture.restore() }

        await #expect(throws: FrameIntentError.automationLocked) {
            _ = try await PauseSlideshowIntent().perform()
        }
        #expect(fixture.surface.calls.isEmpty)
    }

    @Test func resumeIntentThrowsWithoutAutomation() async throws {
        let fixture = try IntentGateFixture(entitlements: EntitlementSet.none)
        defer { fixture.restore() }

        await #expect(throws: FrameIntentError.automationLocked) {
            _ = try await ResumeSlideshowIntent().perform()
        }
        #expect(fixture.surface.calls.isEmpty)
    }

    @Test func nextPhotoIntentThrowsWithoutAutomation() async throws {
        let fixture = try IntentGateFixture(entitlements: EntitlementSet.none)
        defer { fixture.restore() }

        await #expect(throws: FrameIntentError.automationLocked) {
            _ = try await NextPhotoIntent().perform()
        }
        #expect(fixture.surface.calls.isEmpty)
    }

    @Test func previousPhotoIntentThrowsWithoutAutomation() async throws {
        let fixture = try IntentGateFixture(entitlements: EntitlementSet.none)
        defer { fixture.restore() }

        await #expect(throws: FrameIntentError.automationLocked) {
            _ = try await PreviousPhotoIntent().perform()
        }
        #expect(fixture.surface.calls.isEmpty)
    }

    @Test func setBrightnessIntentThrowsWithoutAutomation() async throws {
        let fixture = try IntentGateFixture(entitlements: EntitlementSet.none)
        defer { fixture.restore() }

        let intent = SetBrightnessIntent()
        intent.brightness = 40
        await #expect(throws: FrameIntentError.automationLocked) {
            _ = try await intent.perform()
        }
        #expect(fixture.surface.calls.isEmpty)
    }

    @Test func selectSourceIntentThrowsWithoutAutomation() async throws {
        let fixture = try IntentGateFixture(
            entitlements: EntitlementSet.none,
            sources: [SourceOption(id: "s1", label: "Iceland 2021")]
        )
        defer { fixture.restore() }

        let intent = SelectSourceIntent()
        intent.source = SourceEntity(id: "s1", label: "Iceland 2021")
        await #expect(throws: FrameIntentError.automationLocked) {
            _ = try await intent.perform()
        }
        #expect(fixture.surface.calls.isEmpty)
    }

    @Test func getFrameStateIntentThrowsWithoutAutomation() async throws {
        let fixture = try IntentGateFixture(entitlements: EntitlementSet.none)
        defer { fixture.restore() }

        await #expect(throws: FrameIntentError.automationLocked) {
            _ = try await GetFrameStateIntent().perform()
        }
    }

    /// The guard must precede the registry resolution: an unentitled *and*
    /// unconfigured frame reports the unlock, not the setup copy. Otherwise the
    /// owner is sent to fix a frame that was never the problem.
    @Test func automationGuardPrecedesTheNotConfiguredCheck() async throws {
        let fixture = try IntentGateFixture(entitlements: EntitlementSet.none, configured: false)
        defer { fixture.restore() }

        await #expect(throws: FrameIntentError.automationLocked) {
            _ = try await PauseSlideshowIntent().perform()
        }
    }

    /// Pro is the ambience tier — it buys no remote control.
    @Test func proAloneDoesNotSatisfyTheIntentGuard() async throws {
        let fixture = try IntentGateFixture(entitlements: [.pro])
        defer { fixture.restore() }

        await #expect(throws: FrameIntentError.automationLocked) {
            _ = try await PauseSlideshowIntent().perform()
        }
        #expect(fixture.surface.calls.isEmpty)
    }

    // MARK: - Entitled behaviour is exactly the pre-gate behaviour

    @Test func automationOwnerDrivesEveryIntentUnchanged() async throws {
        let fixture = try IntentGateFixture(entitlements: [.automation])
        defer { fixture.restore() }

        _ = try await PauseSlideshowIntent().perform()
        _ = try await ResumeSlideshowIntent().perform()
        _ = try await NextPhotoIntent().perform()
        _ = try await PreviousPhotoIntent().perform()

        #expect(fixture.surface.calls == [.pause, .resume, .showNext, .showPrevious])
    }

    @Test func everythingBundleOwnerDrivesTheIntents() async throws {
        let fixture = try IntentGateFixture(entitlements: EntitlementSet.all)
        defer { fixture.restore() }

        _ = try await PauseSlideshowIntent().perform()

        #expect(fixture.surface.calls == [.pause])
    }

    // MARK: - Listed, never hidden

    /// A gated intent stays discoverable in Shortcuts: existing shortcuts keep
    /// resolving, and the capability stays findable. Locking changes the *outcome*
    /// of running one, never its presence in the picker.
    @Test func everyIntentStaysListedInShortcutsWhileLocked() throws {
        let fixture = try IntentGateFixture(entitlements: EntitlementSet.none)
        defer { fixture.restore() }

        #expect(PauseSlideshowIntent.isDiscoverable)
        #expect(ResumeSlideshowIntent.isDiscoverable)
        #expect(NextPhotoIntent.isDiscoverable)
        #expect(PreviousPhotoIntent.isDiscoverable)
        #expect(SetBrightnessIntent.isDiscoverable)
        #expect(SelectSourceIntent.isDiscoverable)
        #expect(GetFrameStateIntent.isDiscoverable)
    }

    /// The unattended-automation conformance from 800 (FR-800-05) is unchanged by
    /// the gate — the gate alters neither launch behaviour nor titles.
    @Test func gatingDoesNotDisturbTheUnattendedConformance() throws {
        let fixture = try IntentGateFixture(entitlements: EntitlementSet.none)
        defer { fixture.restore() }

        #expect(PauseSlideshowIntent.openAppWhenRun)
        #expect(ResumeSlideshowIntent.openAppWhenRun)
        #expect(NextPhotoIntent.openAppWhenRun)
        #expect(PreviousPhotoIntent.openAppWhenRun)
        #expect(SetBrightnessIntent.openAppWhenRun)
        #expect(GetFrameStateIntent.openAppWhenRun == false)
    }
}

// MARK: - Fixture

/// Snapshot-and-restore around the app's process registry *and* the new entitlement
/// seam on `FrameIntentContext`, so a locked run never leaks into the next test.
@MainActor
private struct IntentGateFixture {
    let registry: FrameControlRegistry
    let surface: RecordingControlSurface
    private let previousConfigured: Bool
    private let previousSourceOptions: @MainActor () -> [SourceOption]
    private let previousEntitlements: @MainActor () -> EntitlementSet

    init(
        entitlements: EntitlementSet,
        configured: Bool = true,
        sources: [SourceOption]? = nil
    ) throws {
        registry = try #require(FrameIntentContext.registry)
        previousConfigured = registry.isConfigured
        previousSourceOptions = registry.sourceOptions
        previousEntitlements = FrameIntentContext.entitlements

        surface = RecordingControlSurface()
        FrameIntentContext.entitlements = { entitlements }
        registry.isConfigured = configured
        if let sources {
            registry.sourceOptions = { sources }
        }
        if configured {
            registry.register(surface)
        } else {
            registry.unregister()
        }
    }

    func restore() {
        registry.unregister()
        registry.isConfigured = previousConfigured
        registry.sourceOptions = previousSourceOptions
        FrameIntentContext.entitlements = previousEntitlements
    }
}
