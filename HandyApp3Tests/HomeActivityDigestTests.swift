import XCTest
@testable import HandyApp3

final class HomeActivityDigestTests: XCTestCase {

    private let cal = Calendar.current

    /// A timestamp `daysAgo` days back at the given hour, anchored to today's start.
    private func date(_ daysAgo: Int, hour: Int = 12) -> Date {
        let base = cal.startOfDay(for: Date())
        let day = cal.date(byAdding: .day, value: -daysAgo, to: base)!
        return day.addingTimeInterval(TimeInterval(hour * 3600))
    }

    private func entry(_ kind: LoggedRecordKind, owner: UUID? = nil, at date: Date) -> ActivityLogEntry {
        ActivityLogEntry(recordID: UUID(), kind: kind, owningAssetID: owner, timestamp: date)
    }

    private func singles(_ rows: [HomeRow]) -> [ActivityLogEntry] {
        rows.compactMap { if case .single(let e) = $0 { return e } else { return nil } }
    }

    private func summaries(_ rows: [HomeRow]) -> [(kind: LoggedRecordKind, owner: UUID, count: Int)] {
        rows.compactMap {
            if case .summary(let kind, let owner, let count, _) = $0 { return (kind, owner, count) }
            return nil
        }
    }

    // MARK: - Day selection

    func testKeepsOnlyThreeMostRecentActiveDays() {
        let a = UUID()
        let entries = [
            entry(.transaction, owner: a, at: date(0)),
            entry(.transaction, owner: a, at: date(2)),
            entry(.transaction, owner: a, at: date(5)),
            entry(.transaction, owner: a, at: date(10)),
        ]
        let days = HomeActivityDigest.build(from: entries)
        XCTAssertEqual(days.map(\.day), [
            cal.startOfDay(for: date(0)),
            cal.startOfDay(for: date(2)),
            cal.startOfDay(for: date(5)),
        ])
        // Non-contiguous gaps (days 1,3,4) are skipped; the 10-days-ago day is dropped.
    }

    func testSingleEntryDaysAreStillIncluded() {
        let a = UUID()
        let days = HomeActivityDigest.build(from: [
            entry(.photo, owner: a, at: date(0)),
            entry(.event, owner: a, at: date(1)),
        ])
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days.allSatisfy { $0.rows.count == 1 }, true)
    }

    // MARK: - Per type/asset/day summarization

    func testTwoEntriesListedIndividually() {
        let a = UUID()
        let days = HomeActivityDigest.build(from: [
            entry(.transaction, owner: a, at: date(0, hour: 9)),
            entry(.transaction, owner: a, at: date(0, hour: 10)),
        ])
        let rows = days[0].rows
        XCTAssertEqual(singles(rows).count, 2)
        XCTAssertTrue(summaries(rows).isEmpty)
    }

    func testThreeEntriesCollapseToSummary() {
        let a = UUID()
        let days = HomeActivityDigest.build(from: [
            entry(.transaction, owner: a, at: date(0, hour: 9)),
            entry(.transaction, owner: a, at: date(0, hour: 10)),
            entry(.transaction, owner: a, at: date(0, hour: 11)),
        ])
        let rows = days[0].rows
        XCTAssertTrue(singles(rows).isEmpty)
        let summary = summaries(rows)
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(summary.first?.kind, .transaction)
        XCTAssertEqual(summary.first?.owner, a)
        XCTAssertEqual(summary.first?.count, 3)
    }

    func testTypesCountedIndependentlyForSameAssetAndDay() {
        let a = UUID()
        var entries = [
            entry(.photo, owner: a, at: date(0, hour: 9)),
            entry(.photo, owner: a, at: date(0, hour: 10)),
        ]
        entries += (0..<3).map { entry(.transaction, owner: a, at: date(0, hour: 11 + $0)) }

        let rows = HomeActivityDigest.build(from: entries)[0].rows
        // 2 photos stay individual; 3 transactions collapse.
        XCTAssertEqual(singles(rows).filter { $0.kind == .photo }.count, 2)
        let summary = summaries(rows)
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(summary.first?.kind, .transaction)
        XCTAssertEqual(summary.first?.count, 3)
    }

    func testAssetCreationNeverSummarized() {
        let days = HomeActivityDigest.build(from: [
            entry(.asset, at: date(0, hour: 9)),
            entry(.asset, at: date(0, hour: 10)),
            entry(.asset, at: date(0, hour: 11)),
        ])
        let rows = days[0].rows
        XCTAssertEqual(singles(rows).count, 3)
        XCTAssertTrue(summaries(rows).isEmpty)
    }
}
