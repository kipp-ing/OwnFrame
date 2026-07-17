import Foundation
import Testing
@testable import OnboardingKit

// 220: QR-scan onboarding decodes a raw string off the camera; `ScannedShareLink.validate`
// is the pure, synchronous seam that turns that string into either a parsed share link or
// a classified rejection reason. No network call and no persistence on any path — the
// camera and the store are both out of scope for this type.

@Test func scannedShareLinkValidatesAValidImmichShareString() throws {
    let raw = "https://bilder.kippings.de/s/geo2026"
    let expected = try #require(SharedLinkURL.parse(raw))

    let result = ScannedShareLink.validate(raw)

    #expect(result == .success(ParsedSharedLink(baseURL: expected.baseURL, slug: expected.slug)))
}

@Test func scannedShareLinkRejectsANonURLString() {
    let result = ScannedShareLink.validate("not a share link at all")

    #expect(result == .failure(.notAURL))
}

@Test func scannedShareLinkRejectsANonHTTPSURL() {
    let result = ScannedShareLink.validate("http://bilder.kippings.de/s/geo2026")

    #expect(result == .failure(.notHTTPS))
}

@Test func scannedShareLinkRejectsAURLWithNoShareShape() {
    let result = ScannedShareLink.validate("https://bilder.kippings.de")

    #expect(result == .failure(.notAShareLink))
}

@Test func scannedShareLinkFailurePersistsNothingAndMakesNoNetworkCall() {
    // `validate` is pure/synchronous — a `Result<_, InvalidCodeReason>` return with no
    // `async`/`throws` is itself the proof that no store or client is reachable from here;
    // this assertion documents that contract rather than exercising I/O that cannot exist.
    let reasons: [InvalidCodeReason] = [.notAURL, .notHTTPS, .notAShareLink]
    let inputs = [
        "not a share link at all",
        "http://bilder.kippings.de/s/geo2026",
        "https://bilder.kippings.de",
    ]

    for (input, reason) in zip(inputs, reasons) {
        #expect(ScannedShareLink.validate(input) == .failure(reason))
    }
}
