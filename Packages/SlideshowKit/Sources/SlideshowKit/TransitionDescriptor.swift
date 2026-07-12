import Foundation
import ThemeKit

/// A SwiftUI-free description of how a transition should behave, so the mapping from the
/// persisted `Transition` enum is unit-testable on the host. The actual SwiftUI
/// `AnyTransition` and animation curve are built in the view (simulator-verified).
///
/// Review R5: the image swap chooses its transition at runtime, and `.none` disables
/// animation entirely (`animates == false`) so there is no residual cross-fade.
public struct TransitionDescriptor: Equatable, Sendable {
    public enum Style: String, Equatable, Sendable {
        case crossfade
        case slide
        case dissolve
        case none
    }

    public let style: Style

    /// Whether the image swap animates at all. False only for `.none`.
    public var animates: Bool { style != .none }

    /// The style the view should actually build. Dissolve's built-in scale would
    /// stack a second, eased zoom on top of the Ken Burns drift (a fast "catch-up"
    /// that breaks the continuous motion), so while Ken Burns is on it degrades to
    /// the opacity-only crossfade — the drift itself supplies the motion.
    public func effectiveStyle(kenBurns: Bool) -> Style {
        kenBurns && style == .dissolve ? .crossfade : style
    }

    public init(style: Style) {
        self.style = style
    }
}

public extension Transition {
    /// The host-tested descriptor that drives the view's transition + animation.
    var descriptor: TransitionDescriptor {
        switch self {
        case .crossfade: TransitionDescriptor(style: .crossfade)
        case .slide: TransitionDescriptor(style: .slide)
        case .dissolve: TransitionDescriptor(style: .dissolve)
        case .none: TransitionDescriptor(style: .none)
        }
    }
}
