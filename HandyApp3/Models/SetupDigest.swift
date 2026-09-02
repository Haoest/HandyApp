import Foundation

/// The plan card at the top of Setup.
struct PlanSummary: Equatable {
    /// Small uppercase label above the title.
    let kicker: String
    let title: String
    let body: String
    let callToAction: String
    /// True when the card should offer the paywall rather than App Store purchase management.
    let offersUpgrade: Bool
}

/// Pure text rules for the Setup screen, kept out of the view so the free-tier wording is
/// unit-testable and stays in step with `PurchaseManager`'s actual limits.
///
/// The design bundle quoted free-tier numbers ("12 things and 40 records", elsewhere "6 things
/// and 20 records") that match neither each other nor the app. The shipped limits win: whatever
/// `PurchaseManager.freeAssetLimit` and friends say is what the card reports.
enum SetupDigest {

    static func plan(isFullVersion: Bool, assetCount: Int,
                     assetLimit: Int, recordLimit: Int) -> PlanSummary {
        guard !isFullVersion else {
            return PlanSummary(
                kicker: String(localized: "Your plan", bundle: .appPreferred, locale: .appPreferred),
                title: String(localized: "Full version", bundle: .appPreferred, locale: .appPreferred),
                body: String(localized: "Unlimited things and records. Thanks for buying.", bundle: .appPreferred, locale: .appPreferred),
                callToAction: String(localized: "Restore purchase", bundle: .appPreferred, locale: .appPreferred),
                offersUpgrade: false
            )
        }
        return PlanSummary(
            kicker: String(localized: "Free tier", bundle: .appPreferred, locale: .appPreferred),
            title: String(localized: "\(assetCount) of \(assetLimit) things used", bundle: .appPreferred, locale: .appPreferred),
            body: String(localized: "One payment lifts every limit. The free tier holds \(assetLimit) things, and \(recordLimit) events and transactions on each.", bundle: .appPreferred, locale: .appPreferred),
            callToAction: String(localized: "See the full version", bundle: .appPreferred, locale: .appPreferred),
            offersUpgrade: true
        )
    }

}
