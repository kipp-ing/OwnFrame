// StubPhotoSourceTests — T006: proves the scriptable fake scripts results/errors and records calls.

import Foundation
import Testing
import PhotoSourceKit
import PhotoSourceTestSupport

private struct ScriptedError: Error, Equatable {}

@Suite struct StubPhotoSourceTests {

    /// A scripted error is thrown on the matching call, and the call is still counted —
    /// the core capability the engine suites lean on when migrating off `StubImmichAPI`.
    @Test func scriptedErrorThrowsAndCountsTheCall() async {
        let stub = StubPhotoSource()
        stub.setAssetsError(ScriptedError(), for: "album-1")

        await #expect(throws: ScriptedError.self) {
            _ = try await stub.assets(in: "album-1")
        }
        #expect(stub.assetsCallCount == 1)
        #expect(stub.assetsCallCount(for: "album-1") == 1)
    }

    /// Scripted results come back verbatim; unrelated collections stay empty.
    @Test func scriptedResultsAreReturned() async throws {
        let stub = StubPhotoSource()
        let expected = [SourceAsset(id: "a", kind: .image), SourceAsset(id: "b", kind: .video)]
        stub.setAssets(expected, for: "album-1")
        stub.setCollections([SourceCollection(id: "album-1", title: "Trip", assetCount: 2, coverAssetID: "a")])

        #expect(try await stub.assets(in: "album-1") == expected)
        #expect(try await stub.assets(in: "album-2") == [])
        #expect(try await stub.collections().map(\.id) == ["album-1"])
    }

    /// `imageData` honours a per-fidelity override, falls back to the per-asset entry,
    /// and records each request's arguments in call order.
    @Test func imageDataFidelityRoutingAndArgumentCapture() async throws {
        let stub = StubPhotoSource()
        stub.setImageData(Data("fallback".utf8), for: "a")
        stub.setImageData(Data("orig".utf8), for: "a", fidelity: .original)

        let preview = try await stub.imageData(for: "a", fidelity: .preview)   // -> fallback
        let original = try await stub.imageData(for: "a", fidelity: .original) // -> exact override
        #expect(preview == Data("fallback".utf8))
        #expect(original == Data("orig".utf8))

        #expect(stub.imageDataCallCount == 2)
        #expect(stub.imageDataCallCount(for: "a") == 2)
        #expect(stub.recordedImageRequests.map(\.fidelity) == [.preview, .original])
    }

    /// The readiness gate is scriptable exactly like the old server-version gate.
    @Test func ensureReadyErrorIsScriptable() async {
        let stub = StubPhotoSource()
        stub.setEnsureReadyError(ScriptedError())
        await #expect(throws: ScriptedError.self) {
            try await stub.ensureReady()
        }
        #expect(stub.ensureReadyCallCount == 1)
    }
}
