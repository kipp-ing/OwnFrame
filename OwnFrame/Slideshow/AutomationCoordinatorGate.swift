//
//  AutomationCoordinatorGate.swift
//  OwnFrame
//
//  1100: the `.automation` gate on the HA/MQTT coordinator
//  (data-model.md §Gated feature mapping — "coordinator start in
//  SlideshowRemoteControlAdapter / TVRemoteControlAdapter").
//
//  Amended 2026-07-20: telemetry is free, only *control* is gated
//  (spec 1100 FR-1100-03 / FR-1100-03a).
//

import HAControlKit
import PurchaseKit

/// Wraps the app's HA coordinator factory and picks the tier the current entitlements allow.
///
/// The gate no longer blocks the coordinator — it selects its `Mode`:
/// - **No `.automation`** → `.telemetryOnly`: a configured broker still connects and publishes
///   read-only sensor entities, so Home Assistant can *see* the frame, but no controllable
///   entity is published and no command topic is subscribed (FR-1100-03a).
/// - **`.automation`** (or the everything-bundle) → `.full`: read + control.
///
/// It remains a *construction-time* selector, not a runtime mute. The wrapped factory is the
/// code that reaches `BrokerConfigProvider.load()` and from there the Keychain item holding the
/// MQTT password. Reading that credential is now a **free-tier** operation (telemetry needs it),
/// but the factory must still never *clear, migrate, or mask* stored configuration: buying
/// Automation later upgrades the same coordinator to `.full` with zero re-entry (FR-1100-14).
/// When no broker is configured at all, the factory returns `nil` and there is no coordinator.
///
/// Entitlements are read at call time (not captured at construction), so a purchase made while
/// the app runs upgrades telemetry → full on the next coordinator build without a relaunch.
@MainActor
struct AutomationCoordinatorGate: Sendable {
    private let entitlements: @MainActor @Sendable () -> EntitlementSet
    private let makeCoordinator: @MainActor @Sendable (SlideshowRemoteControlAdapter, HAControlCoordinator.Mode) async -> HAControlCoordinator?

    init(
        entitlements: @escaping @MainActor @Sendable () -> EntitlementSet,
        makeCoordinator: @escaping @MainActor @Sendable (SlideshowRemoteControlAdapter, HAControlCoordinator.Mode) async -> HAControlCoordinator?
    ) {
        self.entitlements = entitlements
        self.makeCoordinator = makeCoordinator
    }

    /// The tier the current entitlements allow: `.full` with Automation, else `.telemetryOnly`.
    func mode() -> HAControlCoordinator.Mode {
        entitlements().contains(.automation) ? .full : .telemetryOnly
    }

    /// Builds the coordinator in the allowed mode, or `nil` when no broker is configured.
    func callAsFunction(_ adapter: SlideshowRemoteControlAdapter) async -> HAControlCoordinator? {
        await makeCoordinator(adapter, mode())
    }
}
