//
//  FrameIntentGlueTests.swift
//  Immich SlideshowTests
//
//  800 (T013/T017): the AppIntent shells are one-call thin — each forwards to its
//  FrameCommandService verb against the app's REAL process registry (the instance
//  the host app registered in AppDependencyManager at init; analyze U2: tests
//  register a fake SURFACE into that registry, they never re-register the
//  container). Also pins the unattended-automation conformance: openAppWhenRun on
//  every control intent and error copy matching the contract exactly.
//

import Foundation
import Testing
import AppIntentsKit
import AppIntentsTestSupport
import HAControlKit
@testable import Immich_Slideshow

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
                == "Set up the frame first — open Photo Frame and add a source."
        )
    }

    @Test func remainingContractCopyMatches() {
        #expect(
            String(localized: FrameIntentError.frameNotOpen.localizedStringResource)
                == "Photo Frame must be open on the frame device for this."
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

        init(configured: Bool = true) throws {
            registry = try #require(FrameIntentContext.registry)
            previousConfigured = registry.isConfigured
            surface = RecordingControlSurface()
            registry.isConfigured = configured
            if configured {
                registry.register(surface)
            } else {
                registry.unregister()
            }
        }

        func restore() {
            registry.unregister()
            registry.isConfigured = previousConfigured
        }
    }
}
