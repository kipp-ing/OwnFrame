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
}

@Test func themeSettingsDurationRangeMatchesDisplayOptionsSpec() {
    #expect(ThemeSettings.durationRange == .seconds(3)...(.seconds(600)))
}
