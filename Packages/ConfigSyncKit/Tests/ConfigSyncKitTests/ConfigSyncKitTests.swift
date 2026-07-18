import Testing
@testable import ConfigSyncKit

@Test func schemaVersionIsStamped() {
    #expect(ConfigSyncSchema.current == 1)
}
