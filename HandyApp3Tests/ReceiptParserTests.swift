import XCTest
import CoreGraphics
@testable import HandyApp3

final class ReceiptParserTests: XCTestCase {

    // MARK: - Flat-text entry point (unchanged behavior)

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

    // MARK: - Adaptive monetary rule

    func testDollarInUseIgnoresBareNumbers() {
        // Zip and a quantity carry no `$`, so on a `$`-marked receipt they are
        // not amounts; the `$` total wins.
        let parsed = ReceiptParser.parse(lines: ["SHOP 34491", "Qty 2 Widget $5.00", "TOTAL $42.50"])
        XCTAssertEqual(parsed.total, Decimal(string: "42.50"))
    }

    func testNoDollarStillExcludesBareIntegerZip() {
        // No `$` anywhere → decimal cents required, so the zip is never an amount.
        let parsed = ReceiptParser.parse(lines: ["SHOP 34491", "Widget 5.00", "Gadget 9.99"])
        XCTAssertEqual(parsed.total, Decimal(string: "9.99"))
    }

    // MARK: - Token grid helpers

    private enum Col { case left, price }

    /// Lay out rows of labeled cells into normalized top-left token boxes:
    /// rows stacked top→bottom, `.left` cells on the left, `.price` cells in a
    /// right-aligned column. `rowGap` between rows controls block boundaries.
    private func tokens(rows: [[(String, Col)]], rowGap: CGFloat = 0.02) -> [OCRToken] {
        let rowHeight: CGFloat = 0.03
        var result: [OCRToken] = []
        var y: CGFloat = 0.05
        for row in rows {
            for (text, col) in row {
                let x: CGFloat = col == .left ? 0.1 : 0.7
                let width: CGFloat = col == .left ? 0.4 : 0.2
                result.append(OCRToken(text: text, box: CGRect(x: x, y: y, width: width, height: rowHeight)))
            }
            y += rowHeight + rowGap
        }
        return result
    }

    func testReconstructLinesJoinsRowAndOrders() {
        let toks = tokens(rows: [
            [("Milk", .left), ("3.99", .price)],
            [("Bagel", .left), ("2.25", .price)]
        ])
        XCTAssertEqual(ReceiptParser.reconstructLines(toks), ["Milk 3.99", "Bagel 2.25"])
    }

    func testReconstructLinesSortsLeftToRightRegardlessOfTokenOrder() {
        // Price token added before its description; reconstruction sorts by x.
        let toks = [
            OCRToken(text: "3.99", box: CGRect(x: 0.7, y: 0.1, width: 0.2, height: 0.03)),
            OCRToken(text: "Milk", box: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.03))
        ]
        XCTAssertEqual(ReceiptParser.reconstructLines(toks), ["Milk 3.99"])
    }

    func testDetectBlocksSplitsOnLargeVerticalGap() {
        // Two tight rows, a big gap, then two more tight rows → two blocks.
        let toks = tokens(rows: [
            [("STORE", .left)],
            [("123 Main St", .left)]
        ], rowGap: 0.005)
        + tokens(rows: [
            [("Milk", .left), ("3.99", .price)],
            [("TOTAL", .left), ("3.99", .price)]
        ], rowGap: 0.005).map { OCRToken(text: $0.text, box: $0.box.offsetBy(dx: 0, dy: 0.4)) }

        let blocks = ReceiptParser.detectBlocks(from: toks)
        XCTAssertEqual(blocks.count, 2)
    }

    func testDetectBlocksKeepsTightRowsTogether() {
        let toks = tokens(rows: [
            [("Milk", .left), ("3.99", .price)],
            [("Bagel", .left), ("2.25", .price)],
            [("TOTAL", .left), ("6.24", .price)]
        ], rowGap: 0.005)
        let blocks = ReceiptParser.detectBlocks(from: toks)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.tokens.count, 6)
    }

    // MARK: - Token entry point (selection vs context)

    func testParseFromSelectionTakesTotalFromSelectionMerchantFromContext() {
        let header = tokens(rows: [
            [("Joe's Diner", .left)],
            [("Springfield 34491", .left)]
        ], rowGap: 0.005)
        let body = tokens(rows: [
            [("Burger", .left), ("8.00", .price)],
            [("TOTAL", .left), ("8.00", .price)]
        ], rowGap: 0.005).map { OCRToken(text: $0.text, box: $0.box.offsetBy(dx: 0, dy: 0.4)) }

        let all = header + body
        // User selected only the body block.
        let parsed = ReceiptParser.parse(selectedTokens: body, allTokens: all)
        XCTAssertEqual(parsed.total, Decimal(string: "8.00"))
        XCTAssertEqual(parsed.details, "Joe's Diner")   // pulled from unselected header
        XCTAssertEqual(parsed.lineItems, ["Burger 8.00"])
    }

    func testParseFromSelectionNeverReadsZipAsTotal() {
        let header = tokens(rows: [[("Shop 34491", .left)]], rowGap: 0.005)
        let body = tokens(rows: [
            [("Widget", .left), ("5.00", .price)],
            [("Gadget", .left), ("9.99", .price)]
        ], rowGap: 0.005).map { OCRToken(text: $0.text, box: $0.box.offsetBy(dx: 0, dy: 0.4)) }

        let parsed = ReceiptParser.parse(selectedTokens: body, allTokens: header + body)
        XCTAssertEqual(parsed.total, Decimal(string: "9.99"))
    }
}
