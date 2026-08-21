import XCTest
@testable import HandyApp3

final class PropertyReorderTests: XCTestCase {

    var store: AssetStore!

    override func setUp() {
        super.setUp()
        store = AssetStore()
    }

    // MARK: - Category templates

    func testMoveTemplatePropertyUpChangesOnlyMovedRowsOrder() throws {
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "A", type: .basic(.text)), sortOrder: 0),
            AssetProperty(definition: PropertyDefinition(name: "B", type: .basic(.text)), sortOrder: 10),
            AssetProperty(definition: PropertyDefinition(name: "C", type: .basic(.text)), sortOrder: 20),
        ])
        let bSortOrderBefore = cat.propertyTemplates[1].sortOrder
        let cSortOrderBefore = cat.propertyTemplates[2].sortOrder

        // Move "C" (offset 2) to the front (offset 0), matching `.onMove`'s own semantics.
        try store.moveTemplateProperties(fromOffsets: [2], toOffset: 0, inCategoryID: cat.id)

        let sorted = cat.liveTemplates.sorted(by: SortOrdering.precedes)
        XCTAssertEqual(sorted.map(\.definition.name), ["C", "A", "B"])
        // Only the moved row's sortOrder should have changed.
        XCTAssertEqual(cat.propertyTemplates[1].sortOrder, bSortOrderBefore)
        XCTAssertNotEqual(cat.propertyTemplates[2].sortOrder, cSortOrderBefore)
    }

    // Regression: `.onMove` offsets index the *displayed* (sortOrder-sorted) list, and the
    // first move makes array order and display order diverge — a move rewrites `sortOrder` in
    // place, never repositioning the array. A second move must still resolve its offsets
    // against the displayed order, not the raw array, or it grabs the wrong row.
    func testConsecutiveMovesResolveOffsetsAgainstDisplayedOrder() throws {
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "A", type: .basic(.text)), sortOrder: 0),
            AssetProperty(definition: PropertyDefinition(name: "B", type: .basic(.text)), sortOrder: 10),
            AssetProperty(definition: PropertyDefinition(name: "C", type: .basic(.text)), sortOrder: 20),
        ])
        // Move "C" to the front: display becomes [C, A, B]; array stays [A, B, C].
        try store.moveTemplateProperties(fromOffsets: [2], toOffset: 0, inCategoryID: cat.id)
        var sorted = cat.liveTemplates.sorted(by: SortOrdering.precedes)
        XCTAssertEqual(sorted.map(\.definition.name), ["C", "A", "B"])

        // Now move displayed offset 2 ("B") to the front. Against the raw array, offset 2
        // would still be "C" — the bug this test pins down.
        try store.moveTemplateProperties(fromOffsets: [2], toOffset: 0, inCategoryID: cat.id)
        sorted = cat.liveTemplates.sorted(by: SortOrdering.precedes)
        XCTAssertEqual(sorted.map(\.definition.name), ["B", "C", "A"])
    }

    func testConsecutiveMovesOnAssetBaseProperties() throws {
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "A", type: .basic(.text)), sortOrder: 0),
            AssetProperty(definition: PropertyDefinition(name: "B", type: .basic(.text)), sortOrder: 10),
            AssetProperty(definition: PropertyDefinition(name: "C", type: .basic(.text)), sortOrder: 20),
        ])
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)

        try store.moveBaseProperties(fromOffsets: [2], toOffset: 0, onAssetID: asset.id)
        try store.moveBaseProperties(fromOffsets: [2], toOffset: 0, onAssetID: asset.id)

        let sorted = asset.liveBaseProperties.sorted(by: SortOrdering.precedes)
        XCTAssertEqual(sorted.map(\.definition.name), ["B", "C", "A"])
    }

    func testMoveTemplatePropertyToBottom() throws {
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "A", type: .basic(.text)), sortOrder: 0),
            AssetProperty(definition: PropertyDefinition(name: "B", type: .basic(.text)), sortOrder: 10),
        ])
        try store.moveTemplateProperties(fromOffsets: [0], toOffset: 2, inCategoryID: cat.id)
        let sorted = cat.liveTemplates.sorted(by: SortOrdering.precedes)
        XCTAssertEqual(sorted.map(\.definition.name), ["B", "A"])
    }

    func testMoveTemplatePropertyBumpsOnlyMovedRowsModifyDate() throws {
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "A", type: .basic(.text)), sortOrder: 0),
            AssetProperty(definition: PropertyDefinition(name: "B", type: .basic(.text)), sortOrder: 10),
        ])
        let aModifyBefore = cat.propertyTemplates[0].modifyDate
        let bModifyBefore = cat.propertyTemplates[1].modifyDate

        try store.moveTemplateProperties(fromOffsets: [1], toOffset: 0, inCategoryID: cat.id)

        XCTAssertEqual(cat.propertyTemplates[0].modifyDate, aModifyBefore, "the un-moved row must not be touched")
        XCTAssertGreaterThan(cat.propertyTemplates[1].modifyDate, bModifyBefore)
    }

    func testAppendTemplatePropertyPlacesAfterExisting() throws {
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "A", type: .basic(.text)), sortOrder: 0),
            AssetProperty(definition: PropertyDefinition(name: "B", type: .basic(.text)), sortOrder: 30),
        ])
        let added = try store.appendTemplateProperty(
            definition: PropertyDefinition(name: "C", type: .basic(.text)), toCategoryID: cat.id
        )
        XCTAssertEqual(added.sortOrder, 40)
    }

    // MARK: - Asset base properties

    func testMoveBasePropertiesReordersAndBumpsAssetModifiedDate() throws {
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "A", type: .basic(.text)), sortOrder: 0),
            AssetProperty(definition: PropertyDefinition(name: "B", type: .basic(.text)), sortOrder: 10),
        ])
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)
        let modifiedBefore = asset.modifiedDate

        try store.moveBaseProperties(fromOffsets: [1], toOffset: 0, onAssetID: asset.id)

        let sorted = asset.liveBaseProperties.sorted(by: SortOrdering.precedes)
        XCTAssertEqual(sorted.map(\.definition.name), ["B", "A"])
        XCTAssertGreaterThan(asset.modifiedDate, modifiedBefore)
    }

    // MARK: - Custom properties

    func testAddCustomPropertyPlacesAfterExistingInsteadOfTyingAtZero() throws {
        let cat = try store.createCategory(name: "Appliance")
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)

        let first = try store.addCustomProperty(
            definition: PropertyDefinition(name: "First", type: .basic(.text)), toAssetID: asset.id
        )
        let second = try store.addCustomProperty(
            definition: PropertyDefinition(name: "Second", type: .basic(.text)), toAssetID: asset.id
        )

        XCTAssertEqual(first.sortOrder, 0)
        XCTAssertEqual(second.sortOrder, 10)
    }

    func testMoveCustomPropertiesReorders() throws {
        let cat = try store.createCategory(name: "Appliance")
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)
        try store.addCustomProperty(definition: PropertyDefinition(name: "First", type: .basic(.text)), toAssetID: asset.id)
        try store.addCustomProperty(definition: PropertyDefinition(name: "Second", type: .basic(.text)), toAssetID: asset.id)

        try store.moveCustomProperties(fromOffsets: [1], toOffset: 0, onAssetID: asset.id)

        let sorted = asset.liveCustomProperties.sorted(by: SortOrdering.precedes)
        XCTAssertEqual(sorted.map(\.definition.name), ["Second", "First"])
    }

    // Simulates data from before `addCustomProperty` assigned real sortOrder values: every
    // custom property ties at 0. Dropping a row strictly *between* two tied neighbors is the
    // one move `SortOrdering.values` can't satisfy (equal neighbors), so it must renormalize
    // the whole section instead of computing a value that collides with the tie.
    func testDroppingBetweenTiedNeighborsRenormalizesTheSection() throws {
        let cat = try store.createCategory(name: "Appliance")
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)
        // Fixed ascending ids: tied sortOrders display in id order (`SortOrdering.precedes`'s
        // tie-break), so these pin the displayed order to A, B, C deterministically.
        let a = AssetProperty(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!,
                              definition: PropertyDefinition(name: "A", type: .basic(.text)), sortOrder: 0)
        let b = AssetProperty(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!,
                              definition: PropertyDefinition(name: "B", type: .basic(.text)), sortOrder: 0)
        let c = AssetProperty(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!,
                              definition: PropertyDefinition(name: "C", type: .basic(.text)), sortOrder: 0)
        asset.customProperties = [a, b, c]

        // Move "C" (offset 2) to sit between "A" and "B" — final order [A, C, B].
        try store.moveCustomProperties(fromOffsets: [2], toOffset: 1, onAssetID: asset.id)

        let sorted = asset.liveCustomProperties.sorted(by: SortOrdering.precedes)
        XCTAssertEqual(sorted.map(\.definition.name), ["A", "C", "B"])
        // The section must no longer be tied — every value distinct.
        XCTAssertEqual(Set(asset.customProperties.map(\.sortOrder)).count, 3)
    }

    // The very front/back of a section never hits an equal-neighbor gap (one side has no
    // neighbor at all), so a move there succeeds without needing to renormalize anything —
    // only the moved row's sortOrder changes, the untouched rows may remain tied with each
    // other until something is later dropped between them.
    func testMovingATiedRowToTheFrontOnlyChangesThatRow() throws {
        let cat = try store.createCategory(name: "Appliance")
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)
        // Fixed ascending ids — same reason as above: pins tied rows' displayed order.
        let a = AssetProperty(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!,
                              definition: PropertyDefinition(name: "A", type: .basic(.text)), sortOrder: 0)
        let b = AssetProperty(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!,
                              definition: PropertyDefinition(name: "B", type: .basic(.text)), sortOrder: 0)
        let c = AssetProperty(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!,
                              definition: PropertyDefinition(name: "C", type: .basic(.text)), sortOrder: 0)
        asset.customProperties = [a, b, c]

        try store.moveCustomProperties(fromOffsets: [2], toOffset: 0, onAssetID: asset.id)

        XCTAssertEqual(c.sortOrder, -SortOrdering.increment)
        XCTAssertEqual(a.sortOrder, 0)
        XCTAssertEqual(b.sortOrder, 0)
    }

    func testMoveOnUnknownAssetThrows() {
        XCTAssertThrowsError(try store.moveCustomProperties(fromOffsets: [0], toOffset: 1, onAssetID: UUID()))
    }

    func testMoveOnUnknownCategoryThrows() {
        XCTAssertThrowsError(try store.moveTemplateProperties(fromOffsets: [0], toOffset: 1, inCategoryID: UUID()))
    }

    // MARK: - createAsset copies template sortOrder

    func testCreateAssetCopiesTemplateSortOrderNotArrayPosition() throws {
        // Templates deliberately out of sortOrder/array-position sync — as happens once a
        // category has been reordered at least once (see `SortOrdering.precedes`'s doc
        // comment: a reorder changes sortOrder in place, not array position).
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "A", type: .basic(.text)), sortOrder: 20),
            AssetProperty(definition: PropertyDefinition(name: "B", type: .basic(.text)), sortOrder: 10),
        ])
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)
        let a = try XCTUnwrap(asset.baseProperties.first { $0.definition.name == "A" })
        let b = try XCTUnwrap(asset.baseProperties.first { $0.definition.name == "B" })
        XCTAssertEqual(a.sortOrder, 20)
        XCTAssertEqual(b.sortOrder, 10)
    }
}
