import Foundation

/// A point-in-time battery snapshot. Deliberately UIKit-free so `HAControlKit` stays
/// portable and host-testable; the app adapter fills it from `UIDevice`, and Apple TV never
/// provides one at all.
public struct BatteryReading: Sendable, Equatable {
    /// Charge percentage 0–100, or `nil` when unavailable (monitoring not ready yet, or the
    /// device reports an unknown level). `nil` means "publish nothing yet" — never a
    /// misleading 0%.
    public let level: Int?
    /// `true` while the device is charging or full on external power; `false` on battery or
    /// in an unknown state (an unknown state must never read as a false "on power").
    public let isOnPower: Bool

    public init(level: Int?, isOnPower: Bool) {
        self.level = level
        self.isOnPower = isOnPower
    }
}

/// Read-only battery telemetry seam (spec 710 FR-710-23 / SC-710-07). Implemented by the app
/// adapter over `UIDevice`, injected into `HAControlCoordinator` so the `battery` and
/// `charging` diagnostic entities can publish without `HAControlKit` importing UIKit.
///
/// A source with `hasBattery == false` (Apple TV), or no source at all, means the coordinator
/// omits both entities entirely — no discovery, no state. The change signal lets the adapter
/// push a fresh reading into the coordinator's echo path when the level or power state
/// changes (mirrors `PhotoReporting.onPhotoChange` / `SettingsControlling.onSettingsChange`).
@MainActor
public protocol BatteryReporting: AnyObject {
    /// Whether this device has a battery at all. Batteryless devices report `false`, and the
    /// coordinator then omits `battery`/`charging` from discovery and state.
    var hasBattery: Bool { get }
    /// The current reading, read on every echo so it always reflects the latest state.
    var current: BatteryReading { get }
    /// Fired on the main actor whenever the reading changes, so the coordinator re-echoes
    /// `battery`/`charging`.
    var onBatteryChange: (@MainActor () -> Void)? { get set }
}
