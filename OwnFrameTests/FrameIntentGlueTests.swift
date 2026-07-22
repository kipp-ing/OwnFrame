//
//  FrameIntentGlueTests.swift
//  OwnFrameTests
//
//  800 (T013/T017): the AppIntent shells are one-call thin — each forwards to its
//  FrameCommandService verb against the app's REAL process registry (the instance
//  the host app registered in AppDependencyManager at init; analyze U2: tests
//  register a fake SURFACE into that registry, they never re-register the
//  container). Also pins the unattended-automation conformance: openAppWhenRun on
//  every control intent and error copy matching the contract exactly.
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
struct FrameIntentGlueTests {

    // MARK: - Forwarding (one call, right verb)

    @Test func pauseIntentForwardsToThePauseVerb() async throws {
        let fixture = try Fixture()
        defer { fixture.restore() }

        _ = try await PauseSlideshowIntent().perform()
        #expect(fixture.surface.calls == [.pause])
    }

    @Test func resumeIntentForwardsToTheResumeVerb() async throws {
        let fixture = try Fixture()
        defer { fixture.restore() }

        _ = try await ResumeSlideshowIntent().perform()
        #expect(fixture.surface.calls == [.resume])
    }

    @Test func nextPhotoIntentForwardsToShowNext() async throws {
        let fixture = try Fixture()
        defer { fixture.restore() }

        _ = try await NextPhotoIntent().perform()
        #expect(fixture.surface.calls == [.showNext])
    }

    @Test func previousPhotoIntentForwardsToShowPrevious() async throws {
        let fixture = try Fixture()
        defer { fixture.restore() }

        _ = try await PreviousPhotoIntent().perform()
        #expect(fixture.surface.calls == [.showPrevious])
    }

    @Test func setBrightnessIntentMapsPercentThroughTheService() async throws {
        let fixture = try Fixture()
        defer { fixture.restore() }

        let intent = SetBrightnessIntent()
        intent.brightness = 40
        _ = try await intent.perform()
        #expect(fixture.surface.calls == [.setBrightness(0.4)])
    }

    // MARK: - Error mapping (contract copy, state untouched)

