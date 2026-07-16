import XCTest
@testable import HandyApp3

final class AssetNameMatcherTests: XCTestCase {

    var store: AssetStore!
    var categoryID: UUID!

    override func setUp() {
        super.setUp()
        store = AssetStore()
        categoryID = try! store.createCategory(name: "Test").id
    }

    @discardableResult
    private func makeAsset(_ name: String) throws -> Asset {
        try store.createAsset(name: name, categoryID: categoryID)
    }

    func testExactMatchBeatsPrefixAndSubstring() throws {
        try makeAsset("Camry")
        try makeAsset("Camry Keys")
        try makeAsset("My Camry")

        let results = AssetNameMatcher.match("Camry", in: store.allAssets)

        XCTAssertEqual(results.first?.name, "Camry")
    }

    func testCaseAndDiacriticInsensitive() throws {
        try makeAsset("Café Espresso Machine")

        let results = AssetNameMatcher.match("cafe espresso machine", in: store.allAssets)

        XCTAssertEqual(results.first?.name, "Café Espresso Machine")
    }

    func testDuplicateNamesBothReturned() throws {
        try makeAsset("Camry")
        try makeAsset("Camry")

        let results = AssetNameMatcher.match("Camry", in: store.allAssets)

        XCTAssertEqual(results.count, 2)
    }

    func testNoMatchReturnsEmpty() throws {
        try makeAsset("Camry")

        let results = AssetNameMatcher.match("Refrigerator", in: store.allAssets)

        XCTAssertTrue(results.isEmpty)
    }

    func testTokenMatchOnPartialPhrase() throws {
        try makeAsset("Camry Spare Keys")

        let results = AssetNameMatcher.match("keys", in: store.allAssets)

        XCTAssertEqual(results.first?.name, "Camry Spare Keys")
    }

    func testEmptyQueryReturnsEmpty() throws {
        try makeAsset("Camry")

        let results = AssetNameMatcher.match("   ", in: store.allAssets)

        XCTAssertTrue(results.isEmpty)
    }
}
