//
//  StoreKitClientTests.swift
//  OwnFrameTests
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
//  Two setup traps that between them made this class serve zero products and skip itself
//  (2026-07-21). Both are in the test, not the runner — the earlier "the StoreKit test daemon
//  isn't active under headless xcodebuild" conclusion was wrong, and these cases run for real
//  under plain `xcodebuild test` with no IDE and no device:
//
//  1. `SKTestSession(configurationFileNamed:)` resolves the name against `Bundle.main`. In an
//     app-hosted unit test `Bundle.main` is the HOST APP bundle, which does not carry the
//     fixture — `Configuration.storekit` is a resource of the TEST bundle. The lookup fails
//     *silently*: the initializer does not throw, it hands back a session backed by no
//     configuration, which presents exactly as "loads fine, serves 0 products". Initialize from
//     the explicit test-bundle URL (`contentsOf:`) so bundle-search semantics can't bite.
//  2. `resetToDefaultState()` restores session settings to their defaults, so it turns
//     `disableDialogs` back OFF. Setting that flag before the reset leaves purchase dialogs on,
//     and the Ask-to-Buy cases then block forever waiting for a tap no headless run will make.
//     Configure the session AFTER resetting it.
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
        // target. Creating the session activates that config as the process's StoreKit test
        // environment, which is what makes `Product.products` / `Transaction.currentEntitlements`
        // resolve against it. The scheme carries no StoreKit config, so the code-created session
        // is the single authority and the two can't disagree.
        //
        // Resolve the fixture through the TEST bundle explicitly — see trap 1 in the file header.
        let configURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "Configuration", withExtension: "storekit"),
            "Configuration.storekit is missing from the test bundle — it is picked up via the "
            + "target's synchronized folder, so check it still ships as a test resource."
        )
        session = try SKTestSession(contentsOf: configURL)

        // Configure AFTER resetting — see trap 2 in the file header.
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true        // no confirmation sheets — purchases auto-complete

        // Fail loudly, never skip: an empty store here means the fixture stopped reaching the
        // session (a renamed/removed resource, a broken config), and every case below would fail
        // for that reason rather than an adapter one. This used to be an `XCTSkipIf` on the
        // theory that headless runs simply can't serve products; that theory was wrong, so a
        // silent skip would now only hide a real regression.
        let available = try await Product.products(for: ProductCatalog.unlocks.map(\.rawValue))
        XCTAssertEqual(
            available.count, ProductCatalog.unlocks.count,
            "SKTestSession served \(available.count) of \(ProductCatalog.unlocks.count) unlocks — "
            + "the fixture is not reaching the session."
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

        let outcome = try await client.purchase(.supporter)
        XCTAssertEqual(outcome, .success)

        let owned = try await activelyOwns(client, .supporter)
        XCTAssertTrue(owned, "a completed purchase must surface in ownedTransactions()")
    }

    // MARK: - 2. Restore is a no-throw platform sync that preserves ownership

    func test_restore_doesNotThrow_andPreservesOwnership() async throws {
        let client = StoreKitClient()
        _ = try await client.purchase(.supporter)
        let ownedBefore = try await activelyOwns(client, .supporter)
        XCTAssertTrue(ownedBefore)

        // restore() is `AppStore.sync()`; the store model re-queries afterwards. Here we only
        // assert the adapter half: sync completes without throwing and ownership is intact.
        try await client.restore()

        let ownedAfter = try await activelyOwns(client, .supporter)
        XCTAssertTrue(ownedAfter, "restore must not lose an already-owned unlock")
    }

    // MARK: - 3. A refunded transaction drops out of ownership (FR-1100-12)
    // @covers FR-1100-12

    func test_refund_excludesProductFromOwned() async throws {
        let client = StoreKitClient()
        _ = try await client.purchase(.supporter)
        let ownedBefore = try await activelyOwns(client, .supporter)
        XCTAssertTrue(ownedBefore)

        let identifier = try XCTUnwrap(
            session.allTransactions().first { $0.productIdentifier == ProductID.supporter.rawValue }?.identifier,
            "the purchase should have produced a transaction to refund"
        )
        try session.refundTransaction(identifier: identifier)

        let refundedOut = try await waitUntil { try await self.activelyOwns(client, .supporter) == false }
        XCTAssertTrue(refundedOut, "a refunded unlock must no longer be actively owned")
    }

    // MARK: - 4. Ask to Buy: deferral then approval (FR-1100-15)
    // @covers FR-1100-15

    func test_askToBuy_deferral_returnsPending_thenApprovalBecomesOwned() async throws {
        session.askToBuyEnabled = true
        let client = StoreKitClient()

        let outcome = try await client.purchase(.supporter)
        XCTAssertEqual(outcome, .pending, "an Ask-to-Buy request is a deferral, not a success")
        let ownedWhilePending = try await activelyOwns(client, .supporter)
        XCTAssertFalse(ownedWhilePending, "nothing is owned while approval is still pending")

        let pending = try XCTUnwrap(
            session.allTransactions().first { $0.productIdentifier == ProductID.supporter.rawValue }?.identifier
        )
        try session.approveAskToBuyTransaction(identifier: pending)

        let ownedAfterApproval = try await waitUntil { try await self.activelyOwns(client, .supporter) }
        XCTAssertTrue(ownedAfterApproval, "once approved, the entitlement must arrive")
    }

    // MARK: - 5. The updates stream fires when ownership changes out of band

    func test_updatesStream_yieldsWhenAskToBuyApproved() async throws {
        session.askToBuyEnabled = true
        let client = StoreKitClient()
        _ = try await client.purchase(.supporter)   // -> .pending, no ownership yet

        // Start listening BEFORE approving, exactly as the app does at launch.
        async let firstUpdate: Bool = Self.awaitFirstUpdate(from: client)
        try await Task.sleep(nanoseconds: 300_000_000)   // let the consumer attach

        let pending = try XCTUnwrap(
            session.allTransactions().first { $0.productIdentifier == ProductID.supporter.rawValue }?.identifier
        )
        try session.approveAskToBuyTransaction(identifier: pending)

        let arrived = await firstUpdate
        XCTAssertTrue(arrived, "an out-of-band approval must surface as a reason to re-query")
    }

    // MARK: - 6. An interrupted purchase is owned on the next launch (FR-1100-15)

    // @covers FR-1100-15
    func test_interruptedPurchase_isOwnedOnNextLaunch() async throws {
        // Simulate a purchase that completed at the store but whose app-side finish never ran
        // (crash / kill mid-flight): buy directly and DO NOT finish the transaction.
        let fetched = try await Product.products(for: [ProductID.supporter.rawValue]).first
        let product = try XCTUnwrap(fetched)
        let result = try await product.purchase()
        guard case .success(let verification) = result,
              case .verified = verification else {
            return XCTFail("the direct purchase should verify and succeed")
        }
        // Deliberately no `transaction.finish()` here — this is the interruption.

        // "Next launch": a brand-new adapter reads the durable entitlement from the store.
        let relaunched = StoreKitClient()
        let owned = try await activelyOwns(relaunched, .supporter)
        XCTAssertTrue(owned, "an interrupted purchase must still resolve as owned on the next launch")
    }

    // MARK: - 7. Only verified unlocks surface — never tips, never unverified

    // @covers FR-1100-08
    func test_ownedTransactions_surfacesUnlocksOnly_neverTips() async throws {
        let client = StoreKitClient()

        let tip = try await client.purchase(.tipSmall)
        XCTAssertEqual(tip, .success, "a tip completes like any other purchase (FR-1100-08)")

        _ = try await client.purchase(.supporter)

        let owned = try await client.ownedTransactions()
        XCTAssertTrue(
            owned.contains { $0.productID == ProductID.supporter.rawValue },
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