    @Test func outOfRangeBrightnessThrowsTheContractCopyAndRecordsNothing() async throws {
        let fixture = try Fixture()
        defer { fixture.restore() }

        let intent = SetBrightnessIntent()
        intent.brightness = 101
        await #expect(throws: FrameIntentError.brightnessOutOfRange) {
            _ = try await intent.perform()
        }
        #expect(fixture.surface.calls.isEmpty)
        #expect(
            String(localized: FrameIntentError.brightnessOutOfRange.localizedStringResource)
                == "Brightness must be between 0 and 100 percent."
        )
    }

    @Test func unconfiguredFrameThrowsTheSetupCopy() async throws {
        let fixture = try Fixture(configured: false)
        defer { fixture.restore() }

        await #expect(throws: FrameIntentError.notConfigured) {
            _ = try await PauseSlideshowIntent().perform()
        }
        #expect(
            String(localized: FrameIntentError.notConfigured.localizedStringResource)
                == "Set up the frame first — open OwnFrame and add a source."
        )
    }

    @Test func remainingContractCopyMatches() {
        #expect(
            String(localized: FrameIntentError.frameNotOpen.localizedStringResource)
                == "OwnFrame must be open on the frame device for this."
        )
        #expect(
            String(localized: FrameIntentError.sourceMissing.localizedStringResource)
                == "This source no longer exists in the frame's library."
        )
    }

    // MARK: - Unattended conformance (T017, FR-800-05)

    @Test func everyControlIntentOpensTheAppWhenRun() {
        #expect(PauseSlideshowIntent.openAppWhenRun)
        #expect(ResumeSlideshowIntent.openAppWhenRun)
        #expect(NextPhotoIntent.openAppWhenRun)
        #expect(PreviousPhotoIntent.openAppWhenRun)
        #expect(SetBrightnessIntent.openAppWhenRun)
    }

    // MARK: - US3: source select + state read (T023)

    @Test func selectSourceIntentAppliesViaTheLibraryResolvedLabel() async throws {
        let fixture = try Fixture(sources: [SourceOption(id: "s1", label: "Iceland 2021")])
        defer { fixture.restore() }

        let intent = SelectSourceIntent()
        intent.source = SourceEntity(id: "s1", label: "Stale Old Name")
        _ = try await intent.perform()
        // Applied with the label resolved from the CURRENT library, the exact HA path.
        #expect(fixture.surface.calls == [.selectAlbum("Iceland 2021")])
    }

    @Test func selectSourceIntentSurfacesTheDeletedSourceCopy() async throws {
        let fixture = try Fixture(sources: [SourceOption(id: "s1", label: "Iceland 2021")])
        defer { fixture.restore() }

        let intent = SelectSourceIntent()
        intent.source = SourceEntity(id: "deleted", label: "Vacation")
        await #expect(throws: FrameIntentError.sourceMissing) {
            _ = try await intent.perform()
        }
        #expect(fixture.surface.calls.isEmpty)
    }

    @Test func sourceEntityQueryAnswersFromTheRegistryOptions() async throws {
        let fixture = try Fixture(sources: [
            SourceOption(id: "s1", label: "Iceland 2021"),
            SourceOption(id: "s2", label: "Family"),
        ])
        defer { fixture.restore() }

        let byID = try await SourceEntity.defaultQuery.entities(for: ["s2", "missing"])
        #expect(byID.map(\.id) == ["s2"])
        #expect(byID.map(\.label) == ["Family"])

        let suggested = try await SourceEntity.defaultQuery.suggestedEntities()
        #expect(suggested.map(\.id) == ["s1", "s2"])
        #expect(suggested.map(\.label) == ["Iceland 2021", "Family"])
    }

    @Test func getFrameStateIntentNeverOpensTheAppAndMirrorsTheSnapshot() async throws {
        let taken = Date(timeIntervalSince1970: 1_600_000_000)
        let fixture = try Fixture()
        defer { fixture.restore() }
        fixture.surface.playbackState = .playing
        fixture.surface.brightness = 0.4
        fixture.surface.currentAlbum = "Iceland 2021"
        fixture.surface.currentPhotoReport = PhotoReport(
            assetID: "SECRET-ASSET", imageData: Data([0xFF]),
            takenAt: taken, city: "Berlin", state: "BE", country: "DE",
            albumID: "SECRET-ALBUM", albumName: "Iceland 2021",
            phase: .playing, photoCount: 42
        )

        #expect(GetFrameStateIntent.openAppWhenRun == false)

        let result = try await GetFrameStateIntent().perform()
        let state = try #require(result.value)
        #expect(state.isPlaying == true)
        #expect(state.brightnessPercent == 40)
        #expect(state.sourceLabel == "Iceland 2021")
        #expect(state.photoDate == taken)
        #expect(state.photoCity == "Berlin")
        #expect(state.photoCountry == "DE")
    }

    // MARK: - Fixture

    /// Snapshot-and-restore around the app's process registry: the host app set
    /// it into `FrameIntentContext` at init; the shells resolve that same
    /// instance, so registering a recording surface here proves the intents
    /// drive whatever single adapter the app registered (FR-800-02).
    @MainActor
    private struct Fixture {
        let registry: FrameControlRegistry
        let surface: RecordingControlSurface
        private let previousConfigured: Bool
        private let previousSourceOptions: @MainActor () -> [SourceOption]
        private let previousEntitlements: @MainActor () -> EntitlementSet

        init(configured: Bool = true, sources: [SourceOption]? = nil) throws {
            registry = try #require(FrameIntentContext.registry)
            previousConfigured = registry.isConfigured
            previousSourceOptions = registry.sourceOptions
            // 1100: App Intents are the Automation tier, so every `perform()` now guards on
            // `.automation`. These tests are about intent *glue*, not the gate, so seed the
            // entitlement and let PurchaseGateIntentTests own the locked behaviour. Without
            // this the suite would run against the ambient app value and fail as locked.
            previousEntitlements = FrameIntentContext.entitlements
            FrameIntentContext.entitlements = { [.automation] }
            surface = RecordingControlSurface()
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
}
