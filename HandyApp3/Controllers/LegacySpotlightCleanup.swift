import CoreSpotlight
import Foundation
import os

protocol SpotlightDomainDeleting {
    func deleteSearchableItems(withDomainIdentifiers domainIdentifiers: [String]) async throws
}

extension CSSearchableIndex: SpotlightDomainDeleting {}

/// Removes asset records indexed by builds that predate the decision to keep user data out of
/// system search. The completion flag is written only after Core Spotlight accepts the delete,
/// so a transient failure is retried on the next launch.
final class LegacySpotlightCleanup {
    static let shared = LegacySpotlightCleanup()
    static let domainIdentifier = "haoest.HandyApp3.asset"
    static let completionKey = "migration.removedLegacySpotlightAssetIndex.v1"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "HandyApp3",
        category: "Privacy"
    )

    private let index: any SpotlightDomainDeleting
    private let defaults: UserDefaults

    init(
        index: any SpotlightDomainDeleting = CSSearchableIndex.default(),
        defaults: UserDefaults = .standard
    ) {
        self.index = index
        self.defaults = defaults
    }

    func runIfNeeded() async {
        guard !defaults.bool(forKey: Self.completionKey) else { return }
        do {
            try await index.deleteSearchableItems(
                withDomainIdentifiers: [Self.domainIdentifier]
            )
            defaults.set(true, forKey: Self.completionKey)
        } catch {
            Self.logger.error(
                "Couldn't remove the legacy asset Spotlight index; will retry next launch: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
