import Testing
import ThemeKit

@Test func durationPresetsAreSortedAndWithinRange() {
    let presets = ThemeSettings.durationPresets
    #expect(!presets.isEmpty)
    #expect(presets == presets.sorted())
    for preset in presets {
        #expect(ThemeSettings.durationRange.contains(preset))
    }
}

@Test func durationOptionsForAPresetLeavesPresetsUnchanged() {
    let options = ThemeSettings.durationOptions(including: .seconds(15))
    #expect(options == ThemeSettings.durationPresets)
}

// The reinstall bug: a non-preset duration (e.g. 20 s pushed via Home Assistant,
// retained on the MQTT broker across a device reinstall) must still be a selectable
// option so the settings Picker has a matching tag and never renders blank.
@Test func durationOptionsMergesNonPresetValueSoItIsSelectable() {
    let custom: Duration = .seconds(20)
    let options = ThemeSettings.durationOptions(including: custom)

    #expect(options.contains(custom))
    #expect(options == options.sorted())
    #expect(options.count == ThemeSettings.durationPresets.count + 1)
    for preset in ThemeSettings.durationPresets {
        #expect(options.contains(preset))
    }
}

@Test func durationOptionsAlwaysContainTheCurrentValue() {
    for seconds in stride(from: 3, through: 600, by: 7) {
        let current: Duration = .seconds(seconds)
        #expect(ThemeSettings.durationOptions(including: current).contains(current))
    }
}
