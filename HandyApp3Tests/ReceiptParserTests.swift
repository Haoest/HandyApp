import XCTest
@testable import HandyApp3

final class ReceiptParserTests: XCTestCase {

    func testTotalKeywordAndExpenseKind() {
        let parsed = ReceiptParser.parse(lines: ["WALMART", "Milk 3.99", "TOTAL $42.50"])
        XCTAssertEqual(parsed.total, Decimal(string: "42.50"))
        XCTAssertEqual(parsed.kind, .expense)
    }

    func testSubtotalIsNotMistakenForTotal() {
        let parsed = ReceiptParser.parse(lines: ["SUBTOTAL 40.00", "TAX 2.50", "TOTAL 42.50"])
        XCTAssertEqual(parsed.total, Decimal(string: "42.50"))
    }

    func testCheckIsIncome() {
        let parsed = ReceiptParser.parse(lines: ["PAY TO THE ORDER OF Jane Doe", "100.00"])
        XCTAssertEqual(parsed.kind, .income)
    }

    func testFallsBackToLargestAmountWhenNoTotalKeyword() {
        let parsed = ReceiptParser.parse(lines: ["Widget 5.00", "Gadget 9.99"])
        XCTAssertEqual(parsed.total, Decimal(string: "9.99"))
    }

    func testCheckoutIsNotMistakenForCheck() {
        let parsed = ReceiptParser.parse(lines: ["Self Checkout", "Soda 1.25", "TOTAL 1.25"])
        XCTAssertEqual(parsed.kind, .expense)
    }

    func testLineItemsExcludeTaxChangeCashAndTotalLines() {
        let parsed = ReceiptParser.parse(lines: [
            "Coffee 3.50", "Bagel 2.25", "TAX 0.50", "CASH 10.00", "CHANGE 3.75", "TOTAL 6.25"
        ])
        XCTAssertEqual(parsed.lineItems, ["Coffee 3.50", "Bagel 2.25"])
        XCTAssertEqual(parsed.notesText, "Coffee 3.50\nBagel 2.25")
    }

    func testMerchantIsFirstNonPriceTextLine() {
        let parsed = ReceiptParser.parse(lines: ["Joe's Diner", "Burger 8.00", "TOTAL 8.00"])
        XCTAssertEqual(parsed.details, "Joe's Diner")
    }

    func testMerchantFallsBackToReceiptWhenNoTextLine() {
        let parsed = ReceiptParser.parse(lines: ["12.00", "TOTAL 12.00"])
        XCTAssertEqual(parsed.details, "Receipt")
    }

    func testParsesThousandsSeparatorAndDollarSign() {
        let parsed = ReceiptParser.parse(lines: ["GRAND TOTAL $1,234.56"])
        XCTAssertEqual(parsed.total, Decimal(string: "1234.56"))
    }
}
