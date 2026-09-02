import XCTest
@testable import HandyApp3

final class NumberParsingTests: XCTestCase {

    private let es = Locale(identifier: "es_ES")
    private let en = Locale(identifier: "en_US")
    private let fr = Locale(identifier: "fr_FR")

    // MARK: - The reported bug: a comma-decimal keyboard must not truncate or refuse

    func testCommaDecimalUnderSpanishParsesAsExpected() {
        XCTAssertEqual(NumberParsing.decimal("12,50", locale: es), Decimal(string: "12.50"))
        XCTAssertEqual(NumberParsing.double("12,50", locale: es), 12.50)
    }

    func testCommaDecimalUnderFrenchParsesAsExpected() {
        XCTAssertEqual(NumberParsing.decimal("12,50", locale: fr), Decimal(string: "12.50"))
        XCTAssertEqual(NumberParsing.double("12,50", locale: fr), 12.50)
    }

    /// A hardware keyboard still types `.` regardless of the active locale — that must keep
    /// working too, not just the decimal-pad comma.
    func testDotDecimalStillWorksUnderSpanish() {
        XCTAssertEqual(NumberParsing.decimal("12.50", locale: es), Decimal(string: "12.50"))
    }

    func testDotDecimalUnderEnglish() {
        XCTAssertEqual(NumberParsing.decimal("12.50", locale: en), Decimal(string: "12.50"))
    }

    // MARK: - Round trip with the editors' invariant "\(d)" prefill

    func testRoundTripsThroughInvariantStringInterpolation() {
        let d: Decimal = 1234.56
        for locale in [es, en, fr] {
            XCTAssertEqual(NumberParsing.decimal("\(d)", locale: locale), d)
        }
        let n = 42.5
        for locale in [es, en, fr] {
            XCTAssertEqual(NumberParsing.double("\(n)", locale: locale), n)
        }
    }

    // MARK: - Rejections

    func testAmbiguousMultipleSeparatorsIsRejectedRatherThanGuessed() {
        XCTAssertNil(NumberParsing.decimal("12,5,0", locale: es))
        XCTAssertNil(NumberParsing.decimal("1.234,56", locale: es), "grouping separators are not supported, not guessed at")
    }

    func testEmptyAndNonNumericAreRejected() {
        XCTAssertNil(NumberParsing.decimal("", locale: es))
        XCTAssertNil(NumberParsing.decimal("   ", locale: es))
        XCTAssertNil(NumberParsing.decimal("abc", locale: es))
        XCTAssertNil(NumberParsing.double("abc", locale: es))
    }

    // MARK: - Integers and signs

    func testPlainIntegerParsesUnderEveryLocale() {
        for locale in [es, en, fr] {
            XCTAssertEqual(NumberParsing.decimal("42", locale: locale), 42)
        }
    }

    func testNegativeAmountParses() {
        XCTAssertEqual(NumberParsing.decimal("-12,50", locale: es), Decimal(string: "-12.50"))
    }
}
