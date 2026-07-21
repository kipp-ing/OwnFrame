import Testing
@testable import BrokerSetupKit

@Test func validationAcceptsCompleteSettings() {
    let settings = BrokerSettings(host: "broker.local", port: 1883, username: "mqtt", password: "secret")

    #expect(settings.validate() == nil)
}

// @covers FR-600-02
@Test func validationReturnsFirstErrorInContractOrder() {
    #expect(BrokerSettings(host: " \n", port: 0, username: "", password: "").validate() == .emptyHost)
    #expect(BrokerSettings(host: "broker.local", port: 0, username: "", password: "").validate() == .invalidPort)
    #expect(BrokerSettings(host: "broker.local", port: 1883, username: " \n", password: "").validate() == .emptyUsername)
    #expect(BrokerSettings(host: "broker.local", port: 1883, username: "mqtt", password: "").validate() == .emptyPassword)
}

// @covers FR-600-02
@Test func validationAcceptsBoundaryPorts() {
    #expect(BrokerSettings(host: "broker.local", port: 1, username: "mqtt", password: "secret").validate() == nil)
    #expect(BrokerSettings(host: "broker.local", port: 65_535, username: "mqtt", password: "secret").validate() == nil)
}

// @covers FR-600-02
@Test func validationRejectsPortsOutsideTCPRange() {
    #expect(BrokerSettings(host: "broker.local", port: 0, username: "mqtt", password: "secret").validate() == .invalidPort)
    #expect(BrokerSettings(host: "broker.local", port: 65_536, username: "mqtt", password: "secret").validate() == .invalidPort)
}

@Test func inMemoryStoreRoundTripsCompleteSettings() throws {
    let store = InMemoryBrokerSettingsStore()
    let settings = BrokerSettings(host: "broker.local", port: 1883, username: "mqtt", password: "secret")

    try store.save(settings)

    #expect(store.load() == settings)
}

@Test func inMemoryStoreRejectsInvalidSettingsWithoutWriting() {
    let store = InMemoryBrokerSettingsStore()
    let invalid = BrokerSettings(host: "", port: 1883, username: "mqtt", password: "secret")

    #expect(throws: BrokerValidationError.emptyHost) {
        try store.save(invalid)
    }
    #expect(store.load() == nil)
}

@Test func inMemoryStoreClearRemovesSettings() throws {
    let store = InMemoryBrokerSettingsStore()
    try store.save(BrokerSettings(host: "broker.local", port: 1883, username: "mqtt", password: "secret"))

    store.clear()

    #expect(store.load() == nil)
}
