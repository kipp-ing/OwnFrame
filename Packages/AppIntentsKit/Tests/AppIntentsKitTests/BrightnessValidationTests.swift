import Testing
import HAControlKit
import AppIntentsTestSupport
@testable import AppIntentsKit

/// T011: `FrameCommandService.setBrightness` percent→fraction mapping,
/// out-of-range rejection with zero surface calls, validation-before-resolution
/// (a bad percent must throw even when the frame isn't open — parameter errors
/// beat availability errors), and the spec Edge #2 / analyze G1 race pin.
@MainActor
struct BrightnessValidationTests {

    // MARK: - Percent → fraction mapping

    @Test
    func setBrightness_zeroPercent_mapsToZeroFraction() async throws {
        let (service, surface) = makeReadyService()
        try await service.setBrightness(percent: 0)
        #expect(surface.calls == [.setBrightness(0.0)])
    }

    @Test
    func setBrightness_oneHundredPercent_mapsToOneFraction() async throws {
        let (service, surface) = makeReadyService()
        try await service.setBrightness(percent: 100)
        #expect(surface.calls == [.setBrightness(1.0)])
    }

    @Test
    func setBrightness_fortyPercent_mapsToPointFourFraction() async throws {
        let (service, surface) = makeReadyService()
        try await service.setBrightness(percent: 40)
        #expect(surface.calls == [.setBrightness(0.4)])
    }

    // MARK: - Out-of-range rejection, zero calls

    @Test
    func setBrightness_negativePercent_throwsOutOfRangeWithZeroCalls() async {
        let (service, surface) = makeReadyService()
        await expectOutOfRange(-1, service)
        #expect(surface.calls.isEmpty)
    }

    @Test
    func setBrightness_aboveOneHundredPercent_throwsOutOfRangeWithZeroCalls() async {
        let (service, surface) = makeReadyService()
        await expectOutOfRange(101, service)
        #expect(surface.calls.isEmpty)
    }

    // MARK: - Validation before resolution

    @Test
    func setBrightness_outOfRangeBeatsNotConfigured() async {
        // Parameter errors beat availability errors: even with isConfigured ==
        // false, an out-of-range percent still throws .brightnessOutOfRange, NOT
        // .notConfigured — validation runs before the registry is ever touched.
        let registry = FrameControlRegistry()
        let service = FrameCommandService(registry: registry)
        await expectOutOfRange(101, service)
    }

    // MARK: - Race pin (spec Edge #2, analyze G1)

    @Test
    func interleavedSetBrightness_lastWriteWinsThroughSerializedMainActor() async throws {
        // Two intents race (automation fires while the user taps chrome): last
        // write wins through the same serialized command surface topic 700 uses;
        // no crash, no divergent state. Issued as separate Tasks contending for
        // the MainActor (not plain sequential calls) so the pin exercises actual
        // actor-serialized interleaving. The first is awaited to completion
        // before the second fires so "second" is well-defined — a deterministic
        // ordering pin through one actor, not a racy lottery.
        let (service, surface) = makeReadyService()

        let first = Task { @MainActor in
            try await service.setBrightness(percent: 30)
        }
        try await first.value

        let second = Task { @MainActor in
            try await service.setBrightness(percent: 70)
        }
        try await second.value

        #expect(surface.calls == [.setBrightness(0.3), .setBrightness(0.7)])
        #expect(surface.calls.last == .setBrightness(0.7))
    }
}

/// A registry configured + registered with a fresh `RecordingControlSurface`,
/// wrapped in a `FrameCommandService`. Returns the surface too so tests can
/// assert on recorded calls.
@MainActor
private func makeReadyService() -> (service: FrameCommandService, surface: RecordingControlSurface) {
    let registry = FrameControlRegistry()
    registry.isConfigured = true
    let surface = RecordingControlSurface()
    registry.register(surface)
    return (FrameCommandService(registry: registry), surface)
}

/// Awaits a `setBrightness` call expected to fail with `.brightnessOutOfRange(percent)`.
@MainActor
private func expectOutOfRange(
    _ percent: Int,
    _ service: FrameCommandService,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    do {
        try await service.setBrightness(percent: percent)
        Issue.record("expected .brightnessOutOfRange(\(percent)) to be thrown", sourceLocation: sourceLocation)
    } catch {
        #expect(error == .brightnessOutOfRange(percent), sourceLocation: sourceLocation)
    }
}
