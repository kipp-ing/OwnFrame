import Foundation
import Testing
import ThemeKit

@MainActor
@Test func userDefaultsThemeStoreRoundTripsEveryFieldAcrossRelaunch() {
    let fixture = UserDefaultsThemeStoreFixture()

    let store = UserDefaultsThemeStore(defaults: fixture.defaults)
    store.settings = ThemeSettings(
        order: .sequential,
        duration: .seconds(30),
        transition: .slide,
        kenBurns: true,
        fit: .fill,
        quality: .original,
        clock: ClockSettings(isOn: true, place: .topLeading, showDate: true)
    )

    let relaunchedStore = UserDefaultsThemeStore(defaults: fixture.defaults)
    #expect(relaunchedStore.settings.order == .sequential)
    #expect(relaunchedStore.settings.duration == .seconds(30))
    #expect(relaunchedStore.settings.transition == .slide)
    #expect(relaunchedStore.settings.kenBurns == true)
    #expect(relaunchedStore.settings.fit == .fill)
    #expect(relaunchedStore.settings.quality == .original)
    #expect(relaunchedStore.settings.clock.isOn == true)
    #expect(relaunchedStore.settings.clock.place == .topLeading)
    #expect(relaunchedStore.settings.clock.showDate == true)
}

@MainActor
@Test func userDefaultsThemeStoreFallsBackPerFieldForCorruptValues() {
    let fixture = UserDefaultsThemeStoreFixture()
    fixture.defaults.set("garbage", forKey: "theme.order")
    fixture.defaults.set("fill", forKey: "theme.fit")

    let store = UserDefaultsThemeStore(defaults: fixture.defaults)

    #expect(store.settings.order == .shuffle)
    #expect(store.settings.fit == .fill)
    #expect(store.settings.duration == .seconds(15))
    #expect(store.settings.transition == .crossfade)
    #expect(store.settings.kenBurns == false)
    #expect(store.settings.quality == .preview)
    #expect(store.settings.clock == .off)
}

@MainActor
@Test func userDefaultsThemeStoreUsesDefaultsForEmptySuite() {
    let fixture = UserDefaultsThemeStoreFixture()

    let store = UserDefaultsThemeStore(defaults: fixture.defaults)

    #expect(store.settings == ThemeSettings())
}

@MainActor
@Test func userDefaultsThemeStoreClampsDurationImmediatelyAndAcrossRelaunch() {
    let fixture = UserDefaultsThemeStoreFixture()
    let store = UserDefaultsThemeStore(defaults: fixture.defaults)

    store.settings.duration = .seconds(1)
    #expect(store.settings.duration == .seconds(3))
    #expect(UserDefaultsThemeStore(defaults: fixture.defaults).settings.duration == .seconds(3))

    store.settings.duration = .seconds(999)
    #expect(store.settings.duration == .seconds(600))
    #expect(UserDefaultsThemeStore(defaults: fixture.defaults).settings.duration == .seconds(600))

    store.settings.duration = .seconds(30)
    #expect(store.settings.duration == .seconds(30))
    #expect(UserDefaultsThemeStore(defaults: fixture.defaults).settings.duration == .seconds(30))
}

private final class UserDefaultsThemeStoreFixture {
    let suite: String
    let defaults: UserDefaults

    init() {
        suite = "theme.test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suite)
    }
}
