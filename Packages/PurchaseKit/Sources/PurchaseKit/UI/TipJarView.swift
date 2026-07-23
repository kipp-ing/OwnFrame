import SwiftUI

// Shipping UI — deliberately NOT `#if DEBUG` (unlike StubStoreClient.swift / UITestSeams.swift in
// this package). This is the screen a happy user actually reads before tipping.

/// The tip jar: a warm, optional way to support development that grants **nothing** (spec 1100
/// US6, FR-1100-08).
///
/// Everything about this screen is downstream of one rule: a tip is gratitude, not a transaction
/// for features. So it:
/// - **Grants nothing.** Its model (``TipJarModel``) is handed a ``StoreClient`` and no
///   ``EntitlementStore``; there is no path from a tip to a tier, and the copy never implies one.
/// - **Presents itself to no one.** It is a sheet body with no presentation state of its own; a
///   settings row (`settings.tipjar`) decides when it appears. The app never solicits a tip.
/// - **Invents no price.** Every price string is ``DisplayProduct/displayPrice`` verbatim as the
///   store localized it; when the store is unreachable there is no price at all.
/// - **Never says "lifetime" or "subscription."** A tip is a one-off; nothing here implies a
///   recurring charge (FR-1100-05 wording discipline applies to this screen too).
///
/// ```swift
/// .sheet(isPresented: $showTipJar) {
///     TipJarView { showTipJar = false }
/// }
/// ```
public struct TipJarView: View {

    private let onClose: () -> Void

    /// Optional on purpose: the app reads the store the same way (see ``UnlockScreenView``), and a
    /// screen that hard-unwraps it would turn a wiring mistake into a crash. The model needs only
    /// the store's ``StoreClient`` seam — never the entitlement machinery. Absent store → the
    /// unavailable notice, which is exactly what "no store to ask" means.
    @Environment(EntitlementStore.self) private var entitlements: EntitlementStore?

