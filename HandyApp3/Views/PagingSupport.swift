import SwiftUI

/// Tracks the on-screen (global) frames of content rows so the asset-paging gesture can
/// stand down for drags that start on them: paging is meant to fire only on the form's
/// blank areas (section gaps, headers, empty placeholders), while a swipe that lands on
/// an element — a property, the photo carousel, an event/transaction row — belongs to
/// that element (its own swipe-to-delete, scroll, or nothing) and must not page. Rows
/// write their frames here directly rather than via a `PreferenceKey`, because
/// `List`/`Form` cells don't reliably propagate preferences up to the screen that hosts
/// the paging gesture.
@Observable
final class SwipeableRowRegistry {
    var frames: [String: CGRect] = [:]

    /// True when `point` (in global coordinates) falls on any registered row.
    ///
    /// Deliberately a vertical-band test rather than full rect containment: rows are
    /// full-width `Form` cells, and while a row's swipe action is being revealed `List`
    /// translates the cell — and with it the frame recorded above — horizontally. Testing
    /// `x` too would make a row stop matching its own drag once it had slid far enough
    /// that its trailing edge passed the finger, handing a deep swipe-to-delete back to
    /// the paging gesture. `y` doesn't move, so it alone identifies the row.
    func contains(_ point: CGPoint) -> Bool {
        frames.values.contains { point.y >= $0.minY && point.y <= $0.maxY }
    }
}

private struct PagingExcludedRow: ViewModifier {
    @Environment(SwipeableRowRegistry.self) private var registry
    let id: String

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { registry.frames[id] = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, frame in
                        registry.frames[id] = frame
                    }
                    .onDisappear { registry.frames[id] = nil }
            }
        )
    }
}

extension View {
    /// Marks a content row that should consume its own swipes instead of paging the asset.
    /// The detail screen reads these frames and suppresses paging for drags that start
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
