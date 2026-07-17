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
}
