/// Visibility of the Apple TV (Siri-Remote) chrome, with an auto-hide deadline.
public enum TVChromeState: Equatable, Sendable {
    case hidden
    /// Chrome is showing until the monotonic `Duration` reading `until` is reached.
    case visible(until: Duration)
}

/// Deterministic state machine for Apple TV chrome behavior (topic 1000, FR-1000-03).
///
/// No timers: the caller drives time by passing a monotonic clock reading (`Duration`) into
/// `remoteActivity` / `tick`, so every transition is host-testable without waiting. The view
/// layer owns the actual clock and a display-link / timer that calls `tick(now:)`.
public struct TVChromeModel: Sendable {
    /// How long the chrome stays visible after the last remote activity.
    public static let autoHide: Duration = .seconds(4.5)

    public private(set) var state: TVChromeState = .hidden

    public init() {}

    public var isVisible: Bool {
        switch state {
        case .hidden: return false
        case .visible: return true
        }
    }

    /// Any Siri-Remote activity reveals the chrome and (re)arms the auto-hide deadline a full
    /// `autoHide` interval past `now`. Called on every touch/click/swipe.
    public mutating func remoteActivity(now: Duration) {
        state = .visible(until: now + Self.autoHide)
    }

    /// Advance the clock. Hides the chrome once `now` reaches or passes the deadline; a no-op
    /// while already hidden or still before the deadline.
    public mutating func tick(now: Duration) {
        guard case let .visible(until) = state, now >= until else {
            return
        }
        state = .hidden
    }

    /// Menu-button press (FR-1000-03: "Menu hides chrome first, exits from the naked
    /// slideshow"). When chrome is visible it is consumed — the chrome hides and `true` is
    /// returned so the app does NOT exit. When already hidden it is not consumed — stays
    /// hidden and returns `false` so the system exits to Home.
    public mutating func menuPressed() -> Bool {
        guard isVisible else {
            return false
        }
        state = .hidden
        return true
    }
}
