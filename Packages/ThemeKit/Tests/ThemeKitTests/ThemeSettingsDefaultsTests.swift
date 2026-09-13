import Testing
import ThemeKit

// @covers FR-500-03
@Test func themeSettingsDefaultsMatchDisplayOptionsSpec() {
    let settings = ThemeSettings()

    #expect(settings.order == .shuffle)
    #expect(settings.duration == .seconds(15))
    #expect(settings.transition == .crossfade)
    #expect(settings.kenBurns == false)
    #expect(settings.fit == .fit)
    #expect(settings.quality == .preview)
    #expect(settings.clock == ClockSettings.off)
    #expect(settings.clock.isOn == false)
    #expect(settings.clock.place == .bottomTrailing)
    #expect(settings.clock.showDate == false)
    // FR-310-14 (amended 2026-09-13, Jan: default on — the card is the visible proof of
    // the refresh, and the store set depicts it). A person can still turn it off in Settings.
    #expect(settings.newPhotosCard == true)
}

@Test func themeSettingsDurationRangeMatchesDisplayOptionsSpec() {
    #expect(ThemeSettings.durationRange == .seconds(3)...(.seconds(600)))
}
