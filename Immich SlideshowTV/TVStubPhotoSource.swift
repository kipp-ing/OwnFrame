//
//  TVStubPhotoSource.swift
//  Immich SlideshowTV
//
//  Topic 1000 (US1) — a self-contained `PhotoSourceProviding` for the tvOS simulator, where
//  there is no configured Immich server yet. It serves a small fixed set of generated,
//  visually distinct gradient images (each stamped with its asset id) so a photo-advance is
//  obviously visible on screen. T011/onboarding replaces this with the real Immich/Photos
//  source injected into the same `SlideshowViewModel` seam.
//

import Foundation
import PhotoSourceKit
import UIKit

struct TVStubPhotoSource: PhotoSourceProviding {
    /// One stub collection with a handful of images — enough to see the rotation advance.
    private let assetCount = 6
    private let collectionID = "stub"

    func ensureReady() async throws {
        // No precondition to gate: the stub is always ready (no server, no authorization).
    }

    func collections() async throws -> [SourceCollection] {
        [
            SourceCollection(
                id: collectionID,
                title: "Stub Album",
                assetCount: assetCount,
                coverAssetID: assetID(0)
            )
        ]
    }

    func assets(in collectionID: String) async throws -> [SourceAsset] {
        (0..<assetCount).map { SourceAsset(id: assetID($0), kind: .image) }
    }

    func imageData(for assetID: String, fidelity: ImageFidelity) async throws -> Data {
        Self.render(id: assetID, index: Self.index(from: assetID), of: assetCount)
    }

    func metadata(for assetID: String) async throws -> AssetMetadata {
        // Nothing real to report — the overlay renders nothing for nil fields (FR-300-24).
        AssetMetadata(capturedAt: nil, latitude: nil, longitude: nil, placeName: nil)
    }

    // MARK: - Helpers

    private func assetID(_ index: Int) -> String { "stub-\(index)" }

    private static func index(from assetID: String) -> Int {
        Int(assetID.replacingOccurrences(of: "stub-", with: "")) ?? 0
    }

    /// Render a 1920x1080 diagonal gradient with the asset id drawn large so a photo swap is
    /// unmistakable on screen. `UIGraphicsImageRenderer` is available on tvOS; the render is
    /// self-contained (no cross-actor state), so it is safe from the nonisolated source method.
    private static func render(id: String, index: Int, of count: Int) -> Data {
        let size = CGSize(width: 1920, height: 1080)
        let baseHue = CGFloat(index) / CGFloat(max(count, 1))
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.pngData { context in
            let cg = context.cgContext
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let top = UIColor(hue: baseHue, saturation: 0.60, brightness: 0.85, alpha: 1).cgColor
            let bottom = UIColor(
                hue: (baseHue + 0.14).truncatingRemainder(dividingBy: 1),
                saturation: 0.75,
                brightness: 0.30,
                alpha: 1
            ).cgColor

            if let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [top, bottom] as CFArray,
                locations: [0.0, 1.0]
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            let text = id as NSString
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 240, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let textSize = text.size(withAttributes: attributes)
            let rect = CGRect(
                x: 0,
                y: (size.height - textSize.height) / 2,
                width: size.width,
                height: textSize.height
            )
            text.draw(in: rect, withAttributes: attributes)
        }
    }
}
