import Foundation
import Testing
@testable import OnboardingKit

// Coverage for ConnectionURL.normalize — the pure server-URL normalizer used by
// onboarding and the connection editor. The function had no tests; these
// characterize its current behavior: trim, default to https, https-only, host required.

@Test func normalizePrependsHTTPSToBareHost() throws {
    let url = try #require(ConnectionURL.normalize("immich.example.com"))
    #expect(url.absoluteString == "https://immich.example.com")
}

@Test func normalizePreservesExplicitHTTPS() throws {
    let url = try #require(ConnectionURL.normalize("https://immich.example.com"))
    #expect(url.absoluteString == "https://immich.example.com")
}

@Test func normalizeTrimsSurroundingWhitespaceAndNewline() throws {
    let url = try #require(ConnectionURL.normalize("  immich.example.com\n"))
    #expect(url.absoluteString == "https://immich.example.com")
}

@Test func normalizeRejectsEmptyAndWhitespaceOnly() {
    #expect(ConnectionURL.normalize("") == nil)
    #expect(ConnectionURL.normalize("   ") == nil)
}

@Test func normalizeRejectsPlainHTTP() {
    #expect(ConnectionURL.normalize("http://immich.example.com") == nil)
}

@Test func normalizeRejectsNonHTTPScheme() {
    #expect(ConnectionURL.normalize("ftp://immich.example.com") == nil)
}

@Test func normalizePrependsHTTPSAndKeepsPortForBareHostWithPort() throws {
    let url = try #require(ConnectionURL.normalize("immich.example.com:2283"))
    #expect(url.absoluteString == "https://immich.example.com:2283")
}

@Test func normalizePreservesPathAndPort() throws {
    let url = try #require(ConnectionURL.normalize("https://immich.example.com:2283/api"))
    #expect(url.absoluteString == "https://immich.example.com:2283/api")
}

@Test func normalizeRejectsSchemeWithoutHost() {
    #expect(ConnectionURL.normalize("https://") == nil)
}
