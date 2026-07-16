import Foundation
import PhotoSourceKit
import PhotoSourceTestSupport
import SlideshowKit
import ThemeKit
import ThemeKitTestSupport

/// A deterministic settings store for the engine tests that assert album-order
/// behavior. Sequential order keeps `start()`/`advance()` walking the album in a
/// predictable sequence; tests that exercise shuffle inject their own store.
@MainActor
func sequentialThemeStore(duration: Duration = .seconds(15)) -> InMemoryThemeStore {
    InMemoryThemeStore(settings: ThemeSettings(order: .sequential, duration: duration))
}

final class ManualTicker: SlideshowTicker, @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, any Error>] = []
    private var waiterObservers: [CheckedContinuation<Void, Never>] = []
    private var consumedObservers: [CheckedContinuation<Void, Never>] = []
    private var consumedTickCount = 0
    private var recordedDurations: [Duration] = []

    /// The duration the engine requested for the most recent wait. The live-duration
    /// ticker records this each cycle so tests can assert the interval re-arms when
    /// the store's duration changes mid-show (008, review R1).
    var lastRequestedDuration: Duration? {
        lock.withLock { recordedDurations.last }
    }

    var requestedDurations: [Duration] {
        lock.withLock { recordedDurations }
    }

    func waitForNextTick(duration: Duration) async throws {
        lock.withLock { recordedDurations.append(duration) }

        if Task.isCancelled {
            throw CancellationError()
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    waiters.append(continuation)
                    waiterObservers.forEach { $0.resume() }
                    waiterObservers.removeAll()
                }
            }
        } onCancel: {
            lock.withLock {
                guard !waiters.isEmpty else { return }
                let waiter = waiters.removeFirst()
                waiter.resume(throwing: CancellationError())
            }
        }

        lock.withLock {
            consumedTickCount += 1
            consumedObservers.forEach { $0.resume() }
            consumedObservers.removeAll()
        }
    }

    func tick() {
        let waiter = lock.withLock {
            waiters.isEmpty ? nil : waiters.removeFirst()
        }

        waiter?.resume()
    }

    func waitUntilWaiting() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if waiters.isEmpty {
                    waiterObservers.append(continuation)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func waitUntilConsumedTickCount(_ expectedCount: Int) async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if consumedTickCount >= expectedCount {
                    continuation.resume()
                } else {
                    consumedObservers.append(continuation)
                }
            }
        }
    }
}

/// Deterministic SlideshowClock for the resilience tests (310, FR-310-12): `now` is
/// manual, `sleep` parks a continuation, and `advance(by:)` releases every sleeper
/// whose deadline has passed — in deadline order, synchronously under the lock, so
/// tests can assert "still parked" without racing the scheduler.
final class TestClock: SlideshowClock, @unchecked Sendable {
    private struct Sleeper {
        let id: UUID
        let deadline: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var currentNow: Duration = .zero
    private var sleepers: [Sleeper] = []

    var now: Duration {
        lock.withLock { currentNow }
    }

    /// How many sleeps are currently parked. Reading this is synchronous truth —
    /// a sleeper counted here has provably not been resumed yet.
    var sleeperCount: Int {
        lock.withLock { sleepers.count }
    }

    func sleep(for duration: Duration) async throws {
        if Task.isCancelled {
            throw CancellationError()
        }
        guard duration > .zero else {
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                lock.withLock {
                    sleepers.append(Sleeper(id: id, deadline: currentNow + duration, continuation: continuation))
                }
            }
        } onCancel: {
            let cancelled = lock.withLock {
                sleepers.firstIndex { $0.id == id }.map { sleepers.remove(at: $0) }
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Move time forward and release every sleeper that became due, earliest
    /// deadline first.
    func advance(by duration: Duration) {
        let due = lock.withLock {
            currentNow += duration
            let now = currentNow
            let released = sleepers.filter { $0.deadline <= now }.sorted { $0.deadline < $1.deadline }
            sleepers.removeAll { $0.deadline <= now }
            return released
        }

        for sleeper in due {
            sleeper.continuation.resume()
        }
    }

    /// Yields until `count` sleepers are parked — the deterministic "the engine
    /// has reached its wait" handshake (same role as ManualTicker.waitUntilWaiting).
    /// Bounded so a missing sleeper fails the test's next assertion instead of
    /// hanging the run.
    func waitUntilSleeperCount(_ count: Int) async {
        for _ in 0..<10_000 {
            if lock.withLock({ sleepers.count >= count }) {
                return
            }
            await Task.yield()
        }
    }
}

/// Stand-in underlying error for the scripted `SourceFailure` values the engine
/// suites inject. The engine only ever inspects the `SourceFailure` case (via
/// `RetryPolicy.classify`), never this payload — it exists so `.transient`/`.permanent`
/// have a concrete `underlying`.
enum TestSourceError: Error {
    case probe
}

/// Per-fidelity image-request accounting for the engine suites, derived from
/// `StubPhotoSource.recordedImageRequests`. `StubImmichAPI` exposed separate
/// `previewCallCount(for:)` / `originalCallCount(for:)` counters; the neutral stub
/// records `(assetID, fidelity)` requests instead, so tests that care which tier
/// was fetched filter that log through this helper.
extension StubPhotoSource {
    func imageDataCallCount(for assetID: String, fidelity: ImageFidelity) -> Int {
        recordedImageRequests.filter { $0.assetID == assetID && $0.fidelity == fidelity }.count
    }
}

/// Creates a unique per-test directory under the system temp root (320). Unique
/// per call so parallel test execution never collides; tests clean up via
/// `defer { try? FileManager.default.removeItem(at: dir) }`.
func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("SlideshowKitTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Manually advanced wall clock for the disk cache's injected `now` (320): file
/// recency stamps become fully deterministic instead of racing mtime granularity.
final class MutableDateSource: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_000_000)

    var now: Date {
        lock.withLock { date }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock { date = date.addingTimeInterval(seconds) }
    }
}

/// Deterministic RNG (SplitMix64) so shuffle-order tests assert an exact, repeatable
/// permutation instead of relying on the system generator (SC-004).
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension NSLock {
    @discardableResult
    fileprivate func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
