import AppIntents

/// Spotlight/Siri entry point for the most frequent action: adding an event or a
/// transaction. Deliberately takes no parameters — resolving an `AssetEntity` up front
/// forced Siri into a spoken "Which thing?" disambiguation that bought nothing, since
/// `openAppWhenRun` opens the app regardless.
///
/// Hands off to the Timeline's existing quick-log flow (`QuickLogStep.pickThing`), the same
/// one behind its "+ Log" button: pick the thing, then the kind, then the edit sheet. That
/// picker is a far better disambiguator than Siri reading a list aloud.
struct LogIntent: AppIntent {
    static let title: LocalizedStringResource = "Log"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let deps = AppDependencies.shared
        deps.router.selectedTab = .timeline
        deps.router.pendingQuickLog = true
        return .result()
    }
}
