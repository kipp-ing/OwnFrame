// SourceModelsTests — T004: wire-shape + case-surface guards for the neutral models (spec 900, R2/R3/R8).

import Foundation
import Testing
@testable import PhotoSourceKit

private struct SampleError: Error, Equatable {}

@Suite struct SourceModelsTests {

    // MARK: - SourceAsset wire shape (R2)

    /// (a) Decodes the exact shipped `[Asset]` snapshot bytes: `type` is `kind`'s
    /// coding key, Immich strings are the raw values. Old files decode without migration.
    @Test func decodesLegacySnapshotShape() throws {
        let json = #"[{"id":"asset-1","type":"IMAGE"},{"id":"asset-2","type":"VIDEO"}]"#
        let assets = try JSONDecoder().decode([SourceAsset].self, from: Data(json.utf8))
        #expect(assets == [
            SourceAsset(id: "asset-1", kind: .image),
            SourceAsset(id: "asset-2", kind: .video),
        ])
    }

    /// (b) Re-encodes to the identical `{id, type}` shape. Decoding the encoded bytes as
    /// raw `[String: String]` proves the on-wire key is `type` (not `kind`) and the value
    /// is the Immich raw string — byte-shape compatibility with fielded snapshots.
    @Test func encodesBackToLegacySnapshotShape() throws {
        let assets = [
            SourceAsset(id: "asset-1", kind: .image),
            SourceAsset(id: "asset-2", kind: .video),
        ]
        let encoded = try JSONEncoder().encode(assets)
        let asDicts = try JSONDecoder().decode([[String: String]].self, from: encoded)
        #expect(asDicts == [
            ["id": "asset-1", "type": "IMAGE"],
            ["id": "asset-2", "type": "VIDEO"],
        ])
    }

    /// (c) Unknown wire kinds decode to `.other` instead of throwing (forward-compat, R8).
    /// DOCUMENTED BEHAVIOR: the original unknown string ("SPATIAL") is intentionally NOT
    /// preserved — it normalizes to "OTHER" on re-encode. The engine only needs to know a
    /// kind is not a still image so it can skip it, and `.other` captures exactly that.
    /// Re-encoding an `.other` value never throws and is idempotent from there on.
    @Test func unknownKindDecodesToOtherAndReEncodesLosslesslyEnough() throws {
        let json = #"{"id":"asset-x","type":"SPATIAL"}"#
        let asset = try JSONDecoder().decode(SourceAsset.self, from: Data(json.utf8))
        #expect(asset.kind == .other)

        let encoded = try JSONEncoder().encode(asset)
        let asDict = try JSONDecoder().decode([String: String].self, from: encoded)
        #expect(asDict == ["id": "asset-x", "type": "OTHER"])

        // Idempotent from .other onward — no crash, stays .other.
        let reDecoded = try JSONDecoder().decode(SourceAsset.self, from: encoded)
        #expect(reDecoded.kind == .other)
    }

    /// The three known raw values are the Immich strings (wire compat, R2/R8).
    @Test func mediaKindRawValues() {
        #expect(MediaKind.image.rawValue == "IMAGE")
        #expect(MediaKind.video.rawValue == "VIDEO")
        #expect(MediaKind.other.rawValue == "OTHER")
    }

    // MARK: - SourceFailure surface (R3)

    /// (d) Exactly the four contract cases, usable in an exhaustive switch with no
    /// `default`. A missing or extra case would fail to compile — this is the surface guard.
    @Test func sourceFailureHasExactlyFourExhaustiveCases() {
        func label(_ failure: SourceFailure) -> String {
            switch failure {
            case .transient: return "transient"
            case .authentication: return "authentication"
            case .notFound: return "notFound"
            case .permanent: return "permanent"
            }
        }
        #expect(label(.transient(underlying: SampleError())) == "transient")
        #expect(label(.authentication) == "authentication")
        #expect(label(.notFound) == "notFound")
        #expect(label(.permanent(underlying: SampleError())) == "permanent")
    }

    // MARK: - ImageFidelity raw values (cache-key components — stability matters)

    /// (e) Raw values are the stable lowercase tier names; they participate in the
    /// `"\(id)#\(fidelity)"` cache key, so drift would silently invalidate on-disk caches.
    @Test func imageFidelityRawValues() {
        #expect(ImageFidelity.thumbnail.rawValue == "thumbnail")
        #expect(ImageFidelity.preview.rawValue == "preview")
        #expect(ImageFidelity.original.rawValue == "original")
    }
}