    /// Built in `task`, not `init`: the model needs the store's client from the environment, which
    /// is not available at initialization time. Nil until then, which is why the first pass renders
    /// progress.
    @State private var model: TipJarModel?

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                header
                intro
                content
                fineprint
            }
            .padding(Layout.padding)
            .frame(maxWidth: Layout.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        #if os(tvOS)
        // See UnlockScreenView: tvOS fullScreenCover supplies no opaque backing of its own, so the
        // full-screen tip jar has to bring its own.
        .background { Color.black.ignoresSafeArea() }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tipjar.screen")
        .task {
            // Strictly once per presentation. A re-entrant load would reset a thanked state back
            // to `loading` behind the user's back.
            guard model == nil, let entitlements else { return }
            let created = TipJarModel(client: entitlements.storeClient)
            model = created
            await created.load()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tip Jar", bundle: .module)
                    .font(.largeTitle.weight(.semibold))
                Text("If the frame has earned a coffee, this is the jar.", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            closeButton
        }
    }

    @ViewBuilder
    private var closeButton: some View {
        #if os(iOS)
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Close", bundle: .module))
        .accessibilityIdentifier("tipjar.close")
        #else
        // tvOS has no swipe-to-dismiss gesture, so the control has to be a real, focusable button.
        Button(action: onClose) { Text("Close", bundle: .module) }
            .accessibilityIdentifier("tipjar.close")
        #endif
    }

    // MARK: - Intro

    /// States the whole deal up front so no tap is a surprise: a tip changes nothing about the
    /// app. This is the anti-dark-pattern sentence, and it is load-bearing (FR-1100-08).
    private var intro: some View {
        Label {
            Text("A tip unlocks nothing and is never required — everything you have keeps working exactly the same. It is simply a thank-you if the app has been good to you.", bundle: .module)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "heart")
                .foregroundStyle(.pink)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let model {
            switch model.phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)

            case .ready(let tips):
                tipList(tips, busy: nil, using: model)

            case .tipping(let id):
                // The offer stays put underneath the system purchase sheet; only the tapped row
                // swaps its button for progress.
                tipList(model.offeredProducts, busy: id, using: model)

            case .thanked:
                thankYou(using: model)

            case .unavailable:
                unavailableNotice()
            }
        } else if entitlements == nil {
            // No store in the environment at all — nothing to price and nothing to tip with.
            unavailableNotice()
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private func tipList(
        _ tips: [DisplayProduct],
        busy: ProductID?,
        using model: TipJarModel
    ) -> some View {
        if !tips.isEmpty {
            VStack(alignment: .leading, spacing: Layout.rowSpacing) {
                ForEach(tips) { tip in
                    tipRow(tip, busy: busy, using: model)
                }
            }
        }
    }

    private func tipRow(
        _ tip: DisplayProduct,
        busy: ProductID?,
        using model: TipJarModel
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(tip.displayName)
                .font(.headline)

            Spacer(minLength: 12)

            // The store's own localized price string, verbatim. PurchaseKit formats nothing.
            Text(tip.displayPrice)
                .font(.headline)
                .monospacedDigit()
                .accessibilityIdentifier("tipjar.price.\(tip.id.tipSlug)")

            Button {
                Task { await model.tip(tip.id) }
            } label: {
                if busy == tip.id {
                    ProgressView()
                } else {
                    Text("Tip", bundle: .module)
                }
            }
            .buttonStyle(.borderedProminent)
            // Any tip in flight locks every row: one tap, one charge.
            .disabled(busy != nil)
            .accessibilityLabel(Text("Tip \(tip.displayName), \(tip.displayPrice)", bundle: .module))
            .accessibilityIdentifier("tipjar.buy.\(tip.id.tipSlug)")
        }
        .padding(Layout.rowPadding)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
    }

    // MARK: - Thank you

    /// The post-tip state (`tipjar.thanks`). It is warm, brief, and — crucially — announces no
    /// new capability, because a tip grants none. The tips stay on offer below so a second tip is
    /// one tap away, never a dead end.
    private func thankYou(using model: TipJarModel) -> some View {
        VStack(alignment: .leading, spacing: Layout.rowSpacing) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.title3)
                    .foregroundStyle(.pink)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Thank you", bundle: .module)
                        .font(.headline)
                    Text("That genuinely helps, and it means a lot. Nothing about the app changed.", bundle: .module)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(Layout.rowPadding)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tipjar.thanks")

            // Still on offer — tipping again is welcome, never demanded.
            tipList(model.offeredProducts, busy: nil, using: model)
        }
    }

    // MARK: - Notices

    /// Informative, price-free, and never a crash. There is deliberately no field here a cached or
    /// placeholder price could be rendered into.
    private func unavailableNotice() -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("The App Store is unreachable", bundle: .module)
                    .font(.headline)
                Text("Tipping needs a connection to the App Store. Everything you use keeps working, online or not.", bundle: .module)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Layout.rowPadding)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tipjar.unavailable")
    }

    // MARK: - Fine print

    /// A tip is a one-off. The word "lifetime" is banned outright (FR-1100-05), and nothing here
    /// may imply a recurring charge — a tip is not a subscription.
    private var fineprint: some View {
        Text("Each tip is a one-time thank-you. No subscription, no recurring charge, and no features attached.", bundle: .module)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Layout

    private enum Layout {
        #if os(tvOS)
        static let padding: CGFloat = 60
        static let sectionSpacing: CGFloat = 40
        static let rowSpacing: CGFloat = 20
        static let rowPadding: CGFloat = 24
        static let contentWidth: CGFloat = 1000
        #else
        static let padding: CGFloat = 24
        static let sectionSpacing: CGFloat = 28
        static let rowSpacing: CGFloat = 12
        static let rowPadding: CGFloat = 16
        static let contentWidth: CGFloat = 560
        #endif
    }
}

// MARK: - Presentation copy
//
// The short slug used in accessibility identifiers — never the raw ASC identifier, which is a
// bundle-prefixed string no test should have to spell. English only, by design (CLAUDE.md).

private extension ProductID {
    var tipSlug: String {
        switch self {
        case .tipSmall: "tip.small"
        case .tipMedium: "tip.medium"
        case .tipLarge: "tip.large"
        // Non-tips never reach a tip row, but the slug stays total rather than force-unwrapping.
        case .supporter: "supporter"
        }
    }
}

#if DEBUG
#Preview("Tip jar") {
    let defaults = UserDefaults(suiteName: "preview.tipjar") ?? .standard
    let store = EntitlementStore(
        client: StubStoreClient(),
        cache: EntitlementSnapshotCache(defaults: defaults)
    )
    return TipJarView {}
        .environment(store)
}

#Preview("Tip jar, store unreachable") {
    let defaults = UserDefaults(suiteName: "preview.tipjar.unavailable") ?? .standard
    let store = EntitlementStore(
        client: StubStoreClient(behavior: .unavailable),
        cache: EntitlementSnapshotCache(defaults: defaults)
    )
    return TipJarView {}
        .environment(store)
}
#endif
