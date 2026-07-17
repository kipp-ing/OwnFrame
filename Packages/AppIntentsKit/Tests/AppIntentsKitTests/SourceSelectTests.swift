import Testing
import HAControlKit
import AppIntentsTestSupport
@testable import AppIntentsKit

/// T020: `FrameCommandService.selectSource` — id resolution against the
/// registry's `sourceOptions`, HA-parity apply via the resolved label, the
/// deleted-source edge (`.sourceMissing`, zero calls, resolution beats
/// availability), and duplicate-label first-match parity (data-model.md
/// "FrameCommandService", contracts § SourceEntity).
@MainActor
struct SourceSelectTests {

    // MARK: - Live id applies via the resolved label

    @Test
    func liveId_appliesViaTheResolvedLabelNotTheCallersStaleName() async throws {
        // Rename-with-same-id robustness: the caller passes a stale display
        // name ("Old Stale Name") but the recorded call carries the label
        // resolved from the library ("New") — the byte-identical HA path.
        let registry = FrameControlRegistry()
        registry.isConfigured = true
        registry.sourceOptions = { [SourceOption(id: "s1", label: "New")] }
        let surface = RecordingControlSurface()
        registry.register(surface)
        let service = FrameCommandService(registry: registry)

        try await service.selectSource(id: "s1", label: "Old Stale Name")
        #expect(surface.calls == [.selectAlbum("New")])
    }

    // MARK: - Deleted-source edge

    @Test
    func staleId_throwsSourceMissingWithTheCallersLabelAndZeroCalls() async {
        let registry = FrameControlRegistry()
        registry.isConfigured = true
        registry.sourceOptions = { [SourceOption(id: "s1", label: "Real")] }
        let surface = RecordingControlSurface()
        registry.register(surface)
        let service = FrameCommandService(registry: registry)

        await expectSourceMissing(label: "Vacation") {
            try await service.selectSource(id: "gone", label: "Vacation")
        }
        #expect(surface.calls.isEmpty)
    }

    @Test
    func staleId_failsFastEvenWhenNotLive_withoutTouchingTheSleepSeam() async {
        // Options lookup runs BEFORE awaitReady (data-model.md resolution
        // order) — a stale id must fail fast even while the frame is closed.
        // The injected sleep records an Issue if ever invoked instead of
        // hanging, so a regression here shows up as a red assertion, never a
        // stuck `swift test` process.
        let registry = FrameControlRegistry(sleep: { _ in
            Issue.record("sleep seam touched — a stale id must fail before awaitReady")
        })
        registry.isConfigured = true
        registry.sourceOptions = { [] }
        let service = FrameCommandService(registry: registry)

        await expectSourceMissing(label: "X") {
            try await service.selectSource(id: "gone", label: "X")
        }
    }

    // MARK: - Duplicate labels, distinct ids

    @Test
    func duplicateLabels_selectingByIdAppliesTheSharedLabel() async throws {
        // Parity note: the adapter's `selectAlbum(_:)` resolves by label, first
        // match wins — exactly like the HA select. Selecting the second id
        // still ends up applying the shared label; this documents that
        // existing behavior rather than fixing it.
        let registry = FrameControlRegistry()
        registry.isConfigured = true
        registry.sourceOptions = {
            [SourceOption(id: "a", label: "Dup"), SourceOption(id: "b", label: "Dup")]
        }
        let surface = RecordingControlSurface()
        registry.register(surface)
        let service = FrameCommandService(registry: registry)

        try await service.selectSource(id: "b", label: "Dup")
        #expect(surface.calls == [.selectAlbum("Dup")])
    }

    // MARK: - Availability still checked for the apply path

    @Test
    func unconfiguredRegistry_liveIdInOptions_throwsNotConfiguredWithZeroCalls() async {
        // A valid id resolves against sourceOptions, but the registry itself
        // is unconfigured — notConfigured must still win before any apply.
        let registry = FrameControlRegistry(sleep: { _ in
            Issue.record("sleep must not be called — notConfigured short-circuits before awaitReady's timeout wait")
        })
        registry.sourceOptions = { [SourceOption(id: "s1", label: "Real")] }
        let surface = RecordingControlSurface()
        registry.register(surface)
        let service = FrameCommandService(registry: registry)

        await expectNotConfigured { try await service.selectSource(id: "s1", label: "Real") }
        #expect(surface.calls.isEmpty)
    }
}

/// Awaits a `selectSource` call expected to fail with `.sourceMissing(label:)`.
@MainActor
private func expectSourceMissing(
    label: String,
    _ operation: () async throws -> Void,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    do {
        try await operation()
        Issue.record("expected .sourceMissing(label: \(label)) to be thrown", sourceLocation: sourceLocation)
    } catch let error as FrameCommandError {
        #expect(error == .sourceMissing(label: label), sourceLocation: sourceLocation)
    } catch {
        Issue.record("expected FrameCommandError, got \(error)", sourceLocation: sourceLocation)
    }
}

/// Awaits an operation expected to fail with `.notConfigured` (copied from
/// FrameCommandServiceTests — top-level `private` is file-scoped in Swift, so
/// this is a distinct declaration, not a redeclaration).
@MainActor
private func expectNotConfigured(
    _ operation: () async throws -> Void,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    do {
        try await operation()
        Issue.record("expected .notConfigured to be thrown", sourceLocation: sourceLocation)
    } catch let error as FrameCommandError {
        #expect(error == .notConfigured, sourceLocation: sourceLocation)
    } catch {
        Issue.record("expected FrameCommandError, got \(error)", sourceLocation: sourceLocation)
    }
}
