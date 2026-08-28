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

    /// A transaction saved with a due date inside the horizon reaches the digest and moves the net.
    func testWatchedTransactionReachesSummary() throws {
        let (store, assetID) = try makeStore()
        let due = Date().addingTimeInterval(10 * 86_400)
        try store.addTransaction(details: "Property tax", amount: 2480, date: Date(), kind: .expense,
                                 payeeContactID: nil, notes: "", recurrence: nil,
                                 due: DueSettings(dueDate: due), toAssetID: assetID)

        let summary = TimelineDigest.summary(from: TimelineDigest.items(sources: sources(store)))
        XCTAssertEqual(summary.upcomingCount, 1)
        XCTAssertEqual(summary.netAmount, -2480)
    }

    /// The common real-world reason the net reads zero: nothing has a due date, so nothing is
    /// watched. The record exists and is perfectly valid — it just isn't on the timeline.
    func testTransactionWithoutDueDateIsInvisibleToTheTimeline() throws {
        let (store, assetID) = try makeStore()
        try store.addTransaction(details: "Fuel", amount: 86.40, date: Date(), kind: .expense,
                                 payeeContactID: nil, notes: "", recurrence: nil,
                                 due: DueSettings(), toAssetID: assetID)

        let items = TimelineDigest.items(sources: sources(store))
        XCTAssertTrue(items.isEmpty)
        XCTAssertEqual(TimelineDigest.summary(from: items).netAmount, 0)
    }

    /// The other way the net reads zero while a pill above it shows a count: overdue money is
    /// counted by Overdue but deliberately excluded from the forward-looking net.
    func testOverdueMoneyIsCountedButNotNetted() throws {
        let (store, assetID) = try makeStore()
        let due = Date().addingTimeInterval(-3 * 86_400)
        try store.addTransaction(details: "Late bill", amount: 500, date: Date(), kind: .expense,
                                 payeeContactID: nil, notes: "", recurrence: nil,
                                 due: DueSettings(dueDate: due), toAssetID: assetID)

        let summary = TimelineDigest.summary(from: TimelineDigest.items(sources: sources(store)))
        XCTAssertEqual(summary.overdueCount, 1)
        XCTAssertEqual(summary.upcomingCount, 0)
        XCTAssertEqual(summary.netAmount, 0)
    }

    /// Income and expense net against each other rather than one direction winning.
    func testIncomeAndExpenseNetTogether() throws {
        let (store, assetID) = try makeStore()
        let soon = Date().addingTimeInterval(5 * 86_400)
        try store.addTransaction(details: "Paycheck", amount: 3100, date: Date(), kind: .income,
                                 payeeContactID: nil, notes: "", recurrence: nil,
                                 due: DueSettings(dueDate: soon), toAssetID: assetID)
        try store.addTransaction(details: "Insurance", amount: 1140, date: Date(), kind: .expense,
                                 payeeContactID: nil, notes: "", recurrence: nil,
                                 due: DueSettings(dueDate: soon), toAssetID: assetID)

        let summary = TimelineDigest.summary(from: TimelineDigest.items(sources: sources(store)))
        XCTAssertEqual(summary.upcomingCount, 2)
        XCTAssertEqual(summary.netAmount, 1960)
    }

    /// A freshly seeded install has no events or transactions at all, so every figure is zero —
    /// which is what an untouched app shows on first launch.
    func testFreshSeedHasNothingWatched() throws {
        let store = AssetStore()
        store.seedBuiltInComboLists()
        store.seedBuiltInCategories()
        store.seedBuiltInAssets()
        store.seedSampleAutomobile()

        let summary = TimelineDigest.summary(from: TimelineDigest.items(sources: sources(store)))
        XCTAssertEqual(summary.overdueCount, 0)
        XCTAssertEqual(summary.upcomingCount, 0)
        XCTAssertEqual(summary.netAmount, 0)
    }
}
