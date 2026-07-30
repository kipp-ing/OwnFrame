import SwiftUI

// Shipping UI — deliberately NOT `#if DEBUG` (unlike StubStoreClient.swift / UITestSeams.swift
// in this package). This is the screen a paying user actually reads.

/// The single screen that answers "what do I get" and "how do I get it" for the Supporter Unlock
/// (FR-1100-09, contracts/purchasekit-api.md §Locked-row / unlock-screen UI contract).
///
/// Sections, in the contract's order: what-you-get list (with the Ken Burns motion demo slot) →
/// price + purchase button, or the unavailable notice → Restore Purchases.
///
/// Three things this view will not do:
/// - **Present itself.** It is a sheet body with no presentation state of its own; a locked row,
///   the Unlocks settings section or onboarding decides when it appears (SC-1100-02).
/// - **Buy anything on its own.** Every store call originates in a button the user pressed. The
///   one automatic call is ``PurchaseViewModel/load()``, which only reads prices.
/// - **Invent a price.** Every price string comes from ``DisplayProduct/displayPrice`` as the
///   store localized it. When the store is unreachable there is no price row at all, not a dash
///   and not a cached value (FR-1100-16).
///
/// ```swift
/// .sheet(item: $unlockTier) { tier in
///     UnlockScreenView(tier: tier) { unlockTier = nil }
/// }
/// ```
public struct UnlockScreenView: View {

    private let tier: Entitlement
    private let onClose: () -> Void

    /// Optional on purpose: the app reads the store the same way, and a screen that hard-unwraps
    /// it would turn a wiring mistake into a crash on a paying user's device. Absent store →
    /// the unavailable notice, which is exactly what "no store to ask" means.
    @Environment(EntitlementStore.self) private var entitlements: EntitlementStore?

    /// Built in `task`, not `init`: the model needs the store from the environment, which is not
    /// available at initialization time. Nil until then, which is why the first pass renders
    /// progress.
    @State private var model: PurchaseViewModel?

    public init(tier: Entitlement, onClose: @escaping () -> Void) {
        self.tier = tier
        self.onClose = onClose
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                header
                whatYouGet
                offerSection
                restoreSection
                fineprint
            }
            .padding(Layout.padding)
            .frame(maxWidth: Layout.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        #if os(tvOS)
        // tvOS `fullScreenCover` (unlike an iOS sheet) gives custom content no opaque backing, so
        // the screen underneath bleeds through. This view is presented full screen on tvOS and has
        // to stand on its own, so supply the backing here.
        .background { Color.black.ignoresSafeArea() }
        #endif
        // `.contain` rather than `.combine`: the screen is one findable container, and its
        // children (prices, buttons, notices) stay individually addressable underneath it.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("unlock.screen.\(tier.rawValue)")
        .task {
            // Strictly once per presentation. A re-entrant load would reset a completed or
            // pending purchase back to `loading` behind the user's back.
            guard model == nil, let entitlements else { return }
            let created = PurchaseViewModel(
                tier: tier,
                client: entitlements.storeClient,
                store: entitlements
            )
            model = created
            await created.load()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                // Issue #52: on a 375 pt phone the close button leaves `.largeTitle` too little
                // room and the product's own name truncated to "The Supporte…" — on the screen
                // where the purchase decision is made. German is longer still ("Die
                // Supporter-Freischaltung"), so it wraps first and only shrinks as a backstop.
                Text("The Supporter Unlock", bundle: .module)
                    .font(.largeTitle.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tier.unlockTagline)
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
        .accessibilityIdentifier("unlock.close")
        #else
        // tvOS has no swipe-to-dismiss gesture and no close affordance of its own, so the
        // control has to be a real, focusable button.
        Button(action: onClose) { Text("Close", bundle: .module) }
            .accessibilityIdentifier("unlock.close")
        #endif
    }

    // MARK: - What you get

    private var whatYouGet: some View {
        VStack(alignment: .leading, spacing: Layout.rowSpacing) {
            Text("What you get", bundle: .module)
                .font(.headline)

            ForEach(tier.benefits, id: \.title) { benefit in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(benefit.title).font(.body.weight(.medium))
                        Text(benefit.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: benefit.symbol)
                        .foregroundStyle(.tint)
                }
                .accessibilityElement(children: .combine)
            }

            // Ken Burns is the unlock's most demoable asset, so the one screen always shows it.
            kenBurnsDemo
        }
    }

    /// The unlock screen's motion sample slot — the live demo FR-1100-09 asks for where the
    /// feature is visual: the bundled cliff photo under the slideshow's slow drift-and-scale,
    /// with a miniature clock overlay (`KenBurnsDemoView`). Self-contained: it never reaches
    /// into a running slideshow and never depends on a photo source being configured.
    private var kenBurnsDemo: some View {
        KenBurnsDemoView()
            .frame(height: Layout.demoHeight)
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityLabel(Text("Live sample: Ken Burns motion with the clock overlay", bundle: .module))
            .accessibilityIdentifier("unlock.demo.kenburns")
    }

