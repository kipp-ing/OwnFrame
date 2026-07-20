//
//  StoreKitClientTests.swift
//  Immich SlideshowTests
//
//  1100 (T030) — the real StoreKit 2 adapter, exercised end to end against a live
//  `SKTestSession` loaded from `Configuration.storekit` (T003, a resource of this test target).
//
//  Why XCTest and not Swift Testing (the house default): StoreKit's transaction queue is
//  process-global — `Transaction.currentEntitlements` and `Transaction.updates` are shared
//  singletons. Swift Testing runs `@Test`s in parallel by default, which would race every
//  case against every other on that one queue. XCTest runs a class's methods serially, which
//  is exactly the isolation this needs (constitution I "XCTest only where needed"). Each test
//  additionally resets the session so no owned/refunded state leaks between cases.
//
//  These cases cannot run on the host (`swift test`): `SKTestSession` needs the simulator.
//  Run the WHOLE class via XcodeBuildMCP `test_sim` — a single `-only-testing` method reports
//  a false green (memory: xcodebuildmcp-single-test-false-green).
//
//  Environment skip-guard: `SKTestSession` only serves products where the simulator's StoreKit
//  test daemon is actually activated for the run. Under this project's headless `xcodebuild test`
//  path (XcodeBuildMCP) that activation does not happen: the session loads but serves *zero*
//  products — reproduced across init styles (`configurationFileNamed:`, `contentsOf:`, a scheme
//  `StoreKitConfigurationFileReference`) and runtimes (iOS 18.6 and 26.x), so it is the runner,
//  not the runtime. Rather than let every case go red for that environmental reason, `setUp`
//  probes the store once and `throw`s `XCTSkip` when it comes back empty, so the suite reports an
//  honest **skip** — never a false pass, never a false red. These cases DO run for real when the
//  suite is executed from the Xcode IDE test runner or on a device (T042), where the daemon is
//  live. Until then the adapter's semantics are held by review + the pure PurchaseKit host tests
//  above the seam.
//

import StoreKit
import StoreKitTest
import XCTest

@testable import PurchaseKit

final class StoreKitClientTests: XCTestCase {

    private var session: SKTestSession!

    override func setUp() async throws {
        try await super.setUp()
        // A fresh StoreKit environment per test, from the fixture bundled into THIS (test)
        // target. `configurationFileNamed:` activates that config as the process's StoreKit test
        // environment, which is what makes `Product.products` / `Transaction.currentEntitlements`
        // resolve against it — the canonical pattern for a programmatic StoreKit unit test. (The
        // scheme carries no StoreKit config: the code-created session is the single authority, so
        // the two can't disagree.) `Configuration.storekit` is a resource of the test bundle.
        session = try SKTestSession(configurationFileNamed: "Configuration")
        session.disableDialogs = true        // no confirmation sheets — purchases auto-complete
        session.resetToDefaultState()
        session.clearTransactions()

        // Skip-guard (see file header): when the StoreKit test daemon isn't activated for the run
        // — as under headless `xcodebuild test` here — the session serves no products and every
        // case below would fail for that environmental reason, not an adapter one. Report an honest
        // skip instead. Run from the Xcode IDE test runner or on a device and the six fixture
        // products load and the whole class runs for real.
        let available = try await Product.products(for: ProductCatalog.unlocks.map(\.rawValue))
        try XCTSkipIf(
            available.isEmpty,
            "SKTestSession served 0 products — StoreKit test daemon not active under headless "
            + "xcodebuild (reproduced on iOS 18.6 + 26.x). Adapter held by review; these cases run "
            + "for real from the Xcode IDE runner or on device (T042)."
        )
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        session = nil
        try await super.tearDown()
    }

    // MARK: - 1. A completed purchase becomes owned

    func test_purchase_success_makesProductOwned() async throws {
        let client = StoreKitClient()

        let outcome = try await client.purchase(.pro)
        XCTAssertEqual(outcome, .success)

        let owned = try await activelyOwns(client, .pro)
        XCTAssertTrue(owned, "a completed purchase must surface in ownedTransactions()")
    }

    // MARK: - 2. Restore is a no-throw platform sync that preserves ownership

    func test_restore_doesNotThrow_andPreservesOwnership() async throws {
        let client = StoreKitClient()
        _ = try await client.purchase(.automation)
        let ownedBefore = try await activelyOwns(client, .automation)
        XCTAssertTrue(ownedBefore)

        // restore() is `AppStore.sync()`; the store model re-queries afterwards. Here we only
        // assert the adapter half: sync completes without throwing and ownership is intact.
        try await client.restore()

        let ownedAfter = try await activelyOwns(client, .automation)
        XCTAssertTrue(ownedAfter, "restore must not lose an already-owned unlock")
    }

    // MARK: - 3. A refunded transaction drops out of ownership (FR-1100-12)

    func test_refund_excludesProductFromOwned() async throws {
        let client = StoreKitClient()
        _ = try await client.purchase(.pro)
        let ownedBefore = try await activelyOwns(client, .pro)
        XCTAssertTrue(ownedBefore)

        let identifier = try XCTUnwrap(
            session.allTransactions().first { $0.productIdentifier == ProductID.pro.rawValue }?.identifier,
            "the purchase should have produced a transaction to refund"
        )
        try session.refundTransaction(identifier: identifier)

        let refundedOut = try await waitUntil { try await self.activelyOwns(client, .pro) == false }
        XCTAssertTrue(refundedOut, "a refunded unlock must no longer be actively owned")
    }

