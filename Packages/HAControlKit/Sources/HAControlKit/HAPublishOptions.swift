import Foundation

public struct HAPublishOptions: Sendable, Equatable, Codable {
    public var imageEnabled: Bool
    public var imageSource: ImageSource
    public var byteCap: Int

    public enum ImageSource: String, Sendable, Equatable, Codable, CaseIterable {
        case thumbnail, preview
    }

    public init(
        imageEnabled: Bool = false,
        imageSource: ImageSource = .thumbnail,
        byteCap: Int = 512_000
    ) {
        self.imageEnabled = imageEnabled
        self.imageSource = imageSource
        self.byteCap = byteCap
    }
}

@MainActor
public protocol HAPublishOptionsStore: AnyObject {
    var options: HAPublishOptions { get set }
}

@MainActor
public final class UserDefaultsHAPublishOptionsStore: HAPublishOptionsStore {
    /// The single key this store owns. Exposed so a test seam can clear it directly instead of
    /// calling `removePersistentDomain`, which leaves later writes through the same
    /// `UserDefaults` instance silently dropped.
    public static let defaultsKey = "haPublish.options"

    private let defaults: UserDefaults
    private var cachedOptions: HAPublishOptions

    public var options: HAPublishOptions {
        get { cachedOptions }
        set {
            cachedOptions = newValue
            if let encoded = try? JSONEncoder().encode(newValue),
               let jsonString = String(data: encoded, encoding: .utf8) {
                defaults.set(jsonString, forKey: Self.defaultsKey)
            }
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let saved = defaults.string(forKey: Self.defaultsKey),
           let data = saved.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(HAPublishOptions.self, from: data) {
            self.cachedOptions = decoded
        } else {
            self.cachedOptions = HAPublishOptions()
        }
    }
}

@MainActor
public final class InMemoryHAPublishOptionsStore: HAPublishOptionsStore {
    public var options: HAPublishOptions = HAPublishOptions()

    public init() {}
}
