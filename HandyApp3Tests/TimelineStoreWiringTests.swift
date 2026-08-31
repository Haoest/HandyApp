import XCTest
@testable import HandyApp3

/// End-to-end cover for the path the Timeline tab actually walks: real store records →
/// `TimelineSource` → `TimelineDigest`. The unit tests in `TimelineDigestTests` construct
/// records directly, so they would not catch a record that never reaches the digest because
/// of how the store or the edit sheet stores it.
@MainActor
final class TimelineStoreWiringTests: XCTestCase {

    private func makeStore() throws -> (AssetStore, UUID) {
        let store = AssetStore()
        store.seedBuiltInComboLists()
        store.seedBuiltInCategories()
        let categoryID = try XCTUnwrap(store.allCategories.first?.id)
        let asset = try store.createAsset(name: "Maple St House", categoryID: categoryID)
        return (store, asset.id)
    }

    private func sources(_ store: AssetStore) -> [TimelineSource] {
        store.allAssets.map {
            TimelineSource(assetID: $0.id, assetName: $0.name, events: $0.liveEvents, transactions: $0.liveTransactions)
        }
    }

    private func summary(_ store: AssetStore) -> TimelineSummary {
        let sources = sources(store)
        return TimelineDigest.summary(from: TimelineDigest.items(sources: sources), sources: sources)
    }

    /// A transaction saved with a due date inside the horizon reaches the digest and moves the
    /// net — even when it is further out than its own lead time, so "Due soon" stays quiet. The
    /// two figures are deliberately keyed to different sets; this is the wiring cover for that.
    func testWatchedTransactionOutsideItsLeadTimeNetsButIsNotDueSoon() throws {
        let (store, assetID) = try makeStore()
        let due = Date().addingTimeInterval(10 * 86_400)
        try store.addTransaction(details: "Property tax", amount: 2480, date: Date(), kind: .expense,
                                 payeeContactID: nil, notes: "", recurrence: nil,
                                 due: DueSettings(dueDate: due), toAssetID: assetID)

        // 10 days out against the default 7-day lead, but dated today.
        let summary = summary(store)
        XCTAssertEqual(summary.upcomingCount, 0)
        XCTAssertEqual(summary.recentCashFlow, -2480)
    }

    /// A record with no due date is invisible to everything driven by due dates — no timeline
    /// row, neither count — yet it is still money that moved, so cash flow counts it. This is
    /// the case the old due-date-gated net got wrong.
    func testTransactionWithoutDueDateIsInvisibleToTheTimelineButCountsAsCashFlow() throws {
        let (store, assetID) = try makeStore()
        try store.addTransaction(details: "Fuel", amount: 86.40, date: Date(), kind: .expense,
                                 payeeContactID: nil, notes: "", recurrence: nil,
                                 due: DueSettings(), toAssetID: assetID)

        XCTAssertTrue(TimelineDigest.items(sources: sources(store)).isEmpty)
        let summary = summary(store)
        XCTAssertEqual(summary.overdueCount, 0)
        XCTAssertEqual(summary.upcomingCount, 0)
        XCTAssertEqual(summary.recentCashFlow, -86.40)
    }

    /// Overdue money is counted by Overdue and, because it was paid three days ago, by cash
    /// flow too. The old net excluded overdue entirely — a bill two days late vanished from it.
    func testOverdueMoneyIsCountedAndStillFlows() throws {
        let (store, assetID) = try makeStore()
        let threeDaysAgo = Date().addingTimeInterval(-3 * 86_400)
        try store.addTransaction(details: "Late bill", amount: 500, date: threeDaysAgo, kind: .expense,
                                 payeeContactID: nil, notes: "", recurrence: nil,
                                 due: DueSettings(dueDate: threeDaysAgo), toAssetID: assetID)

        let summary = summary(store)
        XCTAssertEqual(summary.overdueCount, 1)
        XCTAssertEqual(summary.upcomingCount, 0)
        XCTAssertEqual(summary.recentCashFlow, -500)
    }

    /// The window has a far edge: a transaction older than `horizonDays` drops out even though
    /// the record is perfectly live, and it takes its peek row with it.
    func testTransactionOlderThanTheWindowDoesNotFlow() throws {
        let (store, assetID) = try makeStore()
        let longAgo = Date().addingTimeInterval(-45 * 86_400)
        try store.addTransaction(details: "Old repair", amount: 900, date: longAgo, kind: .expense,
                                 payeeContactID: nil, notes: "", recurrence: nil,
                                 due: DueSettings(), toAssetID: assetID)

        XCTAssertEqual(summary(store).recentCashFlow, 0)
        XCTAssertTrue(TimelineDigest.cashFlowEntries(sources: sources(store)).isEmpty)
    }

    /// A soft-deleted asset takes its transactions out of the figure with it — `allAssets`
    /// already filters it, which is why the digest does no liveness checking of its own.
    func testDeletedAssetsTransactionsStopFlowing() throws {
        let (store, assetID) = try makeStore()
        try store.addTransaction(details: "Paint", amount: 300, date: Date(), kind: .expense,
                                 payeeContactID: nil, notes: "", recurrence: nil,
                                 due: DueSettings(), toAssetID: assetID)
        XCTAssertEqual(summary(store).recentCashFlow, -300)

        try store.softDeleteAsset(id: assetID)
        XCTAssertEqual(summary(store).recentCashFlow, 0)
    }

    /// Income and expense net against each other rather than one direction winning — and at
    /// 5 days out both sit inside the default 7-day lead, so both are also counted as due soon.
    func testIncomeAndExpenseNetTogether() throws {
        let (store, assetID) = try makeStore()
        let soon = Date().addingTimeInterval(5 * 86_400)
        try store.addTransaction(details: "Paycheck", amount: 3100, date: Date(), kind: .income,
                                 payeeContactID: nil, notes: "", recurrence: nil,
                                 due: DueSettings(dueDate: soon), toAssetID: assetID)
        try store.addTransaction(details: "Insurance", amount: 1140, date: Date(), kind: .expense,
                                 payeeContactID: nil, notes: "", recurrence: nil,
                                 due: DueSettings(dueDate: soon), toAssetID: assetID)

        let summary = summary(store)
        XCTAssertEqual(summary.upcomingCount, 2)
        XCTAssertEqual(summary.recentCashFlow, 1960)
    }

    /// A freshly seeded install has no events or transactions at all, so every figure is zero —
    /// which is what an untouched app shows on first launch.
    func testFreshSeedHasNothingWatched() throws {
        let store = AssetStore()
        store.seedBuiltInComboLists()
        store.seedBuiltInCategories()
        store.seedBuiltInAssets()
        store.seedSampleAutomobile()

        let summary = summary(store)
        XCTAssertEqual(summary.overdueCount, 0)
        XCTAssertEqual(summary.upcomingCount, 0)
        XCTAssertEqual(summary.recentCashFlow, 0)
    }
}
