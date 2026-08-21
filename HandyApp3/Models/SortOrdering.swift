import Foundation

/// Rules for computing `AssetProperty.sortOrder` when a user reorders property rows (category
/// templates, an asset's base properties, or its custom properties).
///
/// The guiding choice is midpoint insertion, not renumbering: a move changes only the moved
/// row's `sortOrder`, placed strictly between its new neighbors. Two reasons this matters more
/// here than "just a nicety":
///
/// 1. `sortOrderIncrement` (10) gives a `Double` roughly 50 subdivisions of one slot before
///    adjacent values collide — far more than a person will reach by dragging.
/// 2. Cross-device merge (`SnapshotReconciler.joinAssetProperty`) is whole-record last-writer-
///    wins on `modifyDate`, with no timestamp of its own for `sortOrder`. Renumbering N rows
///    writes N records that a peer's concurrent edit can each partially revert; a midpoint move
///    writes one.
enum SortOrdering {
    static var increment: Double { AssetProperty.sortOrderIncrement }

    /// `sortOrder` values for `count` items landing, in order, strictly between `prev` and
    /// `next` (either or both `nil` at an end of the list). `nil` when the gap can't hold
    /// `count` strictly-between, strictly-increasing values — the caller should renormalize the
    /// whole section via `normalized(count:)` and place from that instead. This is also what
    /// self-heals today's all-zero-`sortOrder` custom properties: equal neighbors (`prev == next`
    /// as doubles) fail the `p < n` check below and fall through to renormalization on the first
    /// drag.
    static func values(count: Int, after prev: Double?, before next: Double?) -> [Double]? {
        guard count > 0 else { return [] }
        switch (prev, next) {
        case (nil, nil):
            return normalized(count: count)
        case (let p?, nil):
            return (1...count).map { p + increment * Double($0) }
        case (nil, let n?):
            return (0..<count).map { n - increment * Double(count - $0) }
        case (let p?, let n?):
            guard p < n else { return nil }
            let step = (n - p) / Double(count + 1)
            guard step > 0 else { return nil }
            let result = (1...count).map { p + step * Double($0) }
            guard let first = result.first, let last = result.last, first > p, last < n else { return nil }
            for i in 1..<result.count where result[i] <= result[i - 1] { return nil }
            return result
        }
    }

    /// The renormalized ladder: `0, increment, 2*increment, …`. Used as the fallback when
    /// `values(count:after:before:)` can't subdivide a gap, and to seed a brand-new list.
    static func normalized(count: Int) -> [Double] {
        (0..<count).map { Double($0) * increment }
    }

    /// One increment past the highest existing value — the "append at the end" rule shared by
    /// a new custom property and a new template property. `0` when `existing` is empty.
    static func next(after existing: [Double]) -> Double {
        (existing.max() ?? -increment) + increment
    }

    /// `(sortOrder, id)` — the same tie-break `AssetPropertyDTO.canonicalOrder` uses on disk.
    /// Every display site sorting a `[AssetProperty]` for on-screen order should use this, not
    /// a bare `sortOrder <` comparison, or tied rows (still possible mid-renormalization) render
    /// in an unstable order that a reorder can't compute correct neighbors against.
    static func precedes(_ a: AssetProperty, _ b: AssetProperty) -> Bool {
        a.sortOrder == b.sortOrder ? a.id.uuidString < b.id.uuidString : a.sortOrder < b.sortOrder
    }

    /// `RangeReplaceableCollection.move(fromOffsets:toOffset:)`'s own semantics, reimplemented
    /// against plain `Foundation`: that method is a SwiftUI extension, and `AssetStore` (where
    /// this is consumed) must stay free of SwiftUI/UIKit to keep compiling as part of the
    /// headless `swift test` package — see the package's own doc comment in `Package.swift`.
    static func moved<T>(_ elements: [T], fromOffsets: IndexSet, toOffset: Int) -> [T] {
        let moving = fromOffsets.map { elements[$0] }
        var result = elements
        for index in fromOffsets.sorted(by: >) {
            result.remove(at: index)
        }
        let removedBefore = fromOffsets.filter { $0 < toOffset }.count
        let insertionIndex = toOffset - removedBefore
        result.insert(contentsOf: moving, at: insertionIndex)
        return result
    }
}
