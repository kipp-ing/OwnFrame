import Foundation
import Testing
import ThemeKit

// MARK: - (d) Widened Quiet Glass defaults

// @covers FR-500-03
@Test func clockSettingsDefaultsAreWidenedQuietGlassBaseline() {
    let clock = ClockSettings()

    #expect(clock.isOn == false)
    #expect(clock.style == .digits)
    #expect(clock.place == .bottomTrailing)
    #expect(clock.size == .room)
    #expect(clock.showDate == false)
    #expect(ClockSettings.off == clock)
}

// @covers FR-500-18
@Test func fixedPlacesExcludeRandomInDeclarationOrder() {
    #expect(ClockPlace.fixedPlaces == [
        .topLeading, .topCenter, .topTrailing,
        .bottomLeading, .bottomCenter, .bottomTrailing,
    ])
    #expect(!ClockPlace.fixedPlaces.contains(.random))
    #expect(ClockPlace.allCases.count == 7)
}

// MARK: - (a) Legacy corner raws decode unchanged (FR-510-05)

@MainActor
// @covers FR-500-18
@Test(arguments: [
    ("topLeading", ClockPlace.topLeading),
    ("topTrailing", ClockPlace.topTrailing),
    ("bottomLeading", ClockPlace.bottomLeading),
    ("bottomTrailing", ClockPlace.bottomTrailing),
])
func legacyCornerRawDecodesToMatchingPlace(raw: String, expected: ClockPlace) {
    let fixture = ClockDefaultsFixture()
    fixture.defaults.set(raw, forKey: "theme.clock.corner")

    let store = UserDefaultsThemeStore(defaults: fixture.defaults)

    #expect(store.settings.clock.place == expected)
}

// MARK: - (b) Unknown place raw degrades to the default without crashing

@MainActor
// @covers FR-500-16
@Test func unknownPlaceRawFallsBackToDefaultPlace() {
    let fixture = ClockDefaultsFixture()
    fixture.defaults.set("northByNorthwest", forKey: "theme.clock.corner")

    let store = UserDefaultsThemeStore(defaults: fixture.defaults)

    #expect(store.settings.clock.place == .bottomTrailing)
}

@MainActor
// @covers FR-500-16
@Test func unknownStyleAndSizeRawsFallBackToFieldDefaults() {
    let fixture = ClockDefaultsFixture()
    fixture.defaults.set("hologram", forKey: "theme.clock.style")
    fixture.defaults.set("enormous", forKey: "theme.clock.size")

    let store = UserDefaultsThemeStore(defaults: fixture.defaults)

    #expect(store.settings.clock.style == .digits)
    #expect(store.settings.clock.size == .room)
}

// MARK: - (c) New style/size persist and round-trip through a fresh store

@MainActor
// @covers FR-500-05
@Test func styleAndSizePersistAndRoundTripAcrossRelaunch() {
    let fixture = ClockDefaultsFixture()
    let store = UserDefaultsThemeStore(defaults: fixture.defaults)
    store.settings.clock = ClockSettings(
        isOn: true,
        style: .analog,
        place: .topCenter,
        size: .cozy,
        showDate: true
    )

    let relaunched = UserDefaultsThemeStore(defaults: fixture.defaults)

    #expect(relaunched.settings.clock.isOn == true)
    #expect(relaunched.settings.clock.style == .analog)
    #expect(relaunched.settings.clock.place == .topCenter)
    #expect(relaunched.settings.clock.size == .cozy)
    #expect(relaunched.settings.clock.showDate == true)
}

@MainActor
@Test func newPlaceRawPersistsUnderLegacyCornerKey() {
    let fixture = ClockDefaultsFixture()
    let store = UserDefaultsThemeStore(defaults: fixture.defaults)
    store.settings.clock.place = .bottomCenter

    // The key name stays `theme.clock.corner`; it now holds a ClockPlace raw.
    #expect(fixture.defaults.string(forKey: "theme.clock.corner") == "bottomCenter")
    #expect(fixture.defaults.string(forKey: "theme.clock.style") == "digits")
    #expect(fixture.defaults.string(forKey: "theme.clock.size") == "room")
}

// MARK: - (f) Size-constants table + legibility floor (SC-500-08)

// @covers FR-500-19
@Test func clockMetricsMatchDataModelTable() {
    #expect(ClockMetrics.digitPointSize(idiom: .pad, size: .room) == 76)
    #expect(ClockMetrics.digitPointSize(idiom: .pad, size: .cozy) == 52)
    #expect(ClockMetrics.digitPointSize(idiom: .phone, size: .room) == 92)
    #expect(ClockMetrics.digitPointSize(idiom: .phone, size: .cozy) == 64)

    #expect(ClockMetrics.analogDiameter(idiom: .pad, size: .room) == 250)
    #expect(ClockMetrics.analogDiameter(idiom: .pad, size: .cozy) == 180)
    #expect(ClockMetrics.analogDiameter(idiom: .phone, size: .room) == 210)
    #expect(ClockMetrics.analogDiameter(idiom: .phone, size: .cozy) == 150)
}

