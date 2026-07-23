//
//  FrameIntentContext.swift
//  OwnFrame
//
//  800: the app's composition root hands the process registry to the intent
//  shells here — set once at app init, before any intent can possibly run.
//  A deliberate, documented seam instead of AppDependencyManager: the platform
//  container only resolves inside its own intent-execution flow (out-of-flow
//  @AppDependency access traps, and every `add` variant is lazy with no public
//  getter), which would make the shells untestable app-hosted (FR-800-09).
//

import AppIntentsKit
import PurchaseKit

@MainActor
enum FrameIntentContext {
    static var registry: FrameControlRegistry?

    /// What the frame owns (1100). Same seam shape as `registry`: the composition root
    /// points this at the live `EntitlementStore` at app init. The default owns nothing, so
    /// an intent that somehow runs before wiring fails closed with a readable unlock message
    /// rather than handing out a paid capability.
    static var entitlements: @MainActor () -> EntitlementSet = { EntitlementSet.none }

    /// The shells' single resolution point. `nil` is unreachable once the app
    /// initialized; mapped to the setup error rather than trapping.
    static func requireRegistry() throws(FrameIntentError) -> FrameControlRegistry {
        guard let registry else { throw .notConfigured }
        return registry
    }

    /// The Supporter-Unlock guard every intent runs FIRST (1100, data-model.md §Gated feature
    /// mapping). Ahead of `requireRegistry()` on purpose: an unentitled *and* unconfigured
    /// frame must report the unlock, not send the owner off to fix a setup that was never
    /// the problem. Running it first also keeps a locked intent inert — it never moves the
    /// frame and then complains.
    static func requireSupporterUnlock() throws(FrameIntentError) {
        guard entitlements().contains(.supporter) else { throw .supporterRequired }
    }
}
