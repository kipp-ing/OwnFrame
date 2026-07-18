import Foundation
import Testing
@testable import HAControlKit

@Suite
struct FrameIdentityTests {
    @Test
    func distinctIdentitiesProduceDifferentTopicBase() {
        let ipad = FrameIdentity(deviceID: "ABC", deviceName: "Photo Frame")
        let appleTV = FrameIdentity(deviceID: "ABC-appletv", deviceName: "Photo Frame (Apple TV)")

        #expect(ipad.deviceID != appleTV.deviceID)
        #expect(HATopics.base(deviceID: ipad.deviceID) != HATopics.base(deviceID: appleTV.deviceID))
        #expect(HATopics.base(deviceID: ipad.deviceID) == "immichslideshow/ABC")
        #expect(HATopics.base(deviceID: appleTV.deviceID) == "immichslideshow/ABC-appletv")
    }

    @Test
    func distinctIdentitiesProduceDifferentDiscoveryUniqueIDAndIdentifiers() throws {
        let ipad = FrameIdentity(deviceID: "ABC", deviceName: "Photo Frame")
        let appleTV = FrameIdentity(deviceID: "ABC-appletv", deviceName: "Photo Frame (Apple TV)")

        let ipadJSON = try Self.object(from: HADiscovery.config(
            for: .playback, deviceID: ipad.deviceID, deviceName: ipad.deviceName, albumOptions: []
        ))
        let tvJSON = try Self.object(from: HADiscovery.config(
            for: .playback, deviceID: appleTV.deviceID, deviceName: appleTV.deviceName, albumOptions: []
        ))

        // Same entity, distinct identity -> distinct unique_id: no HA entity collision.
        #expect(ipadJSON["unique_id"] as? String == "ABC_playback")
        #expect(tvJSON["unique_id"] as? String == "ABC-appletv_playback")
        #expect(ipadJSON["unique_id"] as? String != tvJSON["unique_id"] as? String)

        // ...and distinct device identifiers + names: two HA devices, not one.
        let ipadDevice = try #require(ipadJSON["device"] as? [String: Any])
        let tvDevice = try #require(tvJSON["device"] as? [String: Any])
        #expect(ipadDevice["identifiers"] as? [String] == ["ABC"])
        #expect(tvDevice["identifiers"] as? [String] == ["ABC-appletv"])
        #expect((ipadDevice["identifiers"] as? [String]) != (tvDevice["identifiers"] as? [String]))
        #expect(ipadDevice["name"] as? String == "Photo Frame")
        #expect(tvDevice["name"] as? String == "Photo Frame (Apple TV)")
    }

    @Test
    func equatableHolds() {
        #expect(FrameIdentity(deviceID: "ABC", deviceName: "Photo Frame")
            == FrameIdentity(deviceID: "ABC", deviceName: "Photo Frame"))
        #expect(FrameIdentity(deviceID: "ABC", deviceName: "Photo Frame")
            != FrameIdentity(deviceID: "ABC-appletv", deviceName: "Photo Frame (Apple TV)"))
    }

    private static func object(from data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