    // MARK: - 4. Ask to Buy: deferral then approval (FR-1100-15)

    func test_askToBuy_deferral_returnsPending_thenApprovalBecomesOwned() async throws {
        session.askToBuyEnabled = true
        let client = StoreKitClient()

        let outcome = try await client.purchase(.pro)
        XCTAssertEqual(outcome, .pending, "an Ask-to-Buy request is a deferral, not a success")
        let ownedWhilePending = try await activelyOwns(client, .pro)
        XCTAssertFalse(ownedWhilePending, "nothing is owned while approval is still pending")

        let pending = try XCTUnwrap(
            session.allTransactions().first { $0.productIdentifier == ProductID.pro.rawValue }?.identifier
        )
        try session.approveAskToBuyTransaction(identifier: pending)

        let ownedAfterApproval = try await waitUntil { try await self.activelyOwns(client, .pro) }
        XCTAssertTrue(ownedAfterApproval, "once approved, the entitlement must arrive")
    }

    // MARK: - 5. The updates stream fires when ownership changes out of band

    func test_updatesStream_yieldsWhenAskToBuyApproved() async throws {
        session.askToBuyEnabled = true
        let client = StoreKitClient()
        _ = try await client.purchase(.pro)   // -> .pending, no ownership yet

        // Start listening BEFORE approving, exactly as the app does at launch.
        async let firstUpdate: Bool = Self.awaitFirstUpdate(from: client)
        try await Task.sleep(nanoseconds: 300_000_000)   // let the consumer attach

        let pending = try XCTUnwrap(
            session.allTransactions().first { $0.productIdentifier == ProductID.pro.rawValue }?.identifier
        )
        try session.approveAskToBuyTransaction(identifier: pending)

        let arrived = await firstUpdate
        XCTAssertTrue(arrived, "an out-of-band approval must surface as a reason to re-query")
    }

    // MARK: - 6. An interrupted purchase is owned on the next launch (FR-1100-15)

    func test_interruptedPurchase_isOwnedOnNextLaunch() async throws {
        // Simulate a purchase that completed at the store but whose app-side finish never ran
        // (crash / kill mid-flight): buy directly and DO NOT finish the transaction.
        let fetched = try await Product.products(for: [ProductID.pro.rawValue]).first
        let product = try XCTUnwrap(fetched)
        let result = try await product.purchase()
        guard case .success(let verification) = result,
              case .verified = verification else {
            return XCTFail("the direct purchase should verify and succeed")
        }
        // Deliberately no `transaction.finish()` here — this is the interruption.

        // "Next launch": a brand-new adapter reads the durable entitlement from the store.
        let relaunched = StoreKitClient()
        let owned = try await activelyOwns(relaunched, .pro)
        XCTAssertTrue(owned, "an interrupted purchase must still resolve as owned on the next launch")
    }

    // MARK: - 7. Only verified unlocks surface — never tips, never unverified

    func test_ownedTransactions_surfacesUnlocksOnly_neverTips() async throws {
        let client = StoreKitClient()

        let tip = try await client.purchase(.tipSmall)
        XCTAssertEqual(tip, .success, "a tip completes like any other purchase (FR-1100-08)")

        _ = try await client.purchase(.pro)

        let owned = try await client.ownedTransactions()
        XCTAssertTrue(
            owned.contains { $0.productID == ProductID.pro.rawValue },
            "the unlock is owned"
        )
        XCTAssertFalse(
            owned.contains { $0.productID == ProductID.tipSmall.rawValue },
            "a consumable tip completes but must never appear in ownership (FR-1100-08)"
        )
        // The adapter also drops JWS-`.unverified` transactions before building this list.
        // `SKTestSession` cannot synthesise an unverified transaction (its store always signs
        // valid ones), so that branch is enforced by construction (`guard case .verified`) and
        // covered by review rather than a runtime case here.
    }

    // MARK: - Helpers

    /// Whether `client` currently reports `id` as an active (non-revoked) entitlement.
    private func activelyOwns(_ client: StoreKitClient, _ id: ProductID) async throws -> Bool {
        let owned = try await client.ownedTransactions()
        return owned.contains { $0.productID == id.rawValue && !$0.isRevoked }
    }

    /// Polls `condition` until it is true or the budget runs out. StoreKit propagates some
    /// ownership changes (Ask-to-Buy approval, refund) asynchronously, so a single read can
    /// race ahead of the queue; polling is the deterministic way to wait for steady state.
    private func waitUntil(
        _ condition: () async throws -> Bool,
        tries: Int = 30,
        delayMs: UInt64 = 150
    ) async rethrows -> Bool {
        for _ in 0..<tries {
            if try await condition() { return true }
            try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
        }
        return try await condition()
    }

    /// Returns true if `client.updates` yields at least once before the timeout.
    ///
    /// `static` on purpose: an instance method would capture `self` (the non-`Sendable`
    /// `XCTestCase`) into the `async let` child task and trip Swift 6's data-race check.
    private static func awaitFirstUpdate(from client: StoreKitClient, timeoutMs: UInt64 = 5000) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in client.updates { return true }
                return false
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutMs * 1_000_000)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}
