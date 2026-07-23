//
//  FrameStateEntity.swift
//  OwnFrame
//
//  800 (T024): the transient result entity of Get Frame State — a field-for-field
//  mirror of the package's FrameStateSnapshot, nothing more (the six-property
//  whitelist is structural in the snapshot and pinned by SC-800-04; this type
//  must never grow a field the snapshot doesn't have).
//

import AppIntents
import AppIntentsKit

struct FrameStateEntity: TransientAppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Frame State"

    @Property(title: "Is Playing")
    var isPlaying: Bool

    @Property(title: "Brightness Percent")
    var brightnessPercent: Int

    @Property(title: "Source")
    var sourceLabel: String?

    @Property(title: "Photo Date")
    var photoDate: Date?

    @Property(title: "Photo City")
    var photoCity: String?

    @Property(title: "Photo Country")
    var photoCountry: String?

    var displayRepresentation: DisplayRepresentation {
        // The status word is localized on its own so Siri and the Shortcuts result
        // read it in the device language; the "%@ · %lld%%" frame is localized too.
        let status: LocalizedStringResource = isPlaying ? "Playing" : "Paused"
        return DisplayRepresentation(
            title: "\(String(localized: status)) · \(brightnessPercent)%",
            subtitle: sourceLabel.map { "\($0)" }
        )
    }

    init() {}

    init(_ snapshot: FrameStateSnapshot) {
        self.init()
        isPlaying = snapshot.isPlaying
        brightnessPercent = snapshot.brightnessPercent
        sourceLabel = snapshot.sourceLabel
        photoDate = snapshot.photoDate
        photoCity = snapshot.photoCity
        photoCountry = snapshot.photoCountry
    }
}
