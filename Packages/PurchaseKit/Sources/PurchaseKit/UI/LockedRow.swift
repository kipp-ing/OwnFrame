import SwiftUI

// Shipping UI — deliberately NOT `#if DEBUG` (unlike StubStoreClient.swift / UITestSeams.swift
// in this package, which must not exist in a release binary at all). This is what a user sees.

extension Entitlement {

    /// The user-facing unlock name, as it appears on locked badges and unlock screens.
    ///
    /// Presentation only, which is why it lives beside the view rather than in the model: the
    /// entitlement itself is a capability, not a marketing name. Not localized — the repo ships
    /// English-only by design (CLAUDE.md).
    public var displayName: String {
        switch self {
        case .supporter: "Supporter"
        }
    }
}

/// A settings row for a feature the user does not own yet: dimmed **and** badged, but still
/// tappable (spec 1100, FR-1100-09).
///
/// The dimmed-but-tappable rule is the whole point. A plainly disabled iOS control reads as
/// "broken" and is never tapped, so the user never discovers what the feature is or how to get
/// it. Hence: reduced opacity to de-emphasize, a lock glyph + tier badge to explain *why* it is
/// de-emphasized, and a live tap target that opens the unlock screen.
///
/// This view never presents anything itself. It calls `action`, and the call site decides —
/// PurchaseKit must not auto-present purchase UI (SC-1100-02).
///
/// ```swift
/// LockedRow(requires: .supporter, identifier: "settings.row.kenburns.locked") {
///     showUnlock = true
/// } content: {
///     Toggle(isOn: $themeStore.settings.kenBurns) {
///         Label("Ken Burns", systemImage: "camera.viewfinder")
///     }
/// }
/// ```
public struct LockedRow<Content: View>: View {

    /// How far the wrapped row is de-emphasized. Deliberately well above the ~0.3 that iOS uses
    /// for disabled controls: it must read as "not yours yet", not as "not available".
    private static var dimmedOpacity: Double { 0.55 }

    private let tier: Entitlement
    private let identifier: String
    private let action: () -> Void
    private let content: Content

    /// Dimming is a legibility cost. When the user has asked the system to reduce transparency,
    /// drop it and let the badge carry the locked state on its own.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    #if os(tvOS)
    @FocusState private var isFocused: Bool
    #endif

    public init(
        requires tier: Entitlement,
        identifier: String,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.tier = tier
        self.identifier = identifier
        self.action = action
        self.content = content()
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                content
                    .opacity(contentOpacity)
                    // The wrapped row keeps its familiar shape, but must not eat the tap: a
                    // Toggle or Picker inside would otherwise handle the touch itself and
                    // `action` would never run. Note this is NOT `.disabled(true)` — a disabled
                    // subtree makes the whole row unhittable, which is exactly the failure
                    // FR-1100-09 forbids.
                    .allowsHitTesting(false)

                Spacer(minLength: 0)

                badge
            }
            // Tap (or focus) the whole row, not just the glyphs inside it.
            .contentShape(Rectangle())
        }
        #if os(tvOS)
        // The default tvOS button style is what draws the focus card and the lift animation, so
        // it is deliberately left in place — that is how the row announces itself as selectable
        // on a platform with no touch. Focus also un-dims the row (see `contentOpacity`), which
        // keeps it readable across a room.
        .focused($isFocused)
        #else
        // Keep the row looking like a settings row rather than tinted button text.
        .buttonStyle(.plain)
        #endif
        // One accessibility element, or the XCUITest lookup finds the inner Toggle instead of
        // the row. `.combine` folds the wrapped row's label and the badge into a single
        // readable string ("Ken Burns, Pro, locked"); the identifier and traits below then land
        // on that combined element — which is also the element that is hit-testable.
        .accessibilityElement(children: .combine)
        // Combining can carry the wrapped control's own trait up with it; a locked row behaves
        // as a button, so state the trait explicitly and drop the switch semantics.
        .accessibilityAddTraits(.isButton)
        .accessibilityRemoveTraits(.isToggle)
        .accessibilityHint("Opens the \(tier.displayName) unlock screen.")
        .accessibilityIdentifier(identifier)
    }

    private var contentOpacity: Double {
        if reduceTransparency { return 1 }
        #if os(tvOS)
        return isFocused ? 1 : Self.dimmedOpacity
        #else
        return Self.dimmedOpacity
        #endif
    }

    private var badge: some View {
        Label(tier.displayName, systemImage: "lock.fill")
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.quaternary))
            // Read as one phrase; `.combine` above appends this to the wrapped row's own label.
            .accessibilityLabel("\(tier.displayName), locked")
    }
}

extension View {

    /// Wraps this row in a ``LockedRow`` when `isLocked`, and leaves it untouched otherwise.
    ///
    /// Saves every call site an `if`/`else` that would otherwise spell the same row out twice.
    ///
    /// ```swift
    /// Toggle(isOn: $themeStore.settings.kenBurns) {
    ///     Label("Ken Burns", systemImage: "camera.viewfinder")
    /// }
    /// .lockedRow(if: !entitlements.contains(.supporter), requires: .supporter,
    ///            identifier: "settings.row.kenburns.locked") { showUnlock = true }
    /// ```
    @ViewBuilder
    public func lockedRow(
        if isLocked: Bool,
        requires tier: Entitlement,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        if isLocked {
            LockedRow(requires: tier, identifier: identifier, action: action) { self }
        } else {
            self
        }
    }
}

#Preview("Locked rows") {
    Form {
        Section("Ambience") {
            LockedRow(
                requires: .supporter,
                identifier: "settings.row.kenburns.locked",
                action: {}
            ) {
                Toggle(isOn: .constant(false)) {
                    Label("Ken Burns", systemImage: "camera.viewfinder")
                }
            }

            LockedRow(
                requires: .supporter,
                identifier: "settings.row.clock.locked",
                action: {}
            ) {
                Toggle(isOn: .constant(false)) {
                    Label("Clock", systemImage: "clock")
                }
            }
        }

        Section("Remote control") {
            LockedRow(
                requires: .supporter,
                identifier: "settings.row.broker.locked",
                action: {}
            ) {
                Label("Home Assistant", systemImage: "house")
            }
        }

        // For contrast: the same row once it is owned. The modifier passes it straight through,
        // so an unlocked row is the plain control with no badge and no interception.
        Section("Owned (passthrough)") {
            Toggle(isOn: .constant(true)) {
                Label("Ken Burns", systemImage: "camera.viewfinder")
            }
            .lockedRow(
                if: false,
                requires: .supporter,
                identifier: "settings.row.kenburns.locked",
                action: {}
            )
        }
    }
}
