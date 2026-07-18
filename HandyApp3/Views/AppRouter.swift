import SwiftUI

/// Identifies the top-level tabs so one tab can steer the selection of another.
enum AppTab: Hashable {
    case home, assets, categories, tools, preferences
}

enum ToolsAction: Hashable {
    case export
}

/// Lightweight cross-tab navigation state. Lets one tab drive another — e.g. the
/// Categories tab sends the user to the Assets tab focused on a specific category.
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home

    /// When non-nil, the Assets tab switches to "All", scrolls that category into
    /// view, and flashes a highlighted border around it. The Assets tab clears this
    /// back to nil after a brief pause, so it reads as a confirmation cue rather than
    /// a persistent selection.
    var focusedCategoryID: UUID?

    /// When non-nil, the Assets tab pushes that asset's detail screen (set when the
    /// user taps a recurrence notification). Cleared back to nil on dismiss by the
    /// navigation binding.
    var pendingAssetID: UUID?

    /// When non-nil, ToolsTab consumes this action (e.g. trigger export), then resets to nil.
    var pendingToolsAction: ToolsAction?
}
