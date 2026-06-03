import XCTest
@testable import HandyApp3

final class StoredValueCompositeTests: XCTestCase {

    private func size2D() -> CompositeTypeDefinition {
        CompositeTypeDefinition(
            name: "2D Size",
            fields: [
                PropertyDefinition(name: "Width",  type: .basic(.number), isRequired: true),
                PropertyDefinition(name: "Length", type: .basic(.number), isRequired: true),
                PropertyDefinition(name: "Unit",   type: .basic(.text),   isRequired: false),
            ]
        )
    }

    // updatingComposite adds a field to a nil base and replaces an existing one.
    func testUpdatingCompositeAddsAndReplaces() {
        let added = StoredValue.updatingComposite(nil, field: "Width", to: .number(4))
        XCTAssertEqual(added, .composite(["Width": .number(4)]))

        let replaced = StoredValue.updatingComposite(added, field: "Width", to: .number(8))
        XCTAssertEqual(replaced, .composite(["Width": .number(8)]))
    }

    // updatingComposite collapses to nil once the last field is removed.
    func testUpdatingCompositeCollapsesToNilWhenEmptied() {
        let one = StoredValue.composite(["Width": .number(4)])
        let emptied = StoredValue.updatingComposite(one, field: "Width", to: nil)
        XCTAssertNil(emptied)
    }

    // compositeField round-trips a stored sub-value and returns nil for missing/non-composite.
    func testCompositeFieldRoundTrips() {
        let value = StoredValue.composite(["Width": .number(4), "Unit": .text("ft")])
        XCTAssertEqual(value.compositeField("Width"), .number(4))
        XCTAssertEqual(value.compositeField("Unit"), .text("ft"))
        XCTAssertNil(value.compositeField("Length"))
        XCTAssertNil(StoredValue.text("x").compositeField("Width"))
    }

    // compositeSummary joins set fields in definition order and omits unset ones.
    func testCompositeSummaryOrdersByDefinitionAndOmitsUnset() {
        let def = size2D()
        let value = StoredValue.composite(["Unit": .text("ft"), "Width": .number(4)])
        // Length is unset, so it's omitted; Width precedes Unit per field order.
        XCTAssertEqual(value.compositeSummary(for: def), "4 · ft")
    }

    // An empty composite summarizes to an empty string so callers can show a placeholder.
    func testCompositeSummaryEmptyWhenNothingSet() {
        XCTAssertEqual(StoredValue.composite([:]).compositeSummary(for: size2D()), "")
    }
}
