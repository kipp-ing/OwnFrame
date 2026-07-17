import Foundation

/// The whitelisted read-model for "Get Frame State" (data-model.md
/// "FrameStateSnapshot", FR-800-07, research R6). Built exclusively by
/// `FrameCommandService.frameState()`; the app-target `FrameStateEntity` mirrors
/// it field-for-field.
///
/// Exactly six stored properties, nothing else — the exclusion of image bytes,
/// asset/album IDs, region, phase, photo count, and app version is structural,
/// not a filter that could regress (SC-800-04). Keep this a dumb value type;
/// the surface → snapshot mapping lives in `FrameCommandService.frameState()`.
public struct FrameStateSnapshot: Sendable, Equatable {
    public let isPlaying: Bool
    public let brightnessPercent: Int
    public let sourceLabel: String?
    public let photoDate: Date?
    public let photoCity: String?
    public let photoCountry: String?

    public init(
        isPlaying: Bool,
        brightnessPercent: Int,
        sourceLabel: String?,
        photoDate: Date?,
        photoCity: String?,
        photoCountry: String?
    ) {
        self.isPlaying = isPlaying
        self.brightnessPercent = brightnessPercent
        self.sourceLabel = sourceLabel
        self.photoDate = photoDate
        self.photoCity = photoCity
        self.photoCountry = photoCountry
    }
}
