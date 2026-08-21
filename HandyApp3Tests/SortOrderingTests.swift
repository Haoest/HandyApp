import XCTest
@testable import HandyApp3

final class SortOrderingTests: XCTestCase {

    // MARK: - values(count:after:before:)

    func testSingleValueBetweenNeighborsIsMidpoint() {
        let values = SortOrdering.values(count: 1, after: 0, before: 10)
        XCTAssertEqual(values, [5])
    }

    func testMultipleValuesSubdivideTheGapEvenly() throws {
        let values = try XCTUnwrap(SortOrdering.values(count: 3, after: 0, before: 40))
        XCTAssertEqual(values, [10, 20, 30])
    }

    func testValuesAtTopHaveNoPrev() {
        let values = SortOrdering.values(count: 2, after: nil, before: 20)
        XCTAssertEqual(values, [0, 10])
    }

    func testValuesAtBottomHaveNoNext() {
        let values = SortOrdering.values(count: 2, after: 80, before: nil)
        XCTAssertEqual(values, [90, 100])
    }

    func testSingleItemWithNoNeighborsAtAllStartsAtZero() {
        let values = SortOrdering.values(count: 1, after: nil, before: nil)
        XCTAssertEqual(values, [0])
    }

    func testCountZeroReturnsEmpty() {
        XCTAssertEqual(SortOrdering.values(count: 0, after: 0, before: 10), [])
    }

    // equal neighbors — today's all-zero custom-property tie — must fail so the caller
    // renormalizes instead of computing a value that ties with both.
    func testEqualNeighborsReturnsNilSoCallerRenormalizes() {
        XCTAssertNil(SortOrdering.values(count: 1, after: 0, before: 0))
    }

    func testInvertedNeighborsReturnsNil() {
        XCTAssertNil(SortOrdering.values(count: 1, after: 10, before: 0))
    }

    // An exhausted gap (no room for a strictly-between value at this precision) must
    // return nil, not a value that collides with a neighbor.
    func testExhaustedGapReturnsNil() {
        let tiny = 10.0.nextUp
        XCTAssertNil(SortOrdering.values(count: 1, after: 10, before: tiny))
    }

    func testResultIsAlwaysStrictlyBetweenNeighbors() throws {
        let values = try XCTUnwrap(SortOrdering.values(count: 5, after: 0, before: 10))
        XCTAssertEqual(values.count, 5)
        var prev = 0.0
        for v in values {
            XCTAssertGreaterThan(v, prev)
            prev = v
        }
        XCTAssertLessThan(prev, 10)
    }

    // MARK: - normalized(count:)

    func testNormalizedProducesTenPointLadder() {
        XCTAssertEqual(SortOrdering.normalized(count: 4), [0, 10, 20, 30])
    }

    func testNormalizedEmptyIsEmpty() {
        XCTAssertEqual(SortOrdering.normalized(count: 0), [])
    }

    // MARK: - next(after:)

    func testNextAfterEmptyIsZero() {
        XCTAssertEqual(SortOrdering.next(after: []), 0)
    }

    func testNextAfterExistingIsMaxPlusIncrement() {
        XCTAssertEqual(SortOrdering.next(after: [0, 30, 10]), 40)
    }

    // MARK: - precedes(_:_:)

    func testPrecedesOrdersBySortOrderFirst() {
        let a = AssetProperty(definition: PropertyDefinition(name: "A", type: .basic(.text)), sortOrder: 0)
        let b = AssetProperty(definition: PropertyDefinition(name: "B", type: .basic(.text)), sortOrder: 10)
        XCTAssertTrue(SortOrdering.precedes(a, b))
        XCTAssertFalse(SortOrdering.precedes(b, a))
    }

    func testPrecedesFallsBackToIDOnTie() {
        let a = AssetProperty(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                               definition: PropertyDefinition(name: "A", type: .basic(.text)), sortOrder: 0)
        let b = AssetProperty(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                               definition: PropertyDefinition(name: "B", type: .basic(.text)), sortOrder: 0)
        XCTAssertTrue(SortOrdering.precedes(a, b))
        XCTAssertFalse(SortOrdering.precedes(b, a))
    }

    // MARK: - moved(_:fromOffsets:toOffset:)

    func testMovedSingleElementDown() {
        let result = SortOrdering.moved(["a", "b", "c", "d"], fromOffsets: [0], toOffset: 3)
        XCTAssertEqual(result, ["b", "c", "a", "d"])
    }

    func testMovedSingleElementUp() {
        let result = SortOrdering.moved(["a", "b", "c", "d"], fromOffsets: [3], toOffset: 0)
        XCTAssertEqual(result, ["d", "a", "b", "c"])
    }

    func testMovedToBottom() {
        let result = SortOrdering.moved(["a", "b", "c"], fromOffsets: [0], toOffset: 3)
        XCTAssertEqual(result, ["b", "c", "a"])
    }

    func testMovedContiguousBlock() {
        let result = SortOrdering.moved(["a", "b", "c", "d", "e"], fromOffsets: [1, 2], toOffset: 5)
        XCTAssertEqual(result, ["a", "d", "e", "b", "c"])
    }

    func testMovedNoOpWhenAlreadyInPlace() {
        let result = SortOrdering.moved(["a", "b", "c"], fromOffsets: [1], toOffset: 1)
        XCTAssertEqual(result, ["a", "b", "c"])
    }
}
