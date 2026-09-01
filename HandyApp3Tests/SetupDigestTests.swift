import XCTest
@testable import HandyApp3

final class SetupDigestTests: XCTestCase {

    // MARK: - Plan card

    func testFullVersionCardOffersNoUpgrade() {
        let plan = SetupDigest.plan(isFullVersion: true, assetCount: 40,
                                    assetLimit: 5, recordLimit: 12)
        XCTAssertFalse(plan.offersUpgrade)
        XCTAssertEqual(plan.title, "Full version")
    }

    func testFreeTierCardOffersUpgradeAndReportsUsage() {
        let plan = SetupDigest.plan(isFullVersion: false, assetCount: 3,
                                    assetLimit: 5, recordLimit: 12)
        XCTAssertTrue(plan.offersUpgrade)
        XCTAssertEqual(plan.title, "3 of 5 things used")
    }

    /// The design bundle quoted free-tier numbers that matched neither each other nor the app.
    /// The card must read from the shipped limits, whatever they are.
    func testFreeTierBodyQuotesTheLimitsItWasGiven() {
        let plan = SetupDigest.plan(isFullVersion: false, assetCount: 0,
                                    assetLimit: 9, recordLimit: 40)
        XCTAssertTrue(plan.body.contains("9"))
        XCTAssertTrue(plan.body.contains("40"))
    }

    func testFreeTierCardHandlesBeingAtTheLimit() {
        let plan = SetupDigest.plan(isFullVersion: false, assetCount: 5,
                                    assetLimit: 5, recordLimit: 12)
        XCTAssertEqual(plan.title, "5 of 5 things used")
        XCTAssertTrue(plan.offersUpgrade)
    }

}
