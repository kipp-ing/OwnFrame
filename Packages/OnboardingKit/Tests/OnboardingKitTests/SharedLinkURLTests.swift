import Foundation
import Testing
@testable import OnboardingKit

@Test func sharedLinkURLParsesHostAndSlug() throws {
    let parsed = try #require(SharedLinkURL.parse("https://bilder.kippings.de/s/geo2026"))

    #expect(parsed.baseURL.absoluteString == "https://bilder.kippings.de")
    #expect(parsed.slug == "geo2026")
}

// @covers FR-210-09
@Test func sharedLinkURLAddsHTTPSWhenSchemeMissing() throws {
    let parsed = try #require(SharedLinkURL.parse("bilder.kippings.de/s/korsika2026"))

    #expect(parsed.baseURL.absoluteString == "https://bilder.kippings.de")
    #expect(parsed.slug == "korsika2026")
}

@Test func sharedLinkURLKeepsExplicitPort() throws {
    let parsed = try #require(SharedLinkURL.parse("https://photos.example.test:8443/s/abc123"))

    #expect(parsed.baseURL.absoluteString == "https://photos.example.test:8443")
    #expect(parsed.slug == "abc123")
}

@Test func sharedLinkURLIgnoresQueryAndTrailingSlash() throws {
    let parsed = try #require(SharedLinkURL.parse("https://bilder.kippings.de/s/geo2026/?foo=bar"))

    #expect(parsed.slug == "geo2026")
}

// @covers FR-210-09
@Test func sharedLinkURLRejectsNonHTTPS() {
    #expect(SharedLinkURL.parse("http://bilder.kippings.de/s/geo2026") == nil)
}

// @covers FR-210-09
@Test func sharedLinkURLRejectsMissingSlug() {
    #expect(SharedLinkURL.parse("https://bilder.kippings.de") == nil)
    #expect(SharedLinkURL.parse("https://bilder.kippings.de/s/") == nil)
}

@Test func sharedLinkURLRejectsEmptyInput() {
    #expect(SharedLinkURL.parse("   ") == nil)
}
