import Foundation
import Testing
@testable import HAControlKit

@Suite
@MainActor
struct HAPublishOptionsTests {
    
    @Test
    func hAPublishOptionsDefaults() {
        let options = HAPublishOptions()
        #expect(options.imageEnabled == false)
        #expect(options.imageSource == .thumbnail)
        #expect(options.byteCap == 512_000)
    }
    
    @Test
    func userDefaultsHAPublishOptionsStoreRoundTrip() {
        let suiteName = "com.test.HAPublishOptionsTest"
        let defaults = UserDefaults(suiteName: suiteName)!
        
        // Clean up before and after
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            defaults.synchronize()
        }
        
        // Remove persistent domain before test
        defaults.removePersistentDomain(forName: suiteName)
        
        // Create store and write options
        let store1 = UserDefaultsHAPublishOptionsStore(defaults: defaults)
        let newOptions = HAPublishOptions(
            imageEnabled: true,
            imageSource: .preview,
            byteCap: 200_000
        )
        store1.options = newOptions
        
        // Create a second store on the same suite and read back
        let store2 = UserDefaultsHAPublishOptionsStore(defaults: defaults)
        let readOptions = store2.options
        
        #expect(readOptions.imageEnabled == true)
        #expect(readOptions.imageSource == .preview)
        #expect(readOptions.byteCap == 200_000)
    }
    
    @Test
    func userDefaultsHAPublishOptionsStoreFreshReturnsDefaults() {
        let suiteName = "com.test.HAPublishOptionsDefaultsTest"
        let defaults = UserDefaults(suiteName: suiteName)!
        
        // Clean up before and after
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            defaults.synchronize()
        }
        
        // Remove persistent domain to ensure fresh state
        defaults.removePersistentDomain(forName: suiteName)
        
        let store = UserDefaultsHAPublishOptionsStore(defaults: defaults)
        let options = store.options
        
        #expect(options.imageEnabled == false)
        #expect(options.imageSource == .thumbnail)
        #expect(options.byteCap == 512_000)
    }
    
    @Test
    func inMemoryHAPublishOptionsStoreRoundTrip() {
        let store = InMemoryHAPublishOptionsStore()
        
        // Start at defaults
        #expect(store.options.imageEnabled == false)
        #expect(store.options.imageSource == .thumbnail)
        #expect(store.options.byteCap == 512_000)
        
        // Set new values
        let newOptions = HAPublishOptions(
            imageEnabled: true,
            imageSource: .preview,
            byteCap: 200_000
        )
        store.options = newOptions
        
        // Round-trip works
        #expect(store.options.imageEnabled == true)
        #expect(store.options.imageSource == .preview)
        #expect(store.options.byteCap == 200_000)
    }
}
