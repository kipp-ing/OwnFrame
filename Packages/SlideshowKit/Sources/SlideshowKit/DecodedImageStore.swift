import Foundation
import Observation

/// Small decode-ahead cache keyed by asset ID: `prepare` decodes bytes into a
/// ready-to-render bitmap via the injected closure, the display path looks the
/// bitmap up synchronously at body time (falling back to its old lazy decode
/// when preparation hasn't landed yet). Generic over the image type so the
/// policy is host-testable with a dummy class and UIKit stays out of the
/// package — the app injects `UIImage(data:)?.byPreparingForDisplay()`.
///
/// `@Observable` on purpose: a view that rendered the lazy fallback re-renders
/// once the decoded instance lands, so later frames (and the next swap) use the
/// pre-decoded bitmap. Capacity holds the working set: current + prefetch
/// window + the outgoing copy still fading.
@MainActor
@Observable
public final class DecodedImageStore<DecodedImage: AnyObject>: DisplayImagePreparing {
    private let capacity: Int
    @ObservationIgnored private let decode: @Sendable (Data) async -> DecodedImage?
    /// Insertion-ordered (oldest first) — eviction drops the front.
    private var images: [(assetID: String, image: DecodedImage)] = []
    @ObservationIgnored private var inFlight: Set<String> = []

    public init(capacity: Int = 4, decode: @escaping @Sendable (Data) async -> DecodedImage?) {
        self.capacity = max(capacity, 1)
        self.decode = decode
    }

    public func image(for assetID: String) -> DecodedImage? {
        images.first(where: { $0.assetID == assetID })?.image
    }

    public func prepare(assetID: String, data: Data) async {
        guard image(for: assetID) == nil, !inFlight.contains(assetID) else { return }
        inFlight.insert(assetID)
        defer { inFlight.remove(assetID) }
        guard let decoded = await decode(data) else { return }
        images.removeAll { $0.assetID == assetID }
        images.append((assetID: assetID, image: decoded))
        if images.count > capacity {
            images.removeFirst(images.count - capacity)
        }
    }
}

#if canImport(UIKit)
import UIKit

public extension DecodedImageStore where DecodedImage == UIImage {
    /// The display-path store both app targets inject: decodes off the main
    /// thread into a render-ready bitmap (`byPreparingForDisplay`), so the swap
    /// never pays a lazy first-render decode. Capacity 4 = current photo +
    /// prefetch window (2) + the outgoing copy still fading.
    static func displayStore(capacity: Int = 4) -> DecodedImageStore<UIImage> {
        DecodedImageStore(capacity: capacity) { data in
            await UIImage(data: data)?.byPreparingForDisplay()
        }
    }
}
#endif
