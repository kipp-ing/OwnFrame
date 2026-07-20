import Foundation
@testable import PurchaseKit

// T010 (test half) — a scripted `StoreClient` double for the host suite.
//
// Conforms to the protocol exactly as written in contracts/purchasekit-api.md. Every method
// answers from a per-method queue of scripted results (empty queue → the configured default),
// records its call in an ordered log, and can be made to throw. The `updates` stream is driven
// from the test via `emitUpdate()`.
//
// Sendable-correctness: all mutable state lives behind one `NSLock`, so the type is safely
// `@unchecked Sendable` under Swift 6 strict concurrency, and tests can inspect the call log
// synchronously (no `await`) — which is exactly what the "client is never awaited at init"
// assertion needs.
final class StoreClientFake: StoreClient, @unchecked Sendable {

    // MARK: - Failure injection

    enum Failure: Error, Equatable {
        case productsUnavailable
        case purchaseFailed
        case restoreFailed
        case ownershipUnknown
    }

    // MARK: - Call recording

    enum Call: Equatable, Sendable {
        case products([ProductID])
        case purchase(ProductID)
        case restore
        case ownedTransactions
    }

    // MARK: - State (all guarded by `lock`)

    private let lock = NSLock()

    private var _callLog: [Call] = []
    private var _productsQueue: [Result<[DisplayProduct], any Error>] = []
    private var _purchaseQueue: [Result<PurchaseOutcome, any Error>] = []
    private var _restoreQueue: [Result<Void, any Error>] = []
    private var _ownedQueue: [Result<[OwnedTransaction], any Error>] = []

    /// Answer used once a method's queue has run dry.
    private var _defaultProducts: Result<[DisplayProduct], any Error> = .success([])
    private var _defaultPurchase: Result<PurchaseOutcome, any Error> = .success(.success)
    private var _defaultRestore: Result<Void, any Error> = .success(())
    private var _defaultOwned: Result<[OwnedTransaction], any Error> = .success([])

    // MARK: - Updates stream

    let updates: AsyncStream<Void>
    private let updatesContinuation: AsyncStream<Void>.Continuation

