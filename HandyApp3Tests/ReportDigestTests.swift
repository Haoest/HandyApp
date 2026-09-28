import XCTest
@testable import HandyApp3

final class ReportDigestTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func transaction(_ details: String, _ amount: Decimal, _ kind: TransactionKind,
                             on date: Date, createdAt: Date? = nil) -> Transaction {
        Transaction(details: details, amount: amount, date: date, kind: kind,
                    createdAt: createdAt ?? date)
    }

    private func source(id: UUID = UUID(), name: String = "Thing",
                        transactions: [Transaction]) -> ReportSource {
        ReportSource(thingID: id, thingName: name, transactions: transactions)
    }

    func testFiltersInclusiveDatesThingsAndDirectionAndCalculatesTotals() {
        let firstID = UUID()
        let secondID = UUID()
        let first = source(id: firstID, transactions: [
            transaction("Opening income", 100.25, .income, on: date(2026, 1, 1, hour: 0)),
            transaction("Closing expense", 40.10, .expense, on: date(2026, 12, 31, hour: 23)),
            transaction("Outside", 500, .income, on: date(2027, 1, 1, hour: 0))
        ])
        let second = source(id: secondID, transactions: [
            transaction("Other Thing", 200, .income, on: date(2026, 6, 1))
        ])

        let all = ReportDigest.build(sources: [first, second], startDate: date(2026, 1, 1),
                                     endDate: date(2026, 12, 31), selectedThingIDs: nil,
                                     direction: .all, calendar: calendar)
        XCTAssertEqual(all.entries.count, 3)
        XCTAssertEqual(all.moneyIn, 300.25)
        XCTAssertEqual(all.moneyOut, 40.10)
        XCTAssertEqual(all.grandTotal, 260.15)

        let selectedIncome = ReportDigest.build(
            sources: [first, second], startDate: date(2026, 1, 1), endDate: date(2026, 12, 31),
            selectedThingIDs: [firstID], direction: .income, calendar: calendar
        )
        XCTAssertEqual(selectedIncome.entries.map(\.details), ["Opening income"])
        XCTAssertEqual(selectedIncome.moneyIn, 100.25)
        XCTAssertEqual(selectedIncome.moneyOut, 0)
    }

    func testEmptySelectionReturnsZeroReport() {
        let result = ReportDigest.build(
            sources: [source(transactions: [transaction("Income", 10, .income, on: date(2026, 6, 1))])],
            startDate: date(2026, 1, 1), endDate: date(2026, 12, 31),
            selectedThingIDs: [], direction: .all, calendar: calendar
        )
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(result.grandTotal, 0)
    }

    func testRowsSortNewestFirstWithStableTiesAndEachOccurrenceRemainsSeparate() {
        let sameDate = date(2026, 5, 20)
        let older = transaction("Older", 1, .expense, on: date(2026, 5, 19))
        let first = transaction("First created", 2, .expense, on: sameDate,
                                createdAt: date(2026, 5, 20, hour: 10))
        let second = transaction("Second created", 3, .expense, on: sameDate,
                                 createdAt: date(2026, 5, 20, hour: 11))
        let result = ReportDigest.build(
            sources: [source(transactions: [older, first, second])],
            startDate: date(2026, 1, 1), endDate: date(2026, 12, 31),
            selectedThingIDs: nil, direction: .all, calendar: calendar
        )

        XCTAssertEqual(result.entries.map(\.details), ["Second created", "First created", "Older"])
        XCTAssertEqual(result.entries.count, 3)
    }

    func testEndBoundaryUsesCalendarDayAcrossDaylightSavingTime() {
        let dstDay = date(2026, 3, 8, hour: 23)
        let nextDay = date(2026, 3, 9, hour: 0)
        let result = ReportDigest.build(
            sources: [source(transactions: [
                transaction("DST day", 1, .income, on: dstDay),
                transaction("Next day", 1, .income, on: nextDay)
            ])],
            startDate: date(2026, 3, 8), endDate: date(2026, 3, 8),
            selectedThingIDs: nil, direction: .all, calendar: calendar
        )
        XCTAssertEqual(result.entries.map(\.details), ["DST day"])
    }
}
