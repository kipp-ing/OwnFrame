import Foundation
import OnboardingKit
import Testing
@testable import OwnFrame

// 310, FR-310-16 via 120, FR-120-13 (#61): the new-photos card names the active source by its
// display name, never a raw host. Sources saved before the album-name default carry their host
// (or `host N`) as the stored label; the card maps those to the neutral placeholder at display
// time, and passes every human label through unchanged.
@MainActor
struct NewPhotosCardLabelTests {

    private nonisolated static let baseURL = URL(string: "https://bilder.example.org")!

    private static func link(label: String) -> Source {
        Source(label: label, kind: .sharedLink(baseURL: baseURL, slug: "family"))
    }

    // @covers FR-310-16, FR-120-13
    @Test(arguments: ["bilder.example.org", "bilder.example.org 2"])
    func hostLabeledLinkShowsThePlaceholder(_ storedLabel: String) {
        let source = Self.link(label: storedLabel)

        let shown = NewPhotosOverlayView.sourceLabel(for: source)

        #expect(shown == SourceLibraryViewModel.displayName(for: source))
        #expect(shown?.localizedCaseInsensitiveContains("bilder.example.org") == false)
    }

    // @covers FR-310-16, FR-120-13
    @Test(arguments: [
        Source(label: "Iceland 2021", kind: .sharedLink(baseURL: baseURL, slug: "family")),
        Source(label: "Wohnzimmer", kind: .album(albumID: "a1")),
        Source(label: "Holiday", kind: .photoLibrary(collectionID: "ph-1"))
    ])
    func humanLabelsPassThroughUnchanged(_ source: Source) {
        #expect(NewPhotosOverlayView.sourceLabel(for: source) == source.label)
    }

    @Test func noActiveSourceShowsNoLabel() {
        #expect(NewPhotosOverlayView.sourceLabel(for: nil) == nil)
    }
}
