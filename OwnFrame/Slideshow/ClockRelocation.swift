//
//  ClockRelocation.swift
//  OwnFrame
//
//  510 / FR-510-03: a Random clock must never land on the caption's place. The picker
//  (ThemeKit) honours whatever `occupied` set it is handed — deriving that set is app
//  knowledge, because the caption (PhotoInfoView) is chrome-coupled and its place is a
//  layout fact of SlideshowChrome. Issue #26: the call site used to hardcode
//  `occupied: []`, so the exclusion never happened in the shipping app. Owning the
//  derivation here, behind the same call the view uses, is what makes the wiring testable.
//

import ThemeKit

/// The FR-510-03 wiring for a `.random` clock: forwards a relocation request to the
/// injected picker with the caption's place excluded while photo details are enabled.
/// (With details off, Random may use all fixed places — 510 spec, edge cases.)
struct ClockRelocation {
    var picker: any RandomPlacePicking

    /// Where the caption card renders: PhotoInfoView is laid out centered under the
    /// chrome's top bar, so an enabled caption occupies `.topCenter`.
    static let captionPlace: ClockPlace = .topCenter

    mutating func place(now: Duration, current: ClockPlace?, detailsEnabled: Bool) -> ClockPlace {
        picker.place(
            now: now,
            current: current,
            occupied: detailsEnabled ? [Self.captionPlace] : []
        )
    }
}
