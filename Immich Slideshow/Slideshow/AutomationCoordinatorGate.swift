//
//  AutomationCoordinatorGate.swift
//  Immich Slideshow
//
//  1100: the `.automation` gate on the HA/MQTT coordinator
//  (data-model.md §Gated feature mapping — "coordinator start in
//  SlideshowRemoteControlAdapter / TVRemoteControlAdapter").
//

import HAControlKit
import PurchaseKit

/// Wraps the app's HA coordinator factory and refuses to run it without `.automation`.
///
/// It is deliberately a *wrapper* rather than a `guard` inside the factory. The wrapped
/// closure is the code that reaches `BrokerConfigProvider.load()`, and from there the
/// Keychain item holding the MQTT password; short-circuiting **before** invoking it makes
/// "an unentitled device never touches the stored broker credentials" a structural property
/// of the composition rather than a convention someone has to keep re-reading the factory to
/// preserve (FR-1100-14).
///
/// The gate is also strictly a construction gate, never a runtime mute: without the tier no
/// coordinator exists, so there is no transport, no connect, and no discovery — and equally
/// nothing is cleared, masked, or migrated. Buying Automation later re-enables HA with zero
/// re-entry, because the configuration was never touched.
@MainActor
struct AutomationCoordinatorGate: Sendable {
    private let entitlements: @MainActor @Sendable () -> EntitlementSet
    private let makeCoordinator: @MainActor @Sendable (SlideshowRemoteControlAdapter) async -> HAControlCoordinator?

    init(
        entitlements: @escaping @MainActor @Sendable () -> EntitlementSet,
        makeCoordinator: @escaping @MainActor @Sendable (SlideshowRemoteControlAdapter) async -> HAControlCoordinator?
    ) {
        self.entitlements = entitlements
        self.makeCoordinator = makeCoordinator
    }

    /// Builds the coordinator, or `nil` when the frame does not own Automation.
    ///
    /// Entitlements are read at call time (not captured at construction), so a purchase made
    /// while the app runs opens the gate on the next coordinator build without a relaunch.
    func callAsFunction(_ adapter: SlideshowRemoteControlAdapter) async -> HAControlCoordinator? {
        guard entitlements().contains(.automation) else { return nil }
        return await makeCoordinator(adapter)
    }
}
