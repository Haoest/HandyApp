import XCTest
@testable import HandyApp3

final class SetupDigestTests: XCTestCase {

    // MARK: - Plan card

    func testFullVersionCardOffersNoUpgrade() {
        let plan = SetupDigest.plan(isFullVersion: true, assetCount: 40,
                                    assetLimit: 5, eventLimit: 5, transactionLimit: 5)
        XCTAssertFalse(plan.offersUpgrade)
        XCTAssertEqual(plan.title, "Full version")
    }

    func testFreeTierCardOffersUpgradeAndReportsUsage() {
        let plan = SetupDigest.plan(isFullVersion: false, assetCount: 3,
                                    assetLimit: 5, eventLimit: 5, transactionLimit: 5)
        XCTAssertTrue(plan.offersUpgrade)
        XCTAssertEqual(plan.title, "3 of 5 things used")
    }

    /// The design bundle quoted free-tier numbers that matched neither each other nor the app.
    /// The card must read from the shipped limits, whatever they are.
    func testFreeTierBodyQuotesTheLimitsItWasGiven() {
        let plan = SetupDigest.plan(isFullVersion: false, assetCount: 0,
                                    assetLimit: 12, eventLimit: 40, transactionLimit: 40)
        XCTAssertTrue(plan.body.contains("12"))
        XCTAssertTrue(plan.body.contains("40"))
    }

    func testFreeTierCardHandlesBeingAtTheLimit() {
        let plan = SetupDigest.plan(isFullVersion: false, assetCount: 5,
                                    assetLimit: 5, eventLimit: 5, transactionLimit: 5)
        XCTAssertEqual(plan.title, "5 of 5 things used")
        XCTAssertTrue(plan.offersUpgrade)
    }

}
