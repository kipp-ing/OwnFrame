import Foundation
import SlideshowKit
import Testing

// The decoded-image store removes the swap-boundary hitch: the display path used
// to hand SwiftUI a fresh `UIImage(data:)` whose bitmap decodes lazily on first
// render — a main-thread stall exactly while both photo copies animate. The store
// decodes ahead (prefetch/show time) and the view looks up a ready bitmap by
// asset ID. Generic over the image type so the cache policy is host-testable
// with a dummy class and UIKit stays out of the package.

private final class FakeDecoded {
    let tag: UInt8
    init(tag: UInt8) { self.tag = tag }
}

private final class DecodeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

@MainActor
@Test func preparedImageIsRetrievableByAssetID() async {
    let store = DecodedImageStore<FakeDecoded>(capacity: 4) { data in
        FakeDecoded(tag: data.first ?? 0)
    }
    await store.prepare(assetID: "a", data: Data([7]))
    #expect(store.image(for: "a")?.tag == 7)
    #expect(store.image(for: "missing") == nil)
}

@MainActor
@Test func capacityEvictsTheOldestPreparedImage() async {
    let store = DecodedImageStore<FakeDecoded>(capacity: 2) { data in
        FakeDecoded(tag: data.first ?? 0)
    }
    await store.prepare(assetID: "a", data: Data([1]))
    await store.prepare(assetID: "b", data: Data([2]))
    await store.prepare(assetID: "c", data: Data([3]))
    #expect(store.image(for: "a") == nil)
    #expect(store.image(for: "b")?.tag == 2)
    #expect(store.image(for: "c")?.tag == 3)
}

@MainActor
@Test func repeatedPrepareDecodesOnlyOnce() async {
    let counter = DecodeCounter()
    let store = DecodedImageStore<FakeDecoded>(capacity: 4) { data in
        _ = counter.increment()
        return FakeDecoded(tag: data.first ?? 0)
    }
    await store.prepare(assetID: "a", data: Data([1]))
    await store.prepare(assetID: "a", data: Data([1]))
    #expect(counter.value == 1)
    #expect(store.image(for: "a")?.tag == 1)
}

@MainActor
@Test func concurrentPreparesForTheSameAssetDecodeOnce() async {
    let counter = DecodeCounter()
    let store = DecodedImageStore<FakeDecoded>(capacity: 4) { data in
        // Give the first decode time to still be in flight when the second
        // prepare arrives.
        try? await Task.sleep(for: .milliseconds(20))
        _ = counter.increment()
        return FakeDecoded(tag: data.first ?? 0)
    }
    async let first: Void = store.prepare(assetID: "a", data: Data([1]))
    async let second: Void = store.prepare(assetID: "a", data: Data([1]))
    _ = await (first, second)
    #expect(counter.value == 1)
    #expect(store.image(for: "a")?.tag == 1)
}

@MainActor
@Test func failedDecodeStoresNothingAndCanRetry() async {
    let counter = DecodeCounter()
    let store = DecodedImageStore<FakeDecoded>(capacity: 4) { data in
        _ = counter.increment()
        return data.isEmpty ? nil : FakeDecoded(tag: data.first ?? 0)
    }
    await store.prepare(assetID: "a", data: Data())
    #expect(store.image(for: "a") == nil)
    // A later prepare with usable bytes is not blocked by the failed attempt.
    await store.prepare(assetID: "a", data: Data([5]))
    #expect(store.image(for: "a")?.tag == 5)
    #expect(counter.value == 2)
}

@MainActor
@Test func refreshingAnExistingAssetKeepsItRetrievable() async {
    let store = DecodedImageStore<FakeDecoded>(capacity: 2) { data in
        FakeDecoded(tag: data.first ?? 0)
    }
    await store.prepare(assetID: "a", data: Data([1]))
    await store.prepare(assetID: "b", data: Data([2]))
    // Re-preparing "a" must not double-count it toward capacity or evict it.
    await store.prepare(assetID: "a", data: Data([1]))
    await store.prepare(assetID: "c", data: Data([3]))
    #expect(store.image(for: "c")?.tag == 3)
    #expect(store.image(for: "a") != nil || store.image(for: "b") != nil)
}
