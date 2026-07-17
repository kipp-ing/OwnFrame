import Foundation
import HAControlKit

/// All intent logic (data-model.md "FrameCommandService"). One method per intent
/// verb, kept one-call thin so the app-target shells never carry logic
/// (research R2, FR-800-09).
@MainActor
public struct FrameCommandService {
    private let registry: FrameControlRegistry

    public init(registry: FrameControlRegistry) {
        self.registry = registry
    }

    public func pause() async throws(FrameCommandError) {
        let surface = try await registry.awaitReady()
        surface.pause()
    }

    public func resume() async throws(FrameCommandError) {
        let surface = try await registry.awaitReady()
        surface.resume()
    }

    public func nextPhoto() async throws(FrameCommandError) {
        let surface = try await registry.awaitReady()
        await surface.showNext()
    }

    public func previousPhoto() async throws(FrameCommandError) {
        let surface = try await registry.awaitReady()
        await surface.showPrevious()
    }

    public func setBrightness(percent: Int) async throws(FrameCommandError) {
        // Parameter errors beat availability errors: reject — never clamp — before
        // the registry is ever touched (US1 acceptance 4, research R5).
        guard (0...100).contains(percent) else {
            throw .brightnessOutOfRange(percent)
        }
        let surface = try await registry.awaitReady()
        await surface.setBrightness(Double(percent) / 100.0)
    }

    public func selectSource(id: String, label: String) async throws(FrameCommandError) {
        // Resolution order: options lookup BEFORE awaitReady — a stale id must
        // fail fast even while the frame is closed (data-model.md resolution
        // order, spec Edge #2 deleted-source parity with brightness's
        // "parameter errors beat availability errors" stance). `label` here is
        // only ever used in the error payload — the apply below always uses
        // the label resolved from the library, never the caller's.
        guard let option = registry.sourceOptions().first(where: { $0.id == id }) else {
            throw .sourceMissing(label: label)
        }
        let surface = try await registry.awaitReady()
        surface.selectAlbum(option.label)
    }

    public func frameState() async throws(FrameCommandError) -> FrameStateSnapshot {
        let surface = try await registry.awaitReady()
        let report = surface.currentPhotoReport
        return FrameStateSnapshot(
            isPlaying: surface.playbackState == .playing,
            brightnessPercent: Int((surface.brightness * 100).rounded()),
            sourceLabel: surface.currentAlbum,
            photoDate: report.takenAt,
            photoCity: report.city,
            photoCountry: report.country
        )
    }
}
