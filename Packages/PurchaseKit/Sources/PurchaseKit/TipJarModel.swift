import Foundation
import Observation

/// What the tip jar is showing right now (spec 1100 US6).
///
/// Deliberately **not** `Equatable`: assertions should pin the case by pattern matching, and no
/// test should hard-code the user-facing thank-you copy. `.unavailable` carries nothing — there
/// is no products array and so no slot a cached or placeholder price could hide in.
public enum TipPhase: Sendable {

    /// Before ``TipJarModel/load()`` has fetched anything. The initial phase.
    case loading

    /// The three tips, in ``ProductCatalog/tips`` order, priced and ready to offer.
    case ready([DisplayProduct])

    /// The store could not be reached. No products, no prices, no placeholders.
    case unavailable

    /// A tip is in flight. Transient; the screen shows progress and blocks a second tap.
    case tipping(ProductID)

    /// The tip completed. A simple, generic thank-you — a tip grants no functionality, so there
    /// is nothing tier-specific to say (FR-1100-08).
    case thanked
}

/// The model behind the tip jar: offer the fixed set of tips, and turn a tap into a thank-you.
///
/// The tip jar exists to accept gratitude, nothing more. Three rules make that literal:
///
/// 1. **It cannot touch entitlements.** The model is handed a ``StoreClient`` and no
///    ``EntitlementStore`` — there is no reference through which it *could* grant, revoke, or
///    even re-resolve a tier. A tip is a consumable that grants nothing (FR-1100-08); the
///    cleanest way to guarantee that is to give the tip flow no way to reach the entitlement
///    machinery at all. It also never calls ``StoreClient/ownedTransactions()``: a tip cannot
///    change ownership, so re-resolving would be pointless work and a pointless race.
/// 2. **It only ever sells tips.** ``tip(_:)`` rejects any non-tip id outright, so an unlock can
///    never be slipped through the tip jar to bypass the paid gate.
/// 3. **Construction is inert.** No task, no store traffic, no await at init — a caller renders
///    the jar immediately and sees `.loading`. Everything happens in ``load()``. PurchaseKit
///    never auto-presents and never auto-purchases; the tip jar is reachable from settings only
///    and is never solicited (FR-1100-08).
@MainActor
@Observable
public final class TipJarModel {

    public private(set) var phase: TipPhase = .loading

    @ObservationIgnored private let client: any StoreClient

    /// The tips fetched by ``load()``, kept so a returned-from-cancel/failure flow can re-offer
    /// them, and so the thank-you screen can invite another tip, without a second round trip.
    private var offered: [DisplayProduct] = []

    /// The tips ``load()`` fetched, whatever the current phase. Empty until ``load()`` succeeds,
    /// and empty whenever the store was unreachable.
    public var offeredProducts: [DisplayProduct] { offered }

    public init(client: any StoreClient) {
        self.client = client
    }

    // MARK: - Loading

    /// Fetches exactly the three tips and offers them in catalogue order.
    ///
    /// The store makes no ordering promise, so the catalogue order is re-imposed rather than
    /// rendering whatever order came back. A store that answers with nothing sellable, or that
    /// throws, becomes ``TipPhase/unavailable`` — never an empty offer and never a placeholder
    /// price.
    public func load() async {
        phase = .loading
        offered = []

        do {
            let fetched = try await client.products(for: ProductCatalog.tips)
            let ordered = ProductCatalog.tips.compactMap { id in fetched.first { $0.id == id } }
            guard !ordered.isEmpty else {
                phase = .unavailable
                return
            }
            offered = ordered
            phase = .ready(ordered)
        } catch {
            phase = .unavailable
        }
    }

    // MARK: - Tipping

    /// Sends a tip. Never throws: every outcome is a phase the screen can render.
    ///
    /// Only a genuine, completed purchase becomes a thank-you. A cancel, a failure, or an
    /// Ask-to-Buy deferral all return to the idle offer with no thank-you — a pending tip has not
    /// been paid, so there is nothing yet to be grateful for, and a failure that thanked the user
    /// anyway would be a lie. Entitlements are untouched throughout, by construction.
    public func tip(_ id: ProductID) async {
        // Defense in depth: the UI only ever offers tips, but a non-tip id must never reach the
        // store through this path — the tip jar cannot become a side door onto the paid unlocks.
        guard ProductCatalog.tips.contains(id) else { return }

        phase = .tipping(id)

        do {
            switch try await client.purchase(id) {
            case .success:
                // A tip grants nothing, so there is deliberately no `refresh()` here: nothing to
                // resolve, nothing to persist, no ownership query at all.
                phase = .thanked

            case .pending, .cancelled:
                // Not paid (yet): back to the idle offer, unprompted and unexplained.
                phase = .ready(offered)
            }
        } catch {
            // A failed tip is not worth a nag. Quietly return to the offer.
            phase = .ready(offered)
        }
    }
}
