import SwiftUI

/// Tracks the on-screen (global) vertical extent of content rows so the asset-paging gesture
/// can stand down for drags that start on them: paging is meant to fire only on the form's
/// blank areas (section gaps, headers, empty placeholders), while a swipe that lands on
/// an element — a property, the photo carousel, an event/transaction row — belongs to
/// that element (its own swipe-to-delete, scroll, or nothing) and must not page. Rows
/// write their bands here directly rather than via a `PreferenceKey`, because
/// `List`/`Form` cells don't reliably propagate preferences up to the screen that hosts
/// the paging gesture.
@Observable
final class SwipeableRowRegistry {
    /// `@ObservationIgnored` on purpose: nothing reads this from a view body — `contains` is
    /// called only from the paging gesture's callbacks — so per-write observation bookkeeping
    /// would be pure cost on a very hot path. Every row re-registers on every layout pass, and
    /// a keyboard presentation re-lays the whole form once per animation frame.
    @ObservationIgnored private var bands: [String: RowBand] = [:]

    /// Records (or, with a nil band, forgets) one row's vertical extent.
    func setBand(_ band: RowBand?, for id: String) {
        if let band {
            guard bands[id] != band else { return }
            bands[id] = band
        } else {
            bands.removeValue(forKey: id)
        }
    }

    /// True when `point` (in global coordinates) falls on any registered row.
    ///
    /// Deliberately a vertical-band test rather than full rect containment: rows are
    /// full-width `Form` cells, and while a row's swipe action is being revealed `List`
    /// translates the cell — and with it the frame recorded above — horizontally. Testing
    /// `x` too would make a row stop matching its own drag once it had slid far enough
    /// that its trailing edge passed the finger, handing a deep swipe-to-delete back to
    /// the paging gesture. `y` doesn't move, so it alone identifies the row.
    func contains(_ point: CGPoint) -> Bool {
        bands.values.contains { point.y >= $0.minY && point.y <= $0.maxY }
    }
}

/// A row's vertical extent in global coordinates, rounded to whole points so the sub-pixel
/// drift of an in-flight scroll or keyboard animation doesn't count as a change.
struct RowBand: Equatable {
    let minY: CGFloat
    let maxY: CGFloat

    init(_ frame: CGRect) {
        minY = frame.minY.rounded()
        maxY = frame.maxY.rounded()
    }
}

private struct PagingExcludedRow: ViewModifier {
    @Environment(SwipeableRowRegistry.self) private var registry
    let id: String

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                record(geo.frame(in: .global))
                    .onDisappear { registry.setBand(nil, for: id) }
            }
        )
    }

    /// Registers the row's current band as a side effect of the layout read, rather than
    /// through an `onChange(of:)` attached to a child view. That keeps this to one dictionary
    /// write per row per layout pass instead of an extra comparison attribute in the view
    /// graph for every row on screen — and a keyboard presentation re-lays the whole form
    /// once per animation frame, so those add up. Writing here cannot cause a re-render: the
    /// registry holds its bands `@ObservationIgnored` and no view body reads them.
    private func record(_ frame: CGRect) -> some View {
        registry.setBand(RowBand(frame), for: id)
        return Color.clear
    }
}

extension View {
    /// Marks a content row that should consume its own swipes instead of paging the asset.
    /// The detail screen reads these bands and suppresses paging for drags that start
    /// inside them, so paging is left to the form's blank areas.
    func pagingExcludedRow(id: String) -> some View {
        modifier(PagingExcludedRow(id: id))
    }
}

/// One drag's paging verdict, held from the drag's first event to its last so a moving
/// or changing `SwipeableRowRegistry` can't flip it partway through. `start` identifies
/// the drag it was taken for.
struct SuppressionLatch: Equatable {
    let start: CGPoint
    let suppressed: Bool
}
