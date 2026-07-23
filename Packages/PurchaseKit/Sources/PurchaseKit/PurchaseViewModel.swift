import Foundation
import Observation

/// What an unlock screen is showing right now (data-model.md §PurchaseViewModel).
///
/// Deliberately **not** `Equatable`: assertions should pin the case *and its payload* by pattern
/// matching, and `.failed`'s message is a user-facing string no test should hard-code.
///
/// `.unavailable` carries nothing on purpose. There is no products array to fall back on and no
/// slot a cached or placeholder price could hide in, which is what FR-1100-16 demands — a price
/// presented as live while the store is unreachable would be the bug.
public enum PurchasePhase: Sendable {

    /// Before ``PurchaseViewModel/load()`` has resolved anything. The initial phase.
    case loading

    /// The products still worth offering this user, in ``ProductCatalog/unlocks`` order.
    case ready([DisplayProduct])

    /// The store could not be reached. No products, no prices, no placeholders (FR-1100-16).
    case unavailable

    /// A purchase is in flight. Transient; the screen shows progress and blocks a second tap.
    case purchasing(ProductID)

    /// Ask to Buy: the request was deferred for approval. Terminal for this session — approval
    /// arrives later over `StoreClient.updates` (FR-1100-15).
    case pending(ProductID)

    /// Nothing left to sell: everything this screen could offer is owned.
    case completed(EntitlementSet)

    /// The purchase attempt errored. Carries an explanation the user can read and dismiss —
    /// which is not the follow-up *prompt* FR-1100-15 forbids.
    case failed(String)
}

/// The model behind one unlock screen: which products to offer, and what a tap on them does.
///
/// Three rules shape the whole type:
///
/// 1. **Construction is inert.** No task, no store traffic, no await — a caller may render the
///    screen immediately and see `.loading`. Everything happens in ``load()``, which the view
///    calls once it is on screen. PurchaseKit never auto-presents and never auto-purchases
///    (SC-1100-02).
/// 2. **The offer derives from what is owned, not from which screen is open.** A user who owns
///    nothing is offered the single Supporter Unlock whichever locked row brought them here;
///    once it is owned there is nothing left to offer (FR-1100-04).
/// 3. **Entitlements only ever change through ``EntitlementStore``.** A completed purchase is
///    re-resolved via `refresh()` rather than inferred from the outcome, so the granted set and
///    the persisted snapshot come from the same verified query production uses (FR-1100-10).
@MainActor
@Observable
public final class PurchaseViewModel {

    /// The tier whose screen this is. Presentation only — see rule 2 above.
    public let tier: Entitlement

    public private(set) var phase: PurchasePhase = .loading

    @ObservationIgnored private let client: any StoreClient
    @ObservationIgnored private let store: EntitlementStore

    /// The products fetched by ``load()``, kept so that returning from a cancelled purchase or a
    /// restore can re-offer them without a second round trip to the store.
    private var offered: [DisplayProduct] = []

    /// The products ``load()`` fetched, whatever the current phase.
    ///
    /// Lets the screen keep the offer visible while a purchase is in flight or after a failure —
    /// phases that carry no products of their own — instead of blanking the page. Empty until
    /// ``load()`` succeeds, and empty whenever the store was unreachable.
    public var offeredProducts: [DisplayProduct] { offered }

    public init(tier: Entitlement, client: any StoreClient, store: EntitlementStore) {
        self.tier = tier
        self.client = client
        self.store = store
    }

    // MARK: - Loading

    /// Resolves what to offer and fetches exactly those products.
    ///
    /// The id list is computed *before* the query, so a user who already owns the unlock costs
    /// zero store calls. Fetching the whole catalogue and filtering afterwards would leak the
    /// excluded products' prices into memory and put the "never re-sell what is already owned"
    /// rule in the view instead of here.
    public func load() async {
        phase = .loading
        offered = []

        let ids = offerableProductIDs()
        guard !ids.isEmpty else {
            phase = .completed(store.current)
            return
        }

        do {
            let fetched = try await client.products(for: ids)
            // The store makes no ordering promise, so re-impose the catalogue order rather than
            // rendering whatever order came back.
            let ordered = ids.compactMap { id in fetched.first { $0.id == id } }
            // Nothing sellable came back: the store answered, but not with anything that can be
            // priced or bought. Presenting an empty offer would be a dead end with no explanation.
            guard !ordered.isEmpty else {
                phase = .unavailable
                return
            }
            offered = ordered
            phase = .ready(ordered)
        } catch {
            // Unreachable is not evidence of non-ownership: entitlements are left exactly as they
            // were, and no price of any kind reaches the screen.
            phase = .unavailable
        }
    }

    // MARK: - Purchasing

    /// Buys `id`. Never throws: every outcome is a phase the screen can render.
    public func buy(_ id: ProductID) async {
        phase = .purchasing(id)

        do {
            switch try await client.purchase(id) {
            case .success:
                // Ownership is re-resolved and persisted by the store; the outcome alone is never
                // treated as a grant.
                await store.refresh()
                phase = .completed(store.current)

            case .pending:
                // Terminal for this session: no retry, no polling, no optimistic completion. The
                // approval arrives over the updates stream and re-resolves entitlements there.
                phase = .pending(id)

            case .cancelled:
                // The user chose to stop. Back to the offer, unchanged and unexplained — an
                // explanation here would read as the nag FR-1100-15 forbids.
                phase = .ready(offered)
            }
        } catch {
            phase = .failed(Self.failureMessage(for: error))
        }
    }

    // MARK: - Restore (FR-1100-11)

    /// Runs the platform restore through the store and reflects whatever came back.
    ///
    /// Never throws — a failed restore is a message on this screen, not an error the view has to
    /// handle. Deliberately does **not** re-query products: the restore may well have removed the
    /// reason to offer some of them, and the ones still on sale were already fetched by ``load()``.
    public func restore() async {
        let phaseBeforeRestore = phase

        do {
            try await store.restore()
        } catch {
            phase = .failed(Self.failureMessage(for: error))
            return
        }

        let ids = offerableProductIDs()
        guard !ids.isEmpty else {
            phase = .completed(store.current)
            return
        }

        let stillOffered = offered.filter { ids.contains($0.id) }
        // A restore that recovered nothing while the store was unreachable has no products to
        // fall back on; keep the state the user was already looking at rather than inventing one.
        phase = stillOffered.isEmpty ? phaseBeforeRestore : .ready(stillOffered)
    }

    // MARK: - Offer computation (FR-1100-04)

    /// The unlocks still worth selling, in catalogue order.
    ///
    /// With a single functional unlock this reduces to "offer the Supporter Unlock unless it is
    /// already owned" (FR-1100-04). The set-based form is kept so the "never re-sell what is
    /// already owned" rule lives in exactly one place.
    private func offerableProductIDs() -> [ProductID] {
        let owned = store.current
        return ProductCatalog.unlocks.filter { id in
            !ProductCatalog.grants(id).isSubset(of: owned)
        }
    }

    // MARK: - Messages

    /// A readable reason the purchase did not complete.
    ///
    /// The store's own description is appended when it has one, because "why" is the entire point
    /// of the `.failed` case; the leading sentence guarantees the message is never empty or raw.
    /// Not localized — the app ships English-only by design (CLAUDE.md).
    private static func failureMessage(for error: any Error) -> String {
        let lead = "The purchase could not be completed."
        guard let description = (error as? any LocalizedError)?.errorDescription,
              !description.isEmpty
        else { return lead }
        return "\(lead) \(description)"
    }
}
