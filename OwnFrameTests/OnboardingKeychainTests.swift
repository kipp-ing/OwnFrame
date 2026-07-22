//
//  OnboardingKeychainTests.swift
//  OwnFrameTests
//
//  App-hosted test for the real KeychainAPIKeyStore: proves the Security-backed
//  round-trip (save -> read -> overwrite -> delete) works through the real app
//  target on the iPad simulator. The OnboardingKit host suite uses
//  InMemoryKeychainStore; this exercises the actual keychain (SC-005).
//

import Foundation
import Testing
import OnboardingKit

struct OnboardingKeychainTests {

    // A test-only service/account so we never touch the app's real key entry.
    private func makeStore() -> KeychainAPIKeyStore {
        KeychainAPIKeyStore(
            service: "de.kippings.ImmichSlideshow.tests.apiKey",
            account: "test-account"
        )
    }

    @Test func keychainStoreRoundTripsSaveReadDelete() throws {
        let store = makeStore()
        store.delete() // clean slate regardless of prior runs
        defer { store.delete() }

        #expect(store.read() == nil)

        try store.save("secret-key-123")
        #expect(store.read() == "secret-key-123")

        // save overwrites idempotently
        try store.save("secret-key-456")
        #expect(store.read() == "secret-key-456")

        store.delete()
        #expect(store.read() == nil)
    }
}
