//
//  RotationReconciler.swift
//  SlideshowKit
//
//  310 — the pure diff between the playing asset list and a freshly fetched one
//  (FR-310-07/08). Sequential rebuilds the identity order anchored on the
//  current photo; shuffle preserves the running cycle (played prefix stays
//  played, survivors keep relative order) and folds additions into the unplayed
//  remainder only — no mid-cycle reshuffle, every photo once per cycle
//  (FR-300-05). The output is always a full permutation of the new list, so the
//  engine's count-guard never triggers a surprise rebuild after a refresh.
//

import Foundation
import PhotoSourceKit
import ThemeKit

public enum RotationReconciler {
    /// Merge a freshly fetched asset list into the running rotation. Returns
    /// the new play order and the cursor position that preserves the current
    /// photo — or, when the current photo was removed server-side, the slot
    /// just before its successor so the next advance shows that successor
    /// (FR-310-08, SC-310-03).
    public static func reconcile(
        oldAssets: [SourceAsset], newAssets: [SourceAsset],
        playOrder: [Int], cursor: Int,
        order: PlayOrder, currentAssetID: String?,
        rng: inout some RandomNumberGenerator
    ) -> (playOrder: [Int], cursor: Int) {
        guard !newAssets.isEmpty else {
            return ([], 0)
        }

        // Strict no-op on an identical list: no reshuffle, no cursor movement,
        // no visible effect (refresh-returns-same-list edge case).
        if newAssets.map(\.id) == oldAssets.map(\.id) {
            return (playOrder, cursor)
        }

        let newIndexByID = Dictionary(
            newAssets.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )

        switch order {
        case .sequential:
            return reconcileSequential(
                oldAssets: oldAssets, newAssets: newAssets,
                currentAssetID: currentAssetID, newIndexByID: newIndexByID
            )
        case .shuffle:
            return reconcileShuffle(
                oldAssets: oldAssets, newAssets: newAssets,
                playOrder: playOrder, cursor: cursor,
                currentAssetID: currentAssetID, newIndexByID: newIndexByID,
                rng: &rng
            )
        }
    }

    // MARK: - Sequential: identity order, anchored cursor

    private static func reconcileSequential(
        oldAssets: [SourceAsset], newAssets: [SourceAsset],
        currentAssetID: String?, newIndexByID: [String: Int]
    ) -> (playOrder: [Int], cursor: Int) {
        let identity = Array(newAssets.indices)

        guard let currentID = currentAssetID else {
            return (identity, 0)
        }
        if let position = newIndexByID[currentID] {
            return (identity, position)
        }

        // Current photo removed: park before its album-order successor so the
        // next advance shows it; with no surviving successor, park at the end
        // and let the advance wrap into a new cycle — as it would have anyway.
        guard let oldPosition = oldAssets.firstIndex(where: { $0.id == currentID }) else {
            return (identity, 0)
        }
        for index in (oldPosition + 1)..<oldAssets.count {
            if let successor = newIndexByID[oldAssets[index].id] {
                let count = identity.count
                return (identity, (successor - 1 + count) % count)
            }
        }
        return (identity, identity.count - 1)
    }

    // MARK: - Shuffle: preserve the cycle, additions in the remainder only

    private static func reconcileShuffle(
        oldAssets: [SourceAsset], newAssets: [SourceAsset],
        playOrder: [Int], cursor: Int,
        currentAssetID: String?, newIndexByID: [String: Int],
        rng: inout some RandomNumberGenerator
    ) -> (playOrder: [Int], cursor: Int) {
        // Remap the old cycle onto new-list indices, dropping removed assets
        // and tracking where the cursor lands.
        var survivors: [Int] = []
        var cursorPosition: Int?
        for (position, oldIndex) in playOrder.enumerated() {
            guard oldIndex < oldAssets.count else {
                continue
            }
            if let newIndex = newIndexByID[oldAssets[oldIndex].id] {
                survivors.append(newIndex)
                if position == cursor {
                    cursorPosition = survivors.count - 1
                }
            } else if position == cursor {
                // Current removed: the slot before its surviving successor.
                cursorPosition = survivors.count - 1
            }
        }

        // No running cycle to preserve (refill from empty): a fresh shuffle.
        if survivors.isEmpty && cursorPosition == nil {
            var indices = Array(newAssets.indices)
            indices.shuffle(using: &rng)
            return (indices, 0)
        }

        var newCursor = cursorPosition ?? 0

        // Additions join the unplayed remainder at rng-chosen slots — strictly
        // after the cursor, so the played prefix and the current photo's slot
        // stay untouched (FR-310-07).
        let oldIDs = Set(oldAssets.map(\.id))
        var result = survivors
        for (offset, asset) in newAssets.enumerated() where !oldIDs.contains(asset.id) {
            let lower = max(newCursor + 1, 0)
            let position = Int.random(in: lower...result.count, using: &rng)
            result.insert(offset, at: position)
        }

        // Corner: the removed current had no surviving predecessor either
        // (cursorPosition == -1). Park at the cycle's end so the next advance
        // wraps into a fresh cycle instead of leaving an invalid cursor.
        if newCursor < 0 {
            newCursor = result.count - 1
        }
        return (result, newCursor)
    }
}