    init() {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .unbounded)
        updates = stream
        updatesContinuation = continuation
    }

    /// Pushes one ownership-changed event into `updates` (new purchase elsewhere, Ask-to-Buy
    /// approval, revocation). Elements are the *reason* to re-query, never the payload.
    func emitUpdate() {
        updatesContinuation.yield(())
    }

    /// Ends the stream so a `for await` loop can terminate.
    func finishUpdates() {
        updatesContinuation.finish()
    }

    // MARK: - Scripting: success

    func enqueueProducts(_ products: [DisplayProduct]) {
        withLock { $0._productsQueue.append(.success(products)) }
    }

    func enqueuePurchase(_ outcome: PurchaseOutcome) {
        withLock { $0._purchaseQueue.append(.success(outcome)) }
    }

    func enqueueRestoreSuccess() {
        withLock { $0._restoreQueue.append(.success(())) }
    }

    func enqueueOwnedTransactions(_ transactions: [OwnedTransaction]) {
        withLock { $0._ownedQueue.append(.success(transactions)) }
    }

    /// Convenience: script the next ownership answer as a set of non-revoked products.
    func enqueueOwned(_ ids: ProductID...) {
        enqueueOwnedTransactions(ids.map { OwnedTransaction(productID: $0.rawValue, isRevoked: false) })
    }

    // MARK: - Scripting: failure

    func failNextProducts(_ error: any Error = Failure.productsUnavailable) {
        withLock { $0._productsQueue.append(.failure(error)) }
    }

    func failNextPurchase(_ error: any Error = Failure.purchaseFailed) {
        withLock { $0._purchaseQueue.append(.failure(error)) }
    }

    func failNextRestore(_ error: any Error = Failure.restoreFailed) {
        withLock { $0._restoreQueue.append(.failure(error)) }
    }

    func failNextOwnedTransactions(_ error: any Error = Failure.ownershipUnknown) {
        withLock { $0._ownedQueue.append(.failure(error)) }
    }

    // MARK: - Scripting: standing defaults (used when a queue is empty)

    func setDefaultProducts(_ result: Result<[DisplayProduct], any Error>) {
        withLock { $0._defaultProducts = result }
    }

    func setDefaultPurchase(_ result: Result<PurchaseOutcome, any Error>) {
        withLock { $0._defaultPurchase = result }
    }

    func setDefaultRestore(_ result: Result<Void, any Error>) {
        withLock { $0._defaultRestore = result }
    }

    func setDefaultOwnedTransactions(_ result: Result<[OwnedTransaction], any Error>) {
        withLock { $0._defaultOwned = result }
    }

    /// Every ownership query from here on reports "unknown" (offline / store unreachable).
    func alwaysFailOwnedTransactions(_ error: any Error = Failure.ownershipUnknown) {
        setDefaultOwnedTransactions(.failure(error))
    }

    // MARK: - Inspection

    var callLog: [Call] { withLock { $0._callLog } }

    var totalCallCount: Int { callLog.count }

    var productsCallCount: Int {
        callLog.reduce(into: 0) { count, call in
            if case .products = call { count += 1 }
        }
    }

    var purchaseCallCount: Int {
        callLog.reduce(into: 0) { count, call in
            if case .purchase = call { count += 1 }
        }
    }

    var restoreCallCount: Int {
        callLog.reduce(into: 0) { count, call in
            if case .restore = call { count += 1 }
        }
    }

    var ownedTransactionsCallCount: Int {
        callLog.reduce(into: 0) { count, call in
            if case .ownedTransactions = call { count += 1 }
        }
    }

    /// The product ids passed to `purchase(_:)`, in order.
    var purchasedProductIDs: [ProductID] {
        callLog.reduce(into: [ProductID]()) { ids, call in
            if case .purchase(let id) = call { ids.append(id) }
        }
    }

    /// The id lists passed to `products(for:)`, in order.
    var requestedProductIDs: [[ProductID]] {
        callLog.reduce(into: [[ProductID]]()) { lists, call in
            if case .products(let ids) = call { lists.append(ids) }
        }
    }

    func resetCallLog() {
        withLock { $0._callLog = [] }
    }

    // MARK: - StoreClient

    func products(for ids: [ProductID]) async throws -> [DisplayProduct] {
        let result: Result<[DisplayProduct], any Error> = withLock { fake in
            fake._callLog.append(.products(ids))
            guard !fake._productsQueue.isEmpty else { return fake._defaultProducts }
            return fake._productsQueue.removeFirst()
        }
        return try result.get()
    }

    func purchase(_ id: ProductID) async throws -> PurchaseOutcome {
        let result: Result<PurchaseOutcome, any Error> = withLock { fake in
            fake._callLog.append(.purchase(id))
            guard !fake._purchaseQueue.isEmpty else { return fake._defaultPurchase }
            return fake._purchaseQueue.removeFirst()
        }
        return try result.get()
    }

    func restore() async throws {
        let result: Result<Void, any Error> = withLock { fake in
            fake._callLog.append(.restore)
            guard !fake._restoreQueue.isEmpty else { return fake._defaultRestore }
            return fake._restoreQueue.removeFirst()
        }
        try result.get()
    }

    func ownedTransactions() async throws -> [OwnedTransaction] {
        let result: Result<[OwnedTransaction], any Error> = withLock { fake in
            fake._callLog.append(.ownedTransactions)
            guard !fake._ownedQueue.isEmpty else { return fake._defaultOwned }
            return fake._ownedQueue.removeFirst()
        }
        return try result.get()
    }

    // MARK: - Locking

    private func withLock<T>(_ body: (StoreClientFake) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(self)
    }
}
