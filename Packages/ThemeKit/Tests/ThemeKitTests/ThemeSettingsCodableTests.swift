import Foundation
import Testing
import ThemeKit

// Additive Codable conformance so display options can ride the iPad companion config-sync
// channel (topic 1000, FR-1000-06/12). This is JSON transport only; the per-key
// UserDefaultsThemeStore persistence is unchanged and covered elsewhere.

/// A fully-populated, all-non-default settings value round-trips byte-stably and stays `==`.
@Test func fullyPopulatedThemeSettingsRoundTripsByteStable() throws {
    let original = ThemeSettings(
        order: .sequential,
        duration: .seconds(42),
        transition: .dissolve,
        kenBurns: true,
        fit: .fill,
        quality: .original,
        clock: ClockSettings(
            isOn: true,
            style: .analog,
            place: .topCenter,
            size: .cozy,
            showDate: true
        )
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(ThemeSettings.self, from: data)

    #expect(decoded == original)

    // Byte-stable: re-encoding the decoded value yields identical bytes.
    let reEncoded = try encoder.encode(decoded)
    #expect(reEncoded == data)
}

/// The calm defaults round-trip too (the common publish case).
@Test func defaultThemeSettingsRoundTrips() throws {
    let original = ThemeSettings()

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ThemeSettings.self, from: data)

    #expect(decoded == original)
}

/// A couple of non-default clock configurations round-trip independently.
@Test(arguments: [
    ClockSettings(isOn: true, style: .pill, place: .random, size: .room, showDate: false),
    ClockSettings(isOn: true, style: .digits, place: .bottomLeading, size: .cozy, showDate: true),
    ClockSettings(isOn: false, style: .analog, place: .topTrailing, size: .room, showDate: false),
])
func nonDefaultClockConfigsRoundTrip(clock: ClockSettings) throws {
    let original = ThemeSettings(clock: clock)

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ThemeSettings.self, from: data)

    #expect(decoded == original)
    #expect(decoded.clock == clock)
}

/// Each RawRepresentable enum encodes to its raw string, so the JSON is stable across
/// versions and shares a wire shape with the UserDefaults raws.
@Test func clockPlaceEncodesToRawString() throws {
    let data = try JSONEncoder().encode(ClockPlace.bottomTrailing)
    #expect(String(data: data, encoding: .utf8) == "\"bottomTrailing\"")

    let decoded = try JSONDecoder().decode(ClockPlace.self, from: data)
    #expect(decoded == .bottomTrailing)
}
