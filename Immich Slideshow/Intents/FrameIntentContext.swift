//
//  FrameIntentContext.swift
//  Immich Slideshow
//
//  800: the app's composition root hands the process registry to the intent
//  shells here — set once at app init, before any intent can possibly run.
//  A deliberate, documented seam instead of AppDependencyManager: the platform
//  container only resolves inside its own intent-execution flow (out-of-flow
//  @AppDependency access traps, and every `add` variant is lazy with no public
//  getter), which would make the shells untestable app-hosted (FR-800-09).
//

import AppIntentsKit

@MainActor
enum FrameIntentContext {
    static var registry: FrameControlRegistry?

    /// The shells' single resolution point. `nil` is unreachable once the app
    /// initialized; mapped to the setup error rather than trapping.
    static func requireRegistry() throws(FrameIntentError) -> FrameControlRegistry {
        guard let registry else { throw .notConfigured }
        return registry
    }
}