@Test func roomDigitSizeMeetsLegibilityFloor() {
    // SC-500-08: readable from ~1.5 m (~12 mm cap height).
    #expect(ClockMetrics.digitPointSize(idiom: .phone, size: .room) >= 74)
    #expect(ClockMetrics.digitPointSize(idiom: .pad, size: .room) >= 62)
}

// MARK: - (e) RandomPlacePicking (FR-510-03)

// @covers FR-500-18
@Test func randomPickerInitialPlacementPicksAFixedPlaceImmediately() {
    var picker = RandomPlacePicker(rng: SeededGenerator(seed: 42))

    let first = picker.place(now: .seconds(0), current: nil, occupied: [])

    #expect(first != .random)
    #expect(ClockPlace.fixedPlaces.contains(first))
}

// @covers FR-500-18
@Test func randomPickerHoldsBeforeCadenceElapses() {
    var picker = RandomPlacePicker(rng: SeededGenerator(seed: 42))
    let first = picker.place(now: .seconds(0), current: nil, occupied: [])

    let held = picker.place(now: .seconds(359), current: first, occupied: [])

    #expect(held == first)
}

// @covers FR-500-18
@Test func randomPickerRelocatesOnceCadenceElapses() {
    var picker = RandomPlacePicker(rng: SeededGenerator(seed: 42))
    let first = picker.place(now: .seconds(0), current: nil, occupied: [])

    let moved = picker.place(now: .seconds(360), current: first, occupied: [])

    #expect(moved != first)
    #expect(ClockPlace.fixedPlaces.contains(moved))
}

@Test func randomPickerNeverReturnsCurrentAcrossManyRelocations() {
    var picker = RandomPlacePicker(rng: SeededGenerator(seed: 7))
    var current = picker.place(now: .seconds(0), current: nil, occupied: [])
    var now = Duration.seconds(360)

    for _ in 0..<50 {
        let next = picker.place(now: now, current: current, occupied: [])
        #expect(next != current)
        #expect(ClockPlace.fixedPlaces.contains(next))
        current = next
        now += .seconds(360)
    }
}

@Test func randomPickerRespectsOccupiedSet() {
    let occupied: Set<ClockPlace> = [.topLeading, .topCenter, .topTrailing, .bottomLeading]
    var picker = RandomPlacePicker(rng: SeededGenerator(seed: 99))

    let first = picker.place(now: .seconds(0), current: nil, occupied: occupied)
    #expect(!occupied.contains(first))

    var current = first
    var now = Duration.seconds(360)
    for _ in 0..<20 {
        let next = picker.place(now: now, current: current, occupied: occupied)
        #expect(!occupied.contains(next))
        #expect(next != current)
        current = next
        now += .seconds(360)
    }
}

@Test func randomPickerMeasuresCadenceFromLastRelocationUnderMonotonicNow() {
    var picker = RandomPlacePicker(rng: SeededGenerator(seed: 5))
    let first = picker.place(now: .seconds(0), current: nil, occupied: [])

    let moved = picker.place(now: .seconds(360), current: first, occupied: [])
    #expect(moved != first)

    // Only 40 s since the relocation at t=360 (but 400 s since start) → holds.
    let held = picker.place(now: .seconds(400), current: moved, occupied: [])
    #expect(held == moved)

    // 360 s after the last relocation → relocates again.
    let moved2 = picker.place(now: .seconds(720), current: held, occupied: [])
    #expect(moved2 != moved)
}

@Test func randomPickerHonorsInjectedCadence() {
    var picker = RandomPlacePicker(rng: SeededGenerator(seed: 3), cadence: .seconds(60))
    let first = picker.place(now: .seconds(0), current: nil, occupied: [])

    #expect(picker.place(now: .seconds(59), current: first, occupied: []) == first)
    #expect(picker.place(now: .seconds(60), current: first, occupied: []) != first)
}

@Test func randomPickerIsDeterministicUnderSeededRNG() {
    func sequence(seed: UInt64) -> [ClockPlace] {
        var picker = RandomPlacePicker(rng: SeededGenerator(seed: seed))
        var current: ClockPlace?
        var now = Duration.seconds(0)
        var out: [ClockPlace] = []
        for _ in 0..<10 {
            let p = picker.place(now: now, current: current, occupied: [])
            out.append(p)
            current = p
            now += .seconds(360)
        }
        return out
    }

    #expect(sequence(seed: 123) == sequence(seed: 123))
    #expect(sequence(seed: 123) != sequence(seed: 456))
}

// MARK: - Fixtures

/// Deterministic SplitMix64 RNG so the picker's choices are reproducible in tests.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private final class ClockDefaultsFixture {
    let suite: String
    let defaults: UserDefaults

    init() {
        suite = "theme.clock.test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suite)
    }
}
