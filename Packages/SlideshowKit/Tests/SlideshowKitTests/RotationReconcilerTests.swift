//
//  RotationReconcilerTests.swift
//  SlideshowKitTests
//
//  310, T011 — the pure rotation diff (FR-310-07/08, SC-310-02/03). The six
//  data-model invariants: full permutation, identical-list no-op, sequential
//  anchor, shuffle cycle preservation with additions only in the unplayed
//  remainder, and the removed-current cursor rule.
//

import Foundation
import ImmichClient
import Testing
import ThemeKit
@testable import SlideshowKit

private func asset(_ id: String) -> Asset {
    Asset(id: id, type: "IMAGE")
}

private func assets(_ ids: String...) -> [Asset] {
    ids.map(asset)
}

/// IDs in play sequence, mapped through the play order.
private func sequence(of playOrder: [Int], in list: [Asset]) -> [String] {
    playOrder.map { list[$0].id }
}

@Suite("RotationReconciler")
struct RotationReconcilerTests {
    // MARK: Invariant 1 — full permutation of the new list, always

    @Test func outputIsAlwaysAFullPermutationOfTheNewList() {
        var rng = SeededRandomNumberGenerator(seed: 1)
        let old = assets("a", "b", "c")
        let new = assets("b", "d", "e", "a")

        let result = RotationReconciler.reconcile(
            oldAssets: old, newAssets: new,
            playOrder: [2, 0, 1], cursor: 1,
            order: .shuffle, currentAssetID: "a", rng: &rng
        )

        #expect(result.playOrder.sorted() == Array(new.indices))
        #expect(result.cursor >= 0 && result.cursor < new.count)
    }

    // MARK: Invariant 2 — identical lists are a strict no-op

    @Test(arguments: [PlayOrder.sequential, PlayOrder.shuffle])
    func identicalListsReturnInputsUnchanged(order: PlayOrder) {
        var rng = SeededRandomNumberGenerator(seed: 2)
        let list = assets("a", "b", "c", "d")
        let playOrder = order == .sequential ? [0, 1, 2, 3] : [2, 0, 3, 1]

        let result = RotationReconciler.reconcile(
            oldAssets: list, newAssets: list,
            playOrder: playOrder, cursor: 2,
            order: order, currentAssetID: list[playOrder[2]].id, rng: &rng
        )

        #expect(result.playOrder == playOrder)
        #expect(result.cursor == 2)
    }

    // MARK: Invariant 3 — sequential: identity order, cursor anchored

    @Test func sequentialAdditionAppearsAtItsAlbumPosition() {
        var rng = SeededRandomNumberGenerator(seed: 3)
        let old = assets("a", "c")
        let new = assets("a", "b", "c")   // b inserted at album position 1

        let result = RotationReconciler.reconcile(
            oldAssets: old, newAssets: new,
            playOrder: [0, 1], cursor: 0,
            order: .sequential, currentAssetID: "a", rng: &rng
        )

        #expect(result.playOrder == [0, 1, 2])
        #expect(result.cursor == 0)   // still on "a"
        #expect(sequence(of: result.playOrder, in: new) == ["a", "b", "c"])
    }

    @Test func sequentialAdditionBeforeTheCurrentKeepsTheCursorOnTheCurrentPhoto() {
        var rng = SeededRandomNumberGenerator(seed: 4)
        let old = assets("b", "c")
        let new = assets("a", "b", "c")   // a prepended

        let result = RotationReconciler.reconcile(
            oldAssets: old, newAssets: new,
            playOrder: [0, 1], cursor: 0,
            order: .sequential, currentAssetID: "b", rng: &rng
        )

        #expect(result.playOrder == [0, 1, 2])
        #expect(result.cursor == 1)   // "b" moved to album position 1
    }

    @Test func sequentialRemovalBeforeTheCurrentKeepsTheCursorOnTheCurrentPhoto() {
        var rng = SeededRandomNumberGenerator(seed: 5)
        let old = assets("a", "b", "c")
        let new = assets("b", "c")   // a removed; current is b

        let result = RotationReconciler.reconcile(
            oldAssets: old, newAssets: new,
            playOrder: [0, 1, 2], cursor: 1,
            order: .sequential, currentAssetID: "b", rng: &rng
        )

        #expect(result.playOrder == [0, 1])
        #expect(result.cursor == 0)   // "b" is now first
    }

    // MARK: Invariant 4 — shuffle: cycle preserved, additions in the remainder only

    @Test func shuffleSurvivorsKeepTheirRelativeOrder() {
        var rng = SeededRandomNumberGenerator(seed: 6)
        let old = assets("a", "b", "c", "d", "e")
        // Cycle: c a e b d, cursor on e (position 2): played c a e, pending b d.
        let new = assets("a", "c", "d", "e")   // b removed

        let result = RotationReconciler.reconcile(
            oldAssets: old, newAssets: new,
            playOrder: [2, 0, 4, 1, 3], cursor: 2,
            order: .shuffle, currentAssetID: "e", rng: &rng
        )

        // b drops out; survivors keep the exact cycle order c a e d.
        #expect(sequence(of: result.playOrder, in: new) == ["c", "a", "e", "d"])
        #expect(result.cursor == 2)   // still on e
    }

