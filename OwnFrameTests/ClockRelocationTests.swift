//
//  ClockRelocationTests.swift
//  OwnFrameTests
//
//  510 / FR-510-03, issue #26: the picker honoured an `occupied` set and had a green test,
//  but the sole production call site passed `occupied: []` — the caption exclusion never
//  happened in the shipping app. These tests pin the WIRING the picker test could not: the
//  occupied set the app actually derives, and the verbatim passthrough of the picker inputs
//  the cadence and never-repeat clauses ride on. The picker's own behaviour stays covered in
//  ThemeKit; nothing here re-tests it.
//

import Foundation
import Testing
import ThemeKit
@testable import OwnFrame

private struct SpyPicker: RandomPlacePicking {
    var result: ClockPlace = .topLeading
    var seen: [(now: Duration, current: ClockPlace?, occupied: Set<ClockPlace>)] = []

    mutating func place(now: Duration, current: ClockPlace?, occupied: Set<ClockPlace>) -> ClockPlace {
        seen.append((now, current, occupied))
        return result
    }
}

// @covers FR-510-03
@MainActor
@Test func relocationWithDetailsEnabledExcludesTheCaptionPlace() throws {
    var relocation = ClockRelocation(picker: SpyPicker())

    let place = relocation.place(now: .seconds(0), current: nil, detailsEnabled: true)

    let spy = try #require(relocation.picker as? SpyPicker)
    #expect(spy.seen.count == 1)
    #expect(spy.seen.first?.occupied == [ClockRelocation.captionPlace])
    #expect(ClockRelocation.captionPlace == .topCenter)
    #expect(place == .topLeading)
}

// @covers FR-510-03
@MainActor
@Test func relocationWithDetailsDisabledLeavesEveryPlaceFree() throws {
    var relocation = ClockRelocation(picker: SpyPicker())

    _ = relocation.place(now: .seconds(0), current: nil, detailsEnabled: false)

    let spy = try #require(relocation.picker as? SpyPicker)
    #expect(spy.seen.first?.occupied == [])
}

// @covers FR-510-03
@MainActor
@Test func relocationForwardsNowAndCurrentToThePickerVerbatim() throws {
    var relocation = ClockRelocation(picker: SpyPicker())

    _ = relocation.place(now: .seconds(360), current: .bottomLeading, detailsEnabled: true)

    let spy = try #require(relocation.picker as? SpyPicker)
    #expect(spy.seen.first?.now == .seconds(360))
    #expect(spy.seen.first?.current == .bottomLeading)
}
