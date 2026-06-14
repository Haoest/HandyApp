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

    /// True when `point` (in global coordinates) lies inside any registered row.
    func contains(_ point: CGPoint) -> Bool {
        frames.values.contains { $0.contains(point) }
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
