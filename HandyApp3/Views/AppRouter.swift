import SwiftUI

/// Identifies the top-level tabs so one tab can steer the selection of another.
///
/// `timeline` replaced the old `home` and `eventsTransactions` tabs, which the Baron Book
/// redesign merges into a single screen — see `TimelineTab`.
enum AppTab: Hashable {
    case timeline, assets, setup
}

enum ToolsAction: Hashable {
    case export
}

/// Lightweight cross-tab navigation state. Lets one tab drive another — e.g. the
/// Categories tab sends the user to the Assets tab focused on a specific category.
@Observable
final class AppRouter {
    var selectedTab: AppTab = .timeline

    /// When non-nil, the Assets tab switches to "All", scrolls that category into
    /// view, and flashes a highlighted border around it. The Assets tab clears this
    /// back to nil after a brief pause, so it reads as a confirmation cue rather than
    /// a persistent selection.
    var focusedCategoryID: UUID?

    /// When non-nil, the Assets tab pushes that asset's detail screen (set when the
    /// user taps a recurrence notification). Cleared back to nil on dismiss by the
    /// navigation binding.
    var pendingAssetID: UUID?

    /// Section to scroll the pushed asset detail screen to, alongside `pendingAssetID`
    /// (set when the user taps an event/transaction notification). Consumed and reset
    /// to nil once the destination view appears.
    var pendingAssetAnchor: DetailAnchor?

    /// When non-nil, SetupTab consumes this action (e.g. trigger export), then resets to nil.
    var pendingToolsAction: ToolsAction?

    /// When true, the Assets tab opens the new-asset creation sheet. Cleared after consumption.
    var pendingNewAsset: Bool = false

    /// When true, the Timeline tab opens the quick-log picker (`QuickLogStep.pickThing`),
    /// the same flow as its "+ Log" button. Set by `LogIntent`; cleared after consumption.
    var pendingQuickLog: Bool = false
}

/// Where a deep link from the activity log should land inside a thing. Finer-grained than
/// the four sub-tabs Thing detail actually has — `ThingSubTab.init(anchor:)` maps them down.
/// Lives here rather than with the detail screen because `AppRouter.pendingAssetAnchor` is
/// what carries it across the app.
enum DetailAnchor: String, CaseIterable {
    case category = "Category"
    case custom = "Custom"
    case photos = "Photos"
    case events = "Events"
    case transactions = "Transactions"
    case relationship = "Relationship"
    case contents = "What's inside"
}

extension DetailAnchor {
    var localizedName: LocalizedStringKey { LocalizedStringKey(rawValue) }
}
