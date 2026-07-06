import Foundation
import Testing
@testable import HAControlKit

@Suite
struct HAEntityDefaultsTests {
    @Test
    func defaultEnabledIsEverythingExceptTheOptInImage() {
        // Contract (specs/710-ha-full-control/contracts/ha-mqtt-entities.md §2):
        // "Enabled by default: all except current_photo_image (opt-in)."
        let expected = Set(HAEntity.allCases).subtracting([.currentPhotoImage])
        #expect(HAEntity.defaultEnabled == expected)
    }
}
