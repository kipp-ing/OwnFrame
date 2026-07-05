import Foundation

@MainActor
public protocol PhotoReporting: AnyObject {
    var currentPhotoReport: PhotoReport { get }
    /// App version string for the diagnostic `version` sensor (FR-710-07). Constant
    /// for the process lifetime, so it lives on the reporter rather than each report.
    var version: String { get }
    func showNext() async
    func showPrevious() async
    var onPhotoChange: (@MainActor (PhotoReport) -> Void)? { get set }
}

public struct PhotoReport: Sendable, Equatable {
    public var assetID: String?
    public var imageData: Data?
    public var takenAt: Date?
    public var city: String?
    public var state: String?
    public var country: String?
    public var albumID: String?
    public var albumName: String?
    public var phase: SlideshowPhaseReport
    public var photoCount: Int

    public init(
        assetID: String?,
        imageData: Data?,
        takenAt: Date?,
        city: String?,
        state: String?,
        country: String?,
        albumID: String?,
        albumName: String?,
        phase: SlideshowPhaseReport,
        photoCount: Int
    ) {
        self.assetID = assetID
        self.imageData = imageData
        self.takenAt = takenAt
        self.city = city
        self.state = state
        self.country = country
        self.albumID = albumID
        self.albumName = albumName
        self.phase = phase
        self.photoCount = photoCount
    }
}

public enum SlideshowPhaseReport: String, Sendable, Equatable {
    case loading
    case playing
    case empty
    case failed
}
