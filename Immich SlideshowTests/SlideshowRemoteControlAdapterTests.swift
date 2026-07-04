//
//  SlideshowRemoteControlAdapterTests.swift
//  Immich SlideshowTests
//
//  US1 (710, T009): SettingsControlling on SlideshowRemoteControlAdapter — all 9
//  fields map both directions through a REAL UserDefaultsThemeStore; a remote
//  apply() is suppressed and does NOT fire onSettingsChange; a genuinely local
//  store mutation fires it exactly once, including after a suppressed apply
//  (observation re-arm).
//

import Foundation
import Testing
import HAControlKit
import ImmichClient
import PowerKit
import SlideshowKit
import ThemeKit
@testable import Immich_Slideshow

@MainActor
struct SlideshowRemoteControlAdapterTests {

    @Test func themeSettingsSnapshotMapsAllNineFieldsFromStore() throws {
        let fixture = try makeAdapter(suite: "adapter.mapsFromStore")
        defer { fixture.cleanUp() }

        fixture.store.settings = ThemeSettings(
            order: .sequential,
            duration: .seconds(42),
            transition: .slide,
            kenBurns: true,
            fit: .fill,
            quality: .original,
            clock: ClockSettings(isOn: true, corner: .topLeading, showDate: true)
        )

        let snapshot = fixture.adapter.themeSettings
        #expect(snapshot.order == .sequential)
        #expect(snapshot.durationSeconds == 42)
        #expect(snapshot.transition == .slide)
        #expect(snapshot.kenBurns == true)
        #expect(snapshot.fit == .fill)
        #expect(snapshot.quality == .original)
        #expect(snapshot.clockOn == true)
        #expect(snapshot.clockCorner == .topLeading)
        #expect(snapshot.clockDate == true)
    }

    @Test func applyMapsAllNineFieldsIntoStore() throws {
        let fixture = try makeAdapter(suite: "adapter.applyMaps")
        defer { fixture.cleanUp() }

        fixture.adapter.apply(ThemeSettingsSnapshot(
            order: .sequential,
            durationSeconds: 42,
            transition: .dissolve,
            kenBurns: true,
            fit: .fill,
            quality: .original,
            clockOn: true,
            clockCorner: .bottomLeading,
            clockDate: true
        ))

        let settings = fixture.store.settings
        #expect(settings.order == .sequential)
        #expect(settings.duration == .seconds(42))
        #expect(settings.transition == .dissolve)
        #expect(settings.kenBurns == true)
        #expect(settings.fit == .fill)
        #expect(settings.quality == .original)
        #expect(settings.clock.isOn == true)
        #expect(settings.clock.corner == .bottomLeading)
        #expect(settings.clock.showDate == true)
    }

    @Test func applyDoesNotFireOnSettingsChange() async throws {
        let fixture = try makeAdapter(suite: "adapter.applySuppressed")
        defer { fixture.cleanUp() }

        var fired = 0
        fixture.adapter.onSettingsChange = { fired += 1 }

        var snapshot = fixture.adapter.themeSettings
        snapshot.kenBurns = true
        fixture.adapter.apply(snapshot)
        await drainObservation()

        #expect(fired == 0)
    }

    @Test func localStoreMutationFiresOnSettingsChangeOnce() async throws {
        let fixture = try makeAdapter(suite: "adapter.localFires")
        defer { fixture.cleanUp() }

        var fired = 0
        fixture.adapter.onSettingsChange = { fired += 1 }

        fixture.store.settings.kenBurns = true
        await drainObservation()

        #expect(fired == 1)
    }

    @Test func localMutationAfterSuppressedApplyStillFires() async throws {
        let fixture = try makeAdapter(suite: "adapter.rearmAfterApply")
        defer { fixture.cleanUp() }

        var fired = 0
        fixture.adapter.onSettingsChange = { fired += 1 }

        var snapshot = fixture.adapter.themeSettings
        snapshot.quality = .original
        fixture.adapter.apply(snapshot)
        await drainObservation()
        #expect(fired == 0)

        fixture.store.settings.kenBurns = true
        await drainObservation()
        #expect(fired == 1)
    }

    // MARK: - Fixture

    private struct Fixture {
        let adapter: SlideshowRemoteControlAdapter
        let store: UserDefaultsThemeStore
        let defaults: UserDefaults
        let suiteName: String

        func cleanUp() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeAdapter(suite: String) throws -> Fixture {
        let suiteName = "de.kippings.ImmichSlideshow.tests.\(suite)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = UserDefaultsThemeStore(defaults: defaults)
        let slideshow = SlideshowViewModel(
            api: StubAPI(),
            albumID: "album-1",
            ticker: StubTicker(),
            settingsStore: store
        )
        let powerManager = PowerManager(screen: StubScreen())
        let adapter = SlideshowRemoteControlAdapter(
            slideshow: slideshow,
            powerManager: powerManager,
            themeStore: store
        )
        return Fixture(adapter: adapter, store: store, defaults: defaults, suiteName: suiteName)
    }

    /// Observation onChange re-dispatches onto the main actor; give those tasks
    /// a few runloop turns to settle before asserting.
    private func drainObservation() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }
}

// MARK: - Stubs

private struct StubAPI: ImmichAPI {
    func serverVersion() async throws -> String { "test" }
    func albums() async throws -> [Album] { [] }
    func assets(albumID: String) async throws -> [Asset] { [] }
    func preview(assetID: String) async throws -> Data { Data() }
}

private struct StubTicker: SlideshowTicker {
    func waitForNextTick(duration: Duration) async throws {
        try await Task.sleep(for: .milliseconds(1))
    }
}

@MainActor
private final class StubScreen: ScreenControlling {
    var brightness: Double = 0.5
    var isIdleTimerDisabled = false
}
