import Foundation

/// The effective brightness mode (410, FR-410-08): `auto` while OwnFrame leaves brightness to
/// iOS, `fixed` while it holds a level (a preset, a remote level, or the night level).
public enum BrightnessModeSetting: String, Sendable, Equatable, CaseIterable {
    case auto
    case fixed
}

/// Optional brightness-mode/night-window telemetry + control seam (410, FR-410-08/FR-410-19),
/// injected into `HAControlCoordinator` like `BatteryReporting`. Implemented by the app's
/// `BrightnessController` adapter; `HAControlKit` stays free of `PowerKit`/UIKit.
///
/// A source is optional (`nil` on tvOS, which keeps driving `PowerManager` directly): without
/// one, the coordinator omits `brightness_mode`, `night_window` and `night_active` entirely —
/// no discovery, no state, same as battery without a source.
@MainActor
public protocol BrightnessModeControlling: AnyObject {
    /// The effective mode right now: `.auto` while OwnFrame leaves brightness to iOS, `.fixed`
    /// while it holds a level (a preset, a remote level, or the night level).
    var brightnessMode: BrightnessModeSetting { get }
    /// Whether the in-app night window is currently active (inside its time range and enabled).
    var isNightActive: Bool { get }
    /// Whether the in-app night window is switched on.
    var isNightWindowEnabled: Bool { get }
    /// Remote mode command (session override in the app, FR-410-07/08).
    func setBrightnessMode(_ mode: BrightnessModeSetting)
    /// Remote switch for the app's night window (FR-410-19).
    func setNightWindowEnabled(_ isOn: Bool)
    /// Fired on the main actor when any of the three values changes, so the coordinator
    /// re-echoes them (mirrors `BatteryReporting.onBatteryChange`).
    var onBrightnessModeChange: (@MainActor () -> Void)? { get set }
}