    // MARK: - Offer

    @ViewBuilder
    private var offerSection: some View {
        if let model {
            switch model.phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)

            case .ready(let products):
                offerList(products, busy: nil, using: model)

            case .purchasing(let id):
                // The offer stays on screen underneath the system purchase sheet; only the row
                // being bought swaps its button for progress.
                offerList(model.offeredProducts, busy: id, using: model)

            case .pending(let id):
                notice(
                    identifier: "unlock.pending",
                    symbol: "hourglass",
                    title: String(localized: "Waiting for approval", bundle: .module),
                    // Terminal for this session: no retry button, because the approval arrives on
                    // its own and a second tap would risk a second charge (FR-1100-15).
                    message: String(
                        localized: "\(displayName(of: id, using: model)) was sent for approval. The unlock switches on by itself once it is approved — there is nothing else to do here.",
                        bundle: .module
                    )
                )

            case .completed(let owned):
                completedNotice(owned)

            case .unavailable:
                unavailableNotice(retry: model)

            case .failed(let message):
                VStack(alignment: .leading, spacing: Layout.rowSpacing) {
                    notice(
                        identifier: "unlock.failed",
                        symbol: "exclamationmark.triangle",
                        title: String(localized: "Purchase not completed", bundle: .module),
                        message: message
                    )
                    // Back on the offer, with no prompt and nothing re-attempted for the user.
                    offerList(model.offeredProducts, busy: nil, using: model)
                }
            }
        } else if entitlements == nil {
            // No store in the environment at all — nothing to price and nothing to buy.
            unavailableNotice(retry: nil)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private func offerList(
        _ products: [DisplayProduct],
        busy: ProductID?,
        using model: PurchaseViewModel
    ) -> some View {
        if !products.isEmpty {
            VStack(alignment: .leading, spacing: Layout.rowSpacing) {
                ForEach(products) { product in
                    offerRow(product, busy: busy, using: model)
                }
            }
        }
    }

    private func offerRow(
        _ product: DisplayProduct,
        busy: ProductID?,
        using model: PurchaseViewModel
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName)
                    .font(.headline)
                if let blurb = product.id.offerBlurb {
                    Text(blurb)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            // The store's own localized price string, verbatim. PurchaseKit formats nothing and
            // substitutes nothing.
            Text(product.displayPrice)
                .font(.headline)
                .monospacedDigit()
                .accessibilityIdentifier("unlock.price.\(product.id.uiSlug)")

            Button {
                Task { await model.buy(product.id) }
            } label: {
                if busy == product.id {
                    ProgressView()
                } else {
                    Text("Unlock", bundle: .module)
                }
            }
            .buttonStyle(.borderedProminent)
            // Any purchase in flight locks every row: one tap, one charge.
            .disabled(busy != nil)
            .accessibilityLabel(Text("Unlock \(product.displayName), \(product.displayPrice)", bundle: .module))
            .accessibilityIdentifier("unlock.buy.\(product.id.uiSlug)")
        }
        .padding(Layout.rowPadding)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
    }

    // MARK: - Notices

    /// FR-1100-16: informative, price-free, and never a crash. There is deliberately no field
    /// here a cached or placeholder price could be rendered into.
    private func unavailableNotice(retry model: PurchaseViewModel?) -> some View {
        VStack(alignment: .leading, spacing: Layout.rowSpacing) {
            notice(
                identifier: "unlock.unavailable",
                symbol: "wifi.exclamationmark",
                title: String(localized: "The App Store is unreachable", bundle: .module),
                message: String(
                    localized: "Prices and purchases need a connection to the App Store. Everything you already own keeps working, online or not.",
                    bundle: .module
                )
            )

            if let model {
                Button {
                    Task { await model.load() }
                } label: {
                    Text("Try Again", bundle: .module)
                }
                .accessibilityIdentifier("unlock.retry")
            }
        }
    }

    private func completedNotice(_ owned: EntitlementSet) -> some View {
        VStack(alignment: .leading, spacing: Layout.rowSpacing) {
            notice(
                identifier: "unlock.completed",
                symbol: "checkmark.seal",
                title: owned.isEmpty
                    ? String(localized: "Thank you", bundle: .module)
                    : String(localized: "Unlocked", bundle: .module),
                message: owned.isEmpty
                    ? String(localized: "Your purchase went through. It may take a moment to appear.", bundle: .module)
                    : String(localized: "\(ownedList(owned)) — yours, on every device signed in to your Apple Account.", bundle: .module)
            )

            Button(action: onClose) { Text("Done", bundle: .module) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("unlock.done")
        }
    }

    private func notice(
        identifier: String,
        symbol: String,
        title: String,
        message: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(message)
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
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Restore (FR-1100-11)

    /// Present on every unlock screen, in every phase — including `unavailable`, where a user who
    /// already paid needs it most.
    private var restoreSection: some View {
        Button {
            guard let model else { return }
            Task { await model.restore() }
        } label: {
            Text("Restore Purchases", bundle: .module)
        }
        .disabled(model == nil)
        .accessibilityHint(Text("Recovers unlocks you already bought with this Apple Account.", bundle: .module))
        .accessibilityIdentifier("unlock.restore")
    }

    // MARK: - Fine print

    /// FR-1100-05: the sanctioned wording is "one-time purchase". The word "lifetime" is banned
    /// outright, and nothing here may imply a recurring charge or an expiring unlock.
    private var fineprint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Each unlock is a one-time purchase. No subscription, no recurring charge.", bundle: .module)
            Text("Shared with your family and included on iPad, iPhone, and Apple TV.", bundle: .module)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Copy helpers

    private func displayName(of id: ProductID, using model: PurchaseViewModel) -> String {
        model.offeredProducts.first { $0.id == id }?.displayName
            ?? String(localized: "Your purchase", bundle: .module)
    }

    private func ownedList(_ owned: EntitlementSet) -> String {
        Entitlement.allCases
            .filter(owned.contains)
            .map(\.displayName)
            .formatted(.list(type: .and))
    }

    // MARK: - Layout

    private enum Layout {
        #if os(tvOS)
        static let padding: CGFloat = 60
        static let sectionSpacing: CGFloat = 40
        static let rowSpacing: CGFloat = 20
        static let rowPadding: CGFloat = 24
        static let contentWidth: CGFloat = 1000
        static let demoHeight: CGFloat = 260
        #else
        static let padding: CGFloat = 24
        static let sectionSpacing: CGFloat = 28
        static let rowSpacing: CGFloat = 12
        static let rowPadding: CGFloat = 16
        static let contentWidth: CGFloat = 560
        static let demoHeight: CGFloat = 160
        #endif
    }
}

// MARK: - Presentation copy
//
// Marketing wording for the unlock and its product lives beside the screen that says it, not in
// the model: an `Entitlement` is a capability, and a `ProductID` is an App Store Connect identifier.
// The wording itself is localized against the package catalog (`bundle: .module`) — a package's
// strings do not live in the app bundle; what sits here is the *choice* of wording, not its text.

private struct UnlockBenefit {
    let title: String
    let detail: String
    let symbol: String
}

private extension Entitlement {

    var unlockTagline: String {
        switch self {
        case .supporter:
            String(localized: "The ambience touches and full Home Assistant control, in one purchase.",
                   bundle: .module)
        }
    }

    var benefits: [UnlockBenefit] {
        switch self {
        case .supporter:
            [
                UnlockBenefit(
                    title: String(localized: "Ken Burns motion", bundle: .module),
                    detail: String(localized: "Photos drift and scale slowly instead of sitting still.", bundle: .module),
                    symbol: "camera.viewfinder"
                ),
                UnlockBenefit(
                    title: String(localized: "Clock overlay", bundle: .module),
                    detail: String(localized: "A quiet clock on the frame, in your 12- or 24-hour format.", bundle: .module),
                    symbol: "clock"
                ),
                UnlockBenefit(
                    title: String(localized: "Home Assistant control", bundle: .module),
                    detail: String(localized: "Brightness, album, and pause or play over MQTT, with discovery and availability built in.", bundle: .module),
                    symbol: "house"
                ),
                UnlockBenefit(
                    title: String(localized: "Shortcuts and Siri", bundle: .module),
                    detail: String(localized: "App Intents so your automations and your voice can drive the frame.", bundle: .module),
                    symbol: "sparkles"
                ),
            ]
        }
    }
}

private extension ProductID {

    /// The short slug used in accessibility identifiers (contracts/uitest-seams.md) — never the
    /// raw ASC identifier, which is a bundle-prefixed string no test should have to spell.
    var uiSlug: String {
        switch self {
        case .supporter: "supporter"
        case .tipSmall: "tip.small"
        case .tipMedium: "tip.medium"
        case .tipLarge: "tip.large"
        }
    }

    /// One line of context under a product's name. The name and price come from the store; this
    /// says what the purchase covers.
    var offerBlurb: String? {
        switch self {
        case .supporter:
            String(localized: "Ken Burns, the clock overlay, and full Home Assistant control.", bundle: .module)
        case .tipSmall, .tipMedium, .tipLarge: nil
        }
    }
}

#if DEBUG
#Preview("Supporter unlock") {
    let defaults = UserDefaults(suiteName: "preview.unlock.supporter") ?? .standard
    let store = EntitlementStore(
        client: StubStoreClient(),
        cache: EntitlementSnapshotCache(defaults: defaults)
    )
    return UnlockScreenView(tier: .supporter) {}
        .environment(store)
}

#Preview("Supporter unlock, store unreachable") {
    let defaults = UserDefaults(suiteName: "preview.unlock.supporter.unavailable") ?? .standard
    let store = EntitlementStore(
        client: StubStoreClient(behavior: .unavailable),
        cache: EntitlementSnapshotCache(defaults: defaults)
    )
    return UnlockScreenView(tier: .supporter) {}
        .environment(store)
}
#endif
