import Foundation
import PowerKit

@MainActor
final class FakeScreenController: ScreenControlling {
    var brightnessWrites: [Double] = []
    private var _brightness: Double
    var isIdleTimerDisabled: Bool = false

    init(brightness: Double = 0.5) {
        _brightness = brightness
    }

    var brightness: Double {
        get { _brightness }
        set {
            _brightness = newValue
            brightnessWrites.append(newValue)
        }
    }

    /// iOS moving brightness on its own (auto-brightness drift, 410 finding 2) — not an app write.
    func systemMoves(to value: Double) {
        _brightness = value
    }
}

/// 410: a wall clock the test moves by hand.
@MainActor
final class WallClock {
    var now: Date

    init(_ string: String) {
        now = WallClock.date(string)
    }

    func set(_ string: String) {
        now = WallClock.date(string)
    }

    func advance(seconds: TimeInterval) {
        now += seconds
    }

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    static func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: string.count == 16 ? string + ":00" : string)!
    }
}

struct ManualClock: PowerClock {
    func sleep(for duration: Duration) async throws {}
}

final class BlockingManualClock: PowerClock, @unchecked Sendable {
    private let lock = NSLock()
    private var sleepers: [CheckedContinuation<Void, any Error>] = []
    private var observers: [CheckedContinuation<Void, Never>] = []

    var sleepingCount: Int {
        lock.withLock { sleepers.count }
    }

    func sleep(for duration: Duration) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    sleepers.append(continuation)
                    observers.forEach { $0.resume() }
                    observers.removeAll()
                }
            }
        } onCancel: {
            cancelOne()
        }
    }

    func advanceOne() {
        let sleeper = lock.withLock {
            sleepers.isEmpty ? nil : sleepers.removeFirst()
        }
        sleeper?.resume()
    }

    func waitUntilSleeping() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if sleepers.isEmpty {
                    observers.append(continuation)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func cancelOne() {
        let sleeper = lock.withLock {
            sleepers.isEmpty ? nil : sleepers.removeFirst()
        }
        sleeper?.resume(throwing: CancellationError())
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

/// 410 review: a clock whose sleep only yields, so a soft-dim ramp really interleaves with a
/// second event on the main actor (the transition race).
struct YieldingClock: PowerClock {
    func sleep(for duration: Duration) async throws {
        await Task.yield()
        try Task.checkCancellation()
    }
}
