import HAControlKit
import Testing
@testable import BrokerSetupKit

// @covers FR-600-08
@Test func providerReturnsNilWithoutSettings() {
    let store = InMemoryBrokerSettingsStore()
    let provider = BrokerConfigProvider(settingsStore: store, deviceID: "ipad-wall")

    #expect(provider.load() == nil)
}

// @covers FR-600-08
@Test func providerReturnsNilForPersistedInvalidSettings() {
    let store = InMemoryBrokerSettingsStore(settings: BrokerSettings(
        host: "broker.local",
        port: 1883,
        username: "mqtt",
        password: ""
    ))
    let provider = BrokerConfigProvider(settingsStore: store, deviceID: "ipad-wall")

    #expect(provider.load() == nil)
}

// @covers FR-600-07
@Test func providerBuildsBrokerConfigFromSettingsAndDeviceID() throws {
    let store = InMemoryBrokerSettingsStore()
    try store.save(BrokerSettings(host: "broker.local", port: 1883, username: "mqtt", password: "secret"))
    let provider = BrokerConfigProvider(settingsStore: store, deviceID: "ipad-wall")

    #expect(provider.load() == BrokerConfig(
        host: "broker.local",
        port: 1883,
        username: "mqtt",
        password: "secret",
        deviceID: "ipad-wall"
    ))
}

@Test func providerUsesStableDeviceIDAcrossStoreAndProviderReloads() throws {
    let settings = BrokerSettings(host: "broker.local", port: 1883, username: "mqtt", password: "secret")
    let firstStore = InMemoryBrokerSettingsStore()
    try firstStore.save(settings)
    let deviceID = "ipad-wall"

    let first = BrokerConfigProvider(settingsStore: firstStore, deviceID: deviceID).load()
    let reloadedStore = InMemoryBrokerSettingsStore(settings: firstStore.load())
    let second = BrokerConfigProvider(settingsStore: reloadedStore, deviceID: deviceID).load()

    #expect(first?.deviceID == deviceID)
    #expect(second?.deviceID == deviceID)
    #expect(first == second)
}
