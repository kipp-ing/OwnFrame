import Foundation
import Testing
@testable import PowerKit

/// 410 T002/T003: the night window is evaluated on local wall-clock minutes every time
/// (across midnight, DST, time-zone changes), and the settings default to "write nothing".
@Suite("410 NightWindow + BrightnessSettings")
struct BrightnessSettingsTests {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ string: String, _ zone: String = "Europe/Berlin") -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string)!
    }

    @Test func sameDayWindowContainsStartExcludesEnd() {
        let window = NightWindow(isEnabled: true, startMinute: 13 * 60, endMinute: 15 * 60, level: 0)
        let cal = calendar("Europe/Berlin")
        #expect(!window.contains(date("2026-09-28 12:59"), calendar: cal))
        #expect(window.contains(date("2026-09-28 13:00"), calendar: cal))
        #expect(window.contains(date("2026-09-28 14:59"), calendar: cal))
        #expect(!window.contains(date("2026-09-28 15:00"), calendar: cal))
    }

    @Test func windowAcrossMidnight() {
        let window = NightWindow(isEnabled: true, startMinute: 23 * 60, endMinute: 7 * 60, level: 0)
        let cal = calendar("Europe/Berlin")
        #expect(window.contains(date("2026-09-28 23:30"), calendar: cal))
        #expect(window.contains(date("2026-09-29 02:00"), calendar: cal))
        #expect(!window.contains(date("2026-09-29 07:00"), calendar: cal))
        #expect(!window.contains(date("2026-09-28 22:59"), calendar: cal))
    }

    @Test func equalStartAndEndIsNoWindow() {
        let window = NightWindow(isEnabled: true, startMinute: 60, endMinute: 60, level: 0)
        #expect(!window.contains(date("2026-09-28 01:00"), calendar: calendar("Europe/Berlin")))
    }

    @Test func disabledWindowNeverContains() {
        let window = NightWindow(isEnabled: false, startMinute: 0, endMinute: 23 * 60, level: 0)
        #expect(!window.contains(date("2026-09-28 12:00"), calendar: calendar("Europe/Berlin")))
    }

    @Test func wallClockFollowsTheCalendarsTimeZone() {
        // 23:30 Berlin is 22:30 London: inside a 23:00–07:00 window only in Berlin.
        let window = NightWindow(isEnabled: true, startMinute: 23 * 60, endMinute: 7 * 60, level: 0)
        let instant = date("2026-09-28 23:30")
        #expect(window.contains(instant, calendar: calendar("Europe/Berlin")))
        #expect(!window.contains(instant, calendar: calendar("Europe/London")))
    }

    @Test func dstSpringForwardStillEvaluatesWallClock() {
        // 2026-03-29 02:00 → 03:00 in Berlin. 03:30 local is inside 23:00–07:00.
        let window = NightWindow(isEnabled: true, startMinute: 23 * 60, endMinute: 7 * 60, level: 0)
        #expect(window.contains(date("2026-03-29 03:30"), calendar: calendar("Europe/Berlin")))
        #expect(!window.contains(date("2026-03-29 07:30"), calendar: calendar("Europe/Berlin")))
    }

    @Test func defaultsWriteNothing() {
        let settings = BrightnessSettings()
        #expect(settings.mode == .automatic)
        #expect(settings.night.isEnabled == false)
        #expect(settings.night.level == 0.0)
        #expect(settings.night.startMinute == 23 * 60)
        #expect(settings.night.endMinute == 7 * 60)
        #expect(settings.preset > 0 && settings.preset <= 1)
    }

    @Test func nightLevelIsBoundedToTheDarkEnd() {
        #expect(NightWindow(isEnabled: true, startMinute: 0, endMinute: 60, level: 0.9).level == NightWindow.maxLevel)
        #expect(NightWindow(isEnabled: true, startMinute: 0, endMinute: 60, level: -1).level == 0)
        #expect(BrightnessSettings(mode: .fixed, preset: 1.7).preset == 1.0)
    }

    @MainActor @Test func userDefaultsStoreRoundTrips() throws {
        let suite = "410-store-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = UserDefaultsBrightnessStore(defaults: defaults)
        #expect(store.settings == BrightnessSettings())
        #expect(store.preNightBaseline == nil)

        var settings = BrightnessSettings(mode: .fixed, preset: 0.8)
        settings.night = NightWindow(isEnabled: true, startMinute: 22 * 60, endMinute: 6 * 60, level: 0.1)
        store.settings = settings
        store.preNightBaseline = 0.55

        let reloaded = UserDefaultsBrightnessStore(defaults: defaults)
        #expect(reloaded.settings == settings)
        #expect(reloaded.preNightBaseline == 0.55)

        reloaded.preNightBaseline = nil
        #expect(UserDefaultsBrightnessStore(defaults: defaults).preNightBaseline == nil)
    }
}