    @Test func shuffleAdditionsJoinOnlyTheUnplayedRemainder() {
        var rng = SeededRandomNumberGenerator(seed: 7)
        let old = assets("a", "b", "c", "d")
        // Cycle: b d a c, cursor on d (position 1): played b d, pending a c.
        let new = assets("a", "b", "c", "d", "x", "y")

        let result = RotationReconciler.reconcile(
            oldAssets: old, newAssets: new,
            playOrder: [1, 3, 0, 2], cursor: 1,
            order: .shuffle, currentAssetID: "d", rng: &rng
        )

        let ids = sequence(of: result.playOrder, in: new)
        // Played prefix untouched…
        #expect(Array(ids.prefix(2)) == ["b", "d"])
        #expect(result.cursor == 1)
        // …additions only after the cursor, survivors a/c keep relative order.
        let remainder = Array(ids.dropFirst(2))
        #expect(remainder.filter { $0 == "x" }.count == 1)
        #expect(remainder.filter { $0 == "y" }.count == 1)
        let survivorsInRemainder = remainder.filter { ["a", "c"].contains($0) }
        #expect(survivorsInRemainder == ["a", "c"])
        // Exactly once per cycle overall (FR-300-05 invariant).
        #expect(Set(ids).count == new.count)
    }

    @Test func shuffleAdditionAtCycleEndFormsTheNewRemainder() {
        var rng = SeededRandomNumberGenerator(seed: 8)
        let old = assets("a", "b")
        // Cursor at the last position: the cycle was about to wrap.
        let new = assets("a", "b", "x")

        let result = RotationReconciler.reconcile(
            oldAssets: old, newAssets: new,
            playOrder: [1, 0], cursor: 1,
            order: .shuffle, currentAssetID: "a", rng: &rng
        )

        let ids = sequence(of: result.playOrder, in: new)
        #expect(Array(ids.prefix(2)) == ["b", "a"])
        #expect(ids.last == "x")      // only slot after the cursor
        #expect(result.cursor == 1)   // still on a; x plays before the wrap
    }

    // MARK: Invariant 5/6 — removed current photo

    @Test func removedCurrentLandsTheCursorBeforeItsSuccessor() {
        var rng = SeededRandomNumberGenerator(seed: 9)
        let old = assets("a", "b", "c", "d")
        // Cycle: a b c d, cursor on b; b is removed server-side.
        let new = assets("a", "c", "d")

        let result = RotationReconciler.reconcile(
            oldAssets: old, newAssets: new,
            playOrder: [0, 1, 2, 3], cursor: 1,
            order: .sequential, currentAssetID: "b", rng: &rng
        )

        // Next advance must show c (b's successor).
        #expect(result.playOrder == [0, 1, 2])
        #expect(result.cursor == 0)
        let next = result.playOrder[(result.cursor + 1) % result.playOrder.count]
        #expect(new[next].id == "c")
    }

    @Test func removedCurrentInShuffleShowsItsCycleSuccessorNext() {
        var rng = SeededRandomNumberGenerator(seed: 10)
        let old = assets("a", "b", "c", "d")
        // Cycle: d b a c, cursor on b; b removed. Successor in the cycle is a.
        let new = assets("a", "c", "d")

        let result = RotationReconciler.reconcile(
            oldAssets: old, newAssets: new,
            playOrder: [3, 1, 0, 2], cursor: 1,
            order: .shuffle, currentAssetID: "b", rng: &rng
        )

        #expect(sequence(of: result.playOrder, in: new) == ["d", "a", "c"])
        let next = result.playOrder[(result.cursor + 1) % result.playOrder.count]
        #expect(new[next].id == "a")
    }

    @Test func removedCurrentAtCycleEndWrapsIntoANewCycle() {
        var rng = SeededRandomNumberGenerator(seed: 11)
        let old = assets("a", "b", "c")
        // Cursor on the cycle's last photo c; c removed.
        let new = assets("a", "b")

        let result = RotationReconciler.reconcile(
            oldAssets: old, newAssets: new,
            playOrder: [0, 1, 2], cursor: 2,
            order: .sequential, currentAssetID: "c", rng: &rng
        )

        // Cursor parks at the end; the next advance wraps — as it would have.
        #expect(result.playOrder == [0, 1])
        #expect(result.cursor == result.playOrder.count - 1)
    }

    @Test func disjointListsRebuildFromScratch() {
        var rng = SeededRandomNumberGenerator(seed: 12)
        let old = assets("a", "b")
        let new = assets("x", "y", "z")

        let result = RotationReconciler.reconcile(
            oldAssets: old, newAssets: new,
            playOrder: [1, 0], cursor: 0,
            order: .shuffle, currentAssetID: "b", rng: &rng
        )

        #expect(result.playOrder.sorted() == Array(new.indices))
        #expect(result.cursor >= 0 && result.cursor < new.count)
    }

    // MARK: Invariant 7 — graceful degenerate inputs

    @Test func nilCurrentAssetFallsBackToCursorZero() {
        var rng = SeededRandomNumberGenerator(seed: 13)
        let old = assets("a", "b")
        let new = assets("a", "b", "c")

        let result = RotationReconciler.reconcile(
            oldAssets: old, newAssets: new,
            playOrder: [0, 1], cursor: 0,
            order: .sequential, currentAssetID: nil, rng: &rng
        )

        #expect(result.playOrder == [0, 1, 2])
        #expect(result.cursor == 0)
    }

    @Test func emptyNewListDegradesGracefully() {
        var rng = SeededRandomNumberGenerator(seed: 14)
        let result = RotationReconciler.reconcile(
            oldAssets: assets("a"), newAssets: [],
            playOrder: [0], cursor: 0,
            order: .sequential, currentAssetID: "a", rng: &rng
        )

        #expect(result.playOrder.isEmpty)
        #expect(result.cursor == 0)
    }
}
