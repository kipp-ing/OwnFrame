/// The ambience latch: what Ken Burns motion and the clock overlay should *actually*
/// do right now (spec 1100, data-model.md §Gated feature mapping).
///
/// The gate exists to make entitlement changes **boundary-aligned** rather than instantaneous.
/// A refund landing mid-photo must not freeze a pan halfway through, and a purchase completing
/// mid-photo must not set a still photo moving underneath the viewer (FR-1100-12). So the value
/// is *latched*: it holds whatever was last passed to ``init(entitled:)`` or ``relatch(entitled:)``
/// and only changes when the caller re-latches at a natural boundary — a photo advance or an
/// app foreground.
///
/// It is a pure value: no clock, no I/O, no SwiftUI, and — deliberately — **no settings**. The
/// stored user preferences (`ThemeSettings.kenBurns`, `ClockSettings.isOn`) are passed in per
/// call and never held, read, written, masked, or migrated here. PurchaseKit subtracts from the
/// user's configuration at the point of rendering; it never touches the configuration itself
/// (FR-1100-14, data-model.md §Invariants). That is also why the state topics HA publishes keep
/// reporting the stored values while an unentitled frame renders them off — data and rendering
/// are allowed to disagree.
///
/// Both features are granted by the single Supporter Unlock, so the two accessors are the same
/// truth table. They stay as two accessors so a future split would be a deliberate change here,
/// not a scattered one.
public struct AmbienceGate: Equatable, Sendable {

    /// The last latched entitlement. Not the live one — that is the whole point.
    private var latchedEntitled: Bool

    /// Latches the initial entitlement, normally read at the moment the slideshow starts.
    public init(entitled: Bool) {
        latchedEntitled = entitled
    }

    /// Adopts the current entitlement at a boundary (photo advance, foreground).
    ///
    /// Called on every advance, so the overwhelmingly common case is an unchanged value —
    /// which is a plain no-op.
    public mutating func relatch(entitled: Bool) {
        latchedEntitled = entitled
    }

    /// Whether Ken Burns motion should run, given the user's stored setting.
    ///
    /// The gate only ever subtracts: being entitled never switches on motion the user turned off.
    public func effectiveKenBurns(setting: Bool) -> Bool {
        setting && latchedEntitled
    }

    /// Whether the clock overlay should render, given the user's stored setting.
    public func effectiveClock(setting: Bool) -> Bool {
        setting && latchedEntitled
    }
}
