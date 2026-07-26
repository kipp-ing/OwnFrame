import Foundation
import Testing
@testable import HAControlKit

@Suite
struct HATopicsTests {
    // @covers FR-710-18
    @Test
    func haEntityRawValues() {
        #expect(HAEntity.order.rawValue == "order")
        #expect(HAEntity.duration.rawValue == "duration")
        #expect(HAEntity.transition.rawValue == "transition")
        #expect(HAEntity.kenBurns.rawValue == "ken_burns")
        #expect(HAEntity.fit.rawValue == "fit")
        #expect(HAEntity.quality.rawValue == "quality")
        #expect(HAEntity.clock.rawValue == "clock")
        #expect(HAEntity.clockCorner.rawValue == "clock_corner")
        #expect(HAEntity.clockStyle.rawValue == "clock_style")
        #expect(HAEntity.clockSize.rawValue == "clock_size")
        #expect(HAEntity.clockDate.rawValue == "clock_date")
        #expect(HAEntity.next.rawValue == "next")
        #expect(HAEntity.previous.rawValue == "previous")
        #expect(HAEntity.currentPhoto.rawValue == "current_photo")
        #expect(HAEntity.currentPhotoImage.rawValue == "current_photo_image")
        #expect(HAEntity.phase.rawValue == "phase")
        #expect(HAEntity.photoCount.rawValue == "photo_count")
        #expect(HAEntity.version.rawValue == "version")
        #expect(HAEntity.frameStatus.rawValue == "frame_status")
    }

    @Test
    func haEntityAllCasesCount() {
        // 21 core + battery + charging (1200 US3) + frame_status (FR-710-24, 2026-07-26).
        #expect(HAEntity.allCases.count == 24)
    }

    // @covers FR-710-01, FR-710-08
    @Test
    func discoveryConfigTopicUsesCorrectComponent() {
        // New entities
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .order) == "homeassistant/select/dev1/order/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .duration) == "homeassistant/number/dev1/duration/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .transition) == "homeassistant/select/dev1/transition/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .kenBurns) == "homeassistant/switch/dev1/ken_burns/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .fit) == "homeassistant/select/dev1/fit/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .quality) == "homeassistant/select/dev1/quality/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .clock) == "homeassistant/switch/dev1/clock/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .clockCorner) == "homeassistant/select/dev1/clock_corner/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .clockStyle) == "homeassistant/select/dev1/clock_style/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .clockSize) == "homeassistant/select/dev1/clock_size/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .clockDate) == "homeassistant/switch/dev1/clock_date/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .next) == "homeassistant/button/dev1/next/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .previous) == "homeassistant/button/dev1/previous/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .currentPhoto) == "homeassistant/sensor/dev1/current_photo/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .currentPhotoImage) == "homeassistant/image/dev1/current_photo_image/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .phase) == "homeassistant/sensor/dev1/phase/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .photoCount) == "homeassistant/sensor/dev1/photo_count/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .version) == "homeassistant/sensor/dev1/version/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .frameStatus) == "homeassistant/sensor/dev1/frame_status/config")

        // Existing entities (regression check)
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .playback) == "homeassistant/switch/dev1/playback/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .brightness) == "homeassistant/light/dev1/brightness/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .album) == "homeassistant/select/dev1/album/config")
    }

    @Test
    func stateTopicForPhotoEntities() {
        #expect(HATopics.stateTopic(deviceID: "dev1", entity: .currentPhoto) == "ownframe/dev1/current_photo/state")
        #expect(HATopics.stateTopic(deviceID: "dev1", entity: .currentPhotoImage) == "ownframe/dev1/current_photo_image/state")
    }
}
