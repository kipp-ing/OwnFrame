import Foundation
import Testing
@testable import OnboardingKit

private func makeStore() -> KeychainAPIKeyStore {
    let suffix = UUID().uuidString
    return KeychainAPIKeyStore(
        service: "de.kippings.ImmichSlideshow.apiKey.test.\(suffix)",
        account: "immich-api-key-test"
    )
}

@Test func saveAddsKeyWhenNoneExists() throws {
    let store = makeStore()
    defer { store.delete() }

    try store.save("first-key")

    #expect(store.read() == "first-key")
}

@Test func saveOverwritesExistingKey() throws {
    let store = makeStore()
    defer { store.delete() }

    try store.save("first-key")
    try store.save("second-key")

    #expect(store.read() == "second-key")
}

@Test func deleteRemovesTheKey() throws {
    let store = makeStore()
    defer { store.delete() }

    try store.save("first-key")
    store.delete()

    #expect(store.read() == nil)
}
