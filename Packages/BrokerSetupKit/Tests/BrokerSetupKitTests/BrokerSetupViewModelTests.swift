import Testing
@testable import BrokerSetupKit

// @covers FR-600-12
@Test func loadPrefillsWithoutSecret() throws {
    let store = InMemoryBrokerSettingsStore()
    try store.save(BrokerSettings(host: "mqtt.example.com", port: 8883, username: "ha-user", password: "secret"))
    let viewModel = BrokerSetupViewModel(store: store)

    viewModel.load()

    #expect(viewModel.host == "mqtt.example.com")
    #expect(viewModel.port == "8883")
    #expect(viewModel.username == "ha-user")
    #expect(viewModel.password == "")
    #expect(viewModel.passwordIsSet == true)
}

// @covers FR-600-01
@Test func saveNewBrokerPersists() {
    let store = InMemoryBrokerSettingsStore()
    let viewModel = BrokerSetupViewModel(store: store)

    viewModel.host = "mqtt.example.com"
    viewModel.port = "8883"
    viewModel.username = "ha-user"
    viewModel.password = "secret"

    #expect(viewModel.save() == true)
    #expect(store.load() == BrokerSettings(host: "mqtt.example.com", port: 8883, username: "ha-user", password: "secret"))
}

// @covers FR-600-10
@Test func saveEmptyPasswordKeepsExisting() throws {
    let store = InMemoryBrokerSettingsStore()
    try store.save(BrokerSettings(host: "mqtt.example.com", port: 8883, username: "ha-user", password: "secret"))
    let viewModel = BrokerSetupViewModel(store: store)

    viewModel.load()
    viewModel.host = "mqtt-new.example.com"

    #expect(viewModel.save() == true)
    #expect(store.load() == BrokerSettings(host: "mqtt-new.example.com", port: 8883, username: "ha-user", password: "secret"))
}

// @covers FR-600-10
@Test func saveNewPasswordOverwritesExistingPassword() throws {
    let store = InMemoryBrokerSettingsStore()
    try store.save(BrokerSettings(host: "mqtt.example.com", port: 8883, username: "ha-user", password: "secret"))
    let viewModel = BrokerSetupViewModel(store: store)

    viewModel.load()
    viewModel.password = "new-secret"

    #expect(viewModel.save() == true)
    #expect(store.load() == BrokerSettings(host: "mqtt.example.com", port: 8883, username: "ha-user", password: "new-secret"))
}

// @covers FR-600-03
@Test func saveInvalidPortReportsError() {
    let store = InMemoryBrokerSettingsStore()
    let viewModel = BrokerSetupViewModel(store: store)

    viewModel.host = "mqtt.example.com"
    viewModel.port = "0"
    viewModel.username = "ha-user"
    viewModel.password = "secret"

    #expect(viewModel.save() == false)
    #expect(viewModel.validationError == .invalidPort)
    #expect(store.load() == nil)
}

// @covers FR-600-03
@Test func saveEmptyHostReportsError() {
    let store = InMemoryBrokerSettingsStore()
    let viewModel = BrokerSetupViewModel(store: store)

    viewModel.host = ""

    #expect(viewModel.save() == false)
    #expect(viewModel.validationError == .emptyHost)
}

@Test func removeClearsStoreAndForm() throws {
    let store = InMemoryBrokerSettingsStore()
    try store.save(BrokerSettings(host: "mqtt.example.com", port: 8883, username: "ha-user", password: "secret"))
    let viewModel = BrokerSetupViewModel(store: store)
    viewModel.load()

    viewModel.remove()

    #expect(store.load() == nil)
    #expect(viewModel.host == "")
    #expect(viewModel.username == "")
    #expect(viewModel.passwordIsSet == false)
}
