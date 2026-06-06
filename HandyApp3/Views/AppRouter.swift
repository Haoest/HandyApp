import SwiftUI

/// Identifies the top-level tabs so one tab can steer the selection of another.
enum AppTab: Hashable {
    case home, assets, categories, activity, preferences
}

/// Lightweight cross-tab navigation state. Lets one tab drive another — e.g. the
/// Categories tab sends the user to the Assets tab focused on a specific category.
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home

    /// When non-nil, the Assets tab switches to "All", scrolls that category into
    /// view, and draws a highlighted border around it. Persists so the highlight
    /// reads as the current selection until another category is chosen.
    var focusedCategoryID: UUID?
}
