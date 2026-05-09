import XCTest
@testable import HandyApp3

/// Behavioral tests for AssetStore against the TypeNode-based model.
/// TypeNode-tree-specific tests live in TypeNodeStoreTests.swift; pure model
/// tests for TypeNode itself live in TypeNodeTests.swift.
final class HandyApp3Tests: XCTestCase {

    var store: AssetStore!

    override func setUp() {
        super.setUp()
        store = AssetStore()
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    // MARK: - Local field management on TypeNodes

    func testAddLocalFieldToTypeNode() throws {
        let car = try store.createTypeNode(name: "Car")
        let def = PropertyDefinition(name: "Engine Oil Type", type: .basic(.text))
        try store.addLocalField(def, toTypeNodeID: car.id)
        XCTAssertEqual(car.localFields.count, 1)
        XCTAssertEqual(car.localFields.first?.name, "Engine Oil Type")
    }

    func testUpdateLocalField() throws {
        let car = try store.createTypeNode(name: "Car")
        let def = PropertyDefinition(name: "Oil Type", type: .basic(.text))
        try store.addLocalField(def, toTypeNodeID: car.id)
        try store.updateLocalField(id: def.id, inTypeNodeID: car.id, name: "Engine Oil Type", type: .basic(.number))
        let updated = car.localFields.first!
        XCTAssertEqual(updated.name, "Engine Oil Type")
        XCTAssertEqual(updated.type, .basic(.number))
    }

    func testRemoveLocalFieldAlsoCleansAssetValues() throws {
        let car = try store.createTypeNode(name: "Car")
        let def = PropertyDefinition(name: "Tire Pressure", type: .basic(.number))
        try store.addLocalField(def, toTypeNodeID: car.id)
        let asset = try store.createAsset(name: "Camry", typeID: car.id)
        try store.setPropertyValue(.number(32), forDefinitionID: def.id, onAssetID: asset.id)
        XCTAssertEqual(asset.propertyValues.count, 1)
        try store.removeLocalField(id: def.id, fromTypeNodeID: car.id)
        XCTAssertEqual(asset.propertyValues.count, 0)
        XCTAssertEqual(car.localFields.count, 0)
    }

    func testRemoveLocalFieldFromParentCleansDescendantAssetValues() throws {
        // Verify orphan-cleanup walks the subtree, not just direct-typed assets.
        let appliance = try store.createTypeNode(name: "Appliance", isAbstract: true)
        let warranty = PropertyDefinition(name: "Warranty", type: .basic(.text))
        try store.addLocalField(warranty, toTypeNodeID: appliance.id)
        let range = try store.createTypeNode(name: "Range", parentID: appliance.id)
        let rangeAsset = try store.createAsset(name: "GE Range", typeID: range.id)
        try store.setPropertyValue(.text("3 years"), forDefinitionID: warranty.id, onAssetID: rangeAsset.id)
        XCTAssertEqual(rangeAsset.propertyValues.count, 1)

        try store.removeLocalField(id: warranty.id, fromTypeNodeID: appliance.id)
        XCTAssertEqual(rangeAsset.propertyValues.count, 0)
    }

    // MARK: - Asset lifecycle

    func testUpdateAsset() throws {
        let car = try store.createTypeNode(name: "Car")
        let asset = try store.createAsset(name: "Old Car", typeID: car.id)
        try store.updateAsset(id: asset.id, name: "2022 Camry")
        XCTAssertEqual(store.assets[asset.id]?.name, "2022 Camry")
    }

    func testDeleteAsset() throws {
        let car = try store.createTypeNode(name: "Car")
        let asset = try store.createAsset(name: "Camry", typeID: car.id)
        try store.deleteAsset(id: asset.id)
        XCTAssertNil(store.assets[asset.id])
    }

    func testDeleteTypeNodeCascadesToAssets() throws {
        let car = try store.createTypeNode(name: "Car")
        let asset = try store.createAsset(name: "Camry", typeID: car.id)
        try store.deleteTypeNode(id: car.id)
        XCTAssertNil(store.assets[asset.id])
        XCTAssertNil(store.typeNodes[car.id])
    }

    func testDeleteTypeNodeCascadesToDescendantsAndTheirAssets() throws {
        let appliance = try store.createTypeNode(name: "Appliance", isAbstract: true)
        let range = try store.createTypeNode(name: "Range", parentID: appliance.id)
        let asset = try store.createAsset(name: "GE Range", typeID: range.id)
        try store.deleteTypeNode(id: appliance.id)
        XCTAssertNil(store.assets[asset.id])
        XCTAssertNil(store.typeNodes[range.id])
        XCTAssertNil(store.typeNodes[appliance.id])
    }

    // MARK: - assets(ofTypeID:)

    func testAssetsOfTypeReturnsExactMatches() throws {
        let car = try store.createTypeNode(name: "Car")
        let house = try store.createTypeNode(name: "House")
        try store.createAsset(name: "Camry", typeID: car.id)
        try store.createAsset(name: "My House", typeID: house.id)
        let cars = try store.assets(ofTypeID: car.id)
        XCTAssertEqual(cars.count, 1)
        XCTAssertEqual(cars.first?.name, "Camry")
    }

    func testAssetsOfTypeIncludesSubtypes() throws {
        // "Give me all Appliances" returns Refrigerators, Ranges, etc.
        let appliance = try store.createTypeNode(name: "Appliance", isAbstract: true)
        let range = try store.createTypeNode(name: "Range", parentID: appliance.id)
        let fridge = try store.createTypeNode(name: "Refrigerator", parentID: appliance.id)
        try store.createAsset(name: "GE Range", typeID: range.id)
        try store.createAsset(name: "Samsung Fridge", typeID: fridge.id)
        let appliances = try store.assets(ofTypeID: appliance.id)
        XCTAssertEqual(Set(appliances.map(\.name)), ["GE Range", "Samsung Fridge"])
    }

    // MARK: - PropertyValue: Basic Types

    func testSetTextPropertyValue() throws {
        let car = try store.createTypeNode(name: "Car")
        let def = PropertyDefinition(name: "Oil Type", type: .basic(.text))
        try store.addLocalField(def, toTypeNodeID: car.id)
        let asset = try store.createAsset(name: "Camry", typeID: car.id)
        try store.setPropertyValue(.text("5W-30"), forDefinitionID: def.id, onAssetID: asset.id)
        XCTAssertEqual(asset.value(for: def.id)?.value, .text("5W-30"))
    }

    func testSetNumberPropertyValue() throws {
        let car = try store.createTypeNode(name: "Car")
        let def = PropertyDefinition(name: "Tire Pressure", type: .basic(.number))
        try store.addLocalField(def, toTypeNodeID: car.id)
        let asset = try store.createAsset(name: "Camry", typeID: car.id)
        try store.setPropertyValue(.number(32.5), forDefinitionID: def.id, onAssetID: asset.id)
        XCTAssertEqual(asset.value(for: def.id)?.value, .number(32.5))
    }

    func testSetCurrencyPropertyValue() throws {
        let appliance = try store.createTypeNode(name: "Appliance")
        let def = PropertyDefinition(name: "Purchase Price", type: .basic(.currency))
        try store.addLocalField(def, toTypeNodeID: appliance.id)
        let asset = try store.createAsset(name: "Washer", typeID: appliance.id)
        try store.setPropertyValue(.currency(Decimal(799.99)), forDefinitionID: def.id, onAssetID: asset.id)
        XCTAssertEqual(asset.value(for: def.id)?.value, .currency(Decimal(799.99)))
    }

    func testSetDatePropertyValue() throws {
        let appliance = try store.createTypeNode(name: "Appliance")
        let def = PropertyDefinition(name: "Purchase Date", type: .basic(.date))
        try store.addLocalField(def, toTypeNodeID: appliance.id)
        let asset = try store.createAsset(name: "Washer", typeID: appliance.id)
        let date = Date(timeIntervalSince1970: 1_000_000)
        try store.setPropertyValue(.date(date), forDefinitionID: def.id, onAssetID: asset.id)
        XCTAssertEqual(asset.value(for: def.id)?.value, .date(date))
    }

    func testOverwritePropertyValue() throws {
        let car = try store.createTypeNode(name: "Car")
        let def = PropertyDefinition(name: "Oil Type", type: .basic(.text))
        try store.addLocalField(def, toTypeNodeID: car.id)
        let asset = try store.createAsset(name: "Camry", typeID: car.id)
        try store.setPropertyValue(.text("5W-30"), forDefinitionID: def.id, onAssetID: asset.id)
        try store.setPropertyValue(.text("0W-20"), forDefinitionID: def.id, onAssetID: asset.id)
        XCTAssertEqual(asset.propertyValues.count, 1)
        XCTAssertEqual(asset.value(for: def.id)?.value, .text("0W-20"))
    }

    func testTypeMismatchThrows() throws {
        let car = try store.createTypeNode(name: "Car")
        let def = PropertyDefinition(name: "Oil Type", type: .basic(.text))
        try store.addLocalField(def, toTypeNodeID: car.id)
        let asset = try store.createAsset(name: "Camry", typeID: car.id)
        XCTAssertThrowsError(
            try store.setPropertyValue(.number(5), forDefinitionID: def.id, onAssetID: asset.id)
        ) { error in
            if case AssetStoreError.typeMismatch(let expected, _) = error {
                XCTAssertEqual(expected, "text")
            } else { XCTFail("Wrong error: \(error)") }
        }
    }

    func testRemovePropertyValue() throws {
        let car = try store.createTypeNode(name: "Car")
        let def = PropertyDefinition(name: "Oil Type", type: .basic(.text))
        try store.addLocalField(def, toTypeNodeID: car.id)
        let asset = try store.createAsset(name: "Camry", typeID: car.id)
        try store.setPropertyValue(.text("5W-30"), forDefinitionID: def.id, onAssetID: asset.id)
        try store.removePropertyValue(forDefinitionID: def.id, fromAssetID: asset.id)
        XCTAssertNil(asset.value(for: def.id))
    }

    // MARK: - Composite value type

    func testCreateCompositeType() {
        let insuranceType = store.createCompositeType(
            name: "Insurance Info",
            systemFields: [
                PropertyDefinition(name: "Vendor", type: .basic(.text)),
                PropertyDefinition(name: "Annual Premium", type: .basic(.currency))
            ]
        )
        XCTAssertEqual(store.allCompositeTypes.count, 1)
        XCTAssertEqual(insuranceType.fields.count, 2)
    }

    func testSetCompositePropertyValue() throws {
        let insuranceType = store.createCompositeType(
            name: "Insurance Info",
            systemFields: [
                PropertyDefinition(name: "Vendor", type: .basic(.text)),
                PropertyDefinition(name: "Annual Premium", type: .basic(.currency))
            ]
        )
        let house = try store.createTypeNode(name: "House")
        let def = PropertyDefinition(name: "Insurance", type: .composite(insuranceType))
        try store.addLocalField(def, toTypeNodeID: house.id)
        let asset = try store.createAsset(name: "My House", typeID: house.id)

        let payload: StoredValue = .composite([
            "Vendor": .text("State Farm"),
            "Annual Premium": .currency(Decimal(1200))
        ])
        try store.setPropertyValue(payload, forDefinitionID: def.id, onAssetID: asset.id)

        if case .composite(let result) = asset.value(for: def.id)?.value {
            XCTAssertEqual(result["Vendor"], .text("State Farm"))
            XCTAssertEqual(result["Annual Premium"], .currency(Decimal(1200)))
        } else {
            XCTFail("Expected composite value")
        }
    }

    func testCompositeUnknownFieldThrows() throws {
        let insuranceType = store.createCompositeType(
            name: "Insurance Info",
            systemFields: [PropertyDefinition(name: "Vendor", type: .basic(.text))]
        )
        let house = try store.createTypeNode(name: "House")
        let def = PropertyDefinition(name: "Insurance", type: .composite(insuranceType))
        try store.addLocalField(def, toTypeNodeID: house.id)
        let asset = try store.createAsset(name: "My House", typeID: house.id)

        XCTAssertThrowsError(
            try store.setPropertyValue(
                .composite(["UnknownField": .text("X")]),
                forDefinitionID: def.id,
                onAssetID: asset.id
            )
        ) { error in
            if case AssetStoreError.compositeFieldMismatch = error { } else { XCTFail("Wrong error: \(error)") }
        }
    }

    func testCompositeFieldTypeMismatchThrows() throws {
        let insuranceType = store.createCompositeType(
            name: "Insurance Info",
            systemFields: [PropertyDefinition(name: "Vendor", type: .basic(.text))]
        )
        let house = try store.createTypeNode(name: "House")
        let def = PropertyDefinition(name: "Insurance", type: .composite(insuranceType))
        try store.addLocalField(def, toTypeNodeID: house.id)
        let asset = try store.createAsset(name: "My House", typeID: house.id)

        XCTAssertThrowsError(
            try store.setPropertyValue(
                .composite(["Vendor": .number(42)]),
                forDefinitionID: def.id,
                onAssetID: asset.id
            )
        ) { error in
            if case AssetStoreError.typeMismatch = error { } else { XCTFail("Wrong error: \(error)") }
        }
    }

    func testNestedCompositeType() throws {
        let addressType = store.createCompositeType(
            name: "Address",
            systemFields: [
                PropertyDefinition(name: "Street", type: .basic(.text)),
                PropertyDefinition(name: "City", type: .basic(.text)),
                PropertyDefinition(name: "Zip", type: .basic(.text))
            ]
        )
        let insuranceType = store.createCompositeType(
            name: "Insurance Details",
            systemFields: [
                PropertyDefinition(name: "Vendor", type: .basic(.text)),
                PropertyDefinition(name: "Mailing Address", type: .composite(addressType))
            ]
        )
        let house = try store.createTypeNode(name: "House")
        let def = PropertyDefinition(name: "Insurance", type: .composite(insuranceType))
        try store.addLocalField(def, toTypeNodeID: house.id)
        let asset = try store.createAsset(name: "My House", typeID: house.id)

        let nestedPayload: StoredValue = .composite([
            "Vendor": .text("Allstate"),
            "Mailing Address": .composite([
                "Street": .text("123 Main St"),
                "City": .text("Springfield"),
                "Zip": .text("62701")
            ])
        ])
        try store.setPropertyValue(nestedPayload, forDefinitionID: def.id, onAssetID: asset.id)

        guard case .composite(let outer) = asset.value(for: def.id)?.value,
              case .composite(let addr) = outer["Mailing Address"] else {
            XCTFail("Expected nested composite"); return
        }
        XCTAssertEqual(outer["Vendor"], .text("Allstate"))
        XCTAssertEqual(addr["City"], .text("Springfield"))
    }

    func testNestedCompositeFieldTypeMismatchThrows() throws {
        let addressType = store.createCompositeType(
            name: "Address",
            systemFields: [PropertyDefinition(name: "Zip", type: .basic(.text))]
        )
        let insuranceType = store.createCompositeType(
            name: "Insurance",
            systemFields: [PropertyDefinition(name: "Mailing Address", type: .composite(addressType))]
        )
        let house = try store.createTypeNode(name: "House")
        let def = PropertyDefinition(name: "Insurance", type: .composite(insuranceType))
        try store.addLocalField(def, toTypeNodeID: house.id)
        let asset = try store.createAsset(name: "My House", typeID: house.id)

        XCTAssertThrowsError(
            try store.setPropertyValue(
                .composite(["Mailing Address": .composite(["Zip": .number(62701)])]),
                forDefinitionID: def.id,
                onAssetID: asset.id
            )
        ) { error in
            if case AssetStoreError.typeMismatch = error { } else { XCTFail("Wrong error: \(error)") }
        }
    }

    // MARK: - isRequired / optional fields

    func testOptionalFieldMayBeOmitted() throws {
        let ct = store.createCompositeType(
            name: "Contact",
            userFields: [
                PropertyDefinition(name: "Name",  type: .basic(.text), isRequired: true),
                PropertyDefinition(name: "Notes", type: .basic(.text), isRequired: false),
            ]
        )
        XCTAssertNoThrow(
            try store.validate(stored: .composite(["Name": .text("Alice")]),
                               against: .composite(ct), definitionName: "Contact")
        )
    }

    func testRequiredFieldMissingThrows() throws {
        let ct = store.createCompositeType(
            name: "Contact",
            userFields: [
                PropertyDefinition(name: "Name",  type: .basic(.text), isRequired: true),
                PropertyDefinition(name: "Notes", type: .basic(.text), isRequired: false),
            ]
        )
        XCTAssertThrowsError(
            try store.validate(stored: .composite(["Notes": .text("some note")]),
                               against: .composite(ct), definitionName: "Contact")
        ) { error in
            if case AssetStoreError.compositeFieldMismatch(let details) = error {
                XCTAssertTrue(details.contains("Name"))
            } else { XCTFail("Wrong error: \(error)") }
        }
    }

    // MARK: - Built-in composite types (W × L)

    func testSeedBuiltInTypes() {
        store.seedBuiltInTypes()
        XCTAssertTrue(store.allCompositeTypes.contains { $0.name == "W × L" })
    }

    func testSeedBuiltInTypesIsIdempotent() {
        store.seedBuiltInTypes()
        store.seedBuiltInTypes()
        XCTAssertEqual(store.allCompositeTypes.filter { $0.name == "W × L" }.count, 1)
    }

    func testWidthByLengthRequiredFieldsOnly() throws {
        store.seedBuiltInTypes()
        let wxl = store.allCompositeTypes.first { $0.name == "W × L" }!
        XCTAssertNoThrow(
            try store.validate(stored: .composite(["Width": .number(12), "Length": .number(20)]),
                               against: .composite(wxl), definitionName: "Lot Size")
        )
    }

    func testWidthByLengthMissingLengthThrows() throws {
        store.seedBuiltInTypes()
        let wxl = store.allCompositeTypes.first { $0.name == "W × L" }!
        XCTAssertThrowsError(
            try store.validate(stored: .composite(["Width": .number(12)]),
                               against: .composite(wxl), definitionName: "Lot Size")
        ) { error in
            if case AssetStoreError.compositeFieldMismatch(let details) = error {
                XCTAssertTrue(details.contains("Length"))
            } else { XCTFail("Wrong error: \(error)") }
        }
    }

    func testWidthByLengthOnAsset() throws {
        store.seedBuiltInTypes()
        let wxl = store.allCompositeTypes.first { $0.name == "W × L" }!
        let house = try store.createTypeNode(name: "House")
        let lotDef = PropertyDefinition(name: "Lot Size", type: .composite(wxl))
        try store.addLocalField(lotDef, toTypeNodeID: house.id)
        let asset = try store.createAsset(name: "123 Main St", typeID: house.id)

        try store.setPropertyValue(
            .composite(["Width": .number(80), "Length": .number(120), "Unit": .text(UnitIndex.feet.symbol)]),
            forDefinitionID: lotDef.id,
            onAssetID: asset.id
        )
        guard case .composite(let v) = asset.value(for: lotDef.id)?.value else {
            XCTFail("Expected composite value"); return
        }
        XCTAssertEqual(v["Width"],  .number(80))
        XCTAssertEqual(v["Length"], .number(120))
        XCTAssertEqual(v["Unit"],   .text("ft"))
    }

    // MARK: - Contact field

    func testContactBasicTypeExists() {
        XCTAssertTrue(BasicType.allCases.contains(.contact))
    }

    func testSetContactPropertyValue() throws {
        let car = try store.createTypeNode(name: "Car")
        let def = PropertyDefinition(name: "Service Center", type: .basic(.contact))
        try store.addLocalField(def, toTypeNodeID: car.id)
        let camry = try store.createAsset(name: "2022 Camry", typeID: car.id)

        let fakeIdentifier = "ABC-123-CONTACT-ID"
        try store.setPropertyValue(.contact(fakeIdentifier), forDefinitionID: def.id, onAssetID: camry.id)

        guard case .contact(let stored) = camry.value(for: def.id)?.value else {
            XCTFail("Expected .contact value"); return
        }
        XCTAssertEqual(stored, fakeIdentifier)
    }

    func testContactTypeMismatchThrows() throws {
        let car = try store.createTypeNode(name: "Car")
        let def = PropertyDefinition(name: "Service Center", type: .basic(.contact))
        try store.addLocalField(def, toTypeNodeID: car.id)
        let camry = try store.createAsset(name: "2022 Camry", typeID: car.id)

        XCTAssertThrowsError(
            try store.setPropertyValue(.text("not a contact"), forDefinitionID: def.id, onAssetID: camry.id)
        ) { error in
            if case AssetStoreError.typeMismatch(let expected, _) = error {
                XCTAssertEqual(expected, "contact")
            } else { XCTFail("Wrong error: \(error)") }
        }
    }

    func testContactIdentifierHelperOnStore() throws {
        let car = try store.createTypeNode(name: "Car")
        let def = PropertyDefinition(name: "Service Center", type: .basic(.contact))
        try store.addLocalField(def, toTypeNodeID: car.id)
        let camry = try store.createAsset(name: "2022 Camry", typeID: car.id)
        let fakeID = "DEALER-CONTACT-UUID"
        try store.setPropertyValue(.contact(fakeID), forDefinitionID: def.id, onAssetID: camry.id)

        let retrieved = store.contactIdentifier(forDefinitionID: def.id, onAssetID: camry.id)
        XCTAssertEqual(retrieved, fakeID)
    }

    func testContactIdentifierHelperReturnsNilWhenNotSet() throws {
        let car = try store.createTypeNode(name: "Car")
        let def = PropertyDefinition(name: "Service Center", type: .basic(.contact))
        try store.addLocalField(def, toTypeNodeID: car.id)
        let camry = try store.createAsset(name: "2022 Camry", typeID: car.id)
        XCTAssertNil(store.contactIdentifier(forDefinitionID: def.id, onAssetID: camry.id))
    }

    // MARK: - UnitIndex

    func testUnitIndexContainsStarterUnits() {
        XCTAssertNotNil(UnitIndex.unit(id: "length.inch"))
        XCTAssertNotNil(UnitIndex.unit(id: "length.feet"))
        XCTAssertNotNil(UnitIndex.unit(id: "weight.pound"))
    }

    func testUnitIndexLookupBySymbol() {
        XCTAssertEqual(UnitIndex.unit(symbol: "in"), UnitIndex.inch)
        XCTAssertEqual(UnitIndex.unit(symbol: "ft"), UnitIndex.feet)
        XCTAssertEqual(UnitIndex.unit(symbol: "lb"), UnitIndex.pound)
    }

    func testUnitIndexUnknownReturnsNil() {
        XCTAssertNil(UnitIndex.unit(id: "length.furlongs"))
        XCTAssertNil(UnitIndex.unit(symbol: "??"))
    }

    func testUnitIndexFilterByCategory() {
        let lengths = UnitIndex.units(for: .length)
        let weights = UnitIndex.units(for: .weight)
        XCTAssertTrue(lengths.allSatisfy { $0.category == .length })
        XCTAssertTrue(weights.allSatisfy { $0.category == .weight })
        XCTAssertTrue(lengths.contains(UnitIndex.inch))
        XCTAssertTrue(lengths.contains(UnitIndex.feet))
        XCTAssertTrue(weights.contains(UnitIndex.pound))
    }

    func testUnitDefinitionDisplayName() {
        XCTAssertEqual(UnitIndex.inch.displayName,  "Inch (in)")
        XCTAssertEqual(UnitIndex.feet.displayName,  "Feet (ft)")
        XCTAssertEqual(UnitIndex.pound.displayName, "Pound (lb)")
    }

    func testUnitIdsAreStableAndUnique() {
        let ids = UnitIndex.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Duplicate unit ids found")
    }

    func testUnitSymbolsAreUnique() {
        let symbols = UnitIndex.all.map(\.symbol)
        XCTAssertEqual(symbols.count, Set(symbols).count, "Duplicate unit symbols found")
    }

    // MARK: - Asset containment hierarchy

    func testAddChildAsset() throws {
        let house = try store.createTypeNode(name: "House")
        let appliance = try store.createTypeNode(name: "Appliance")
        let myHouse = try store.createAsset(name: "My House", typeID: house.id)
        let fridge = try store.createAsset(name: "Refrigerator", typeID: appliance.id)

        try store.addChild(assetID: fridge.id, toParentID: myHouse.id)

        XCTAssertEqual(myHouse.children.count, 1)
        XCTAssertEqual(myHouse.children.first, fridge)
        XCTAssertEqual(fridge.parent, myHouse)
        XCTAssertFalse(fridge.isRoot)
        XCTAssertTrue(myHouse.isRoot)
    }

    func testThreeLevelHierarchy() throws {
        let house = try store.createTypeNode(name: "House")
        let appliance = try store.createTypeNode(name: "Appliance")
        let part = try store.createTypeNode(name: "Part")
        let myHouse = try store.createAsset(name: "My House", typeID: house.id)
        let fridge = try store.createAsset(name: "Refrigerator", typeID: appliance.id)
        let filter = try store.createAsset(name: "Water Filter", typeID: part.id)

        try store.addChild(assetID: fridge.id, toParentID: myHouse.id)
        try store.addChild(assetID: filter.id, toParentID: fridge.id)

        XCTAssertEqual(filter.parent, fridge)
        XCTAssertEqual(filter.ancestors, [myHouse, fridge])
        XCTAssertEqual(myHouse.descendants.count, 2)
        XCTAssertTrue(myHouse.descendants.contains(filter))
    }

    func testRemoveFromParent() throws {
        let house = try store.createTypeNode(name: "House")
        let appliance = try store.createTypeNode(name: "Appliance")
        let myHouse = try store.createAsset(name: "My House", typeID: house.id)
        let fridge = try store.createAsset(name: "Refrigerator", typeID: appliance.id)

        try store.addChild(assetID: fridge.id, toParentID: myHouse.id)
        try store.removeFromParent(assetID: fridge.id)

        XCTAssertNil(fridge.parent)
        XCTAssertTrue(fridge.isRoot)
        XCTAssertTrue(myHouse.children.isEmpty)
    }

    func testMoveAssetToNewParent() throws {
        let house = try store.createTypeNode(name: "House")
        let appliance = try store.createTypeNode(name: "Appliance")
        let garage = try store.createAsset(name: "Garage", typeID: house.id)
        let kitchen = try store.createAsset(name: "Kitchen", typeID: house.id)
        let fridge = try store.createAsset(name: "Refrigerator", typeID: appliance.id)

        try store.addChild(assetID: fridge.id, toParentID: garage.id)
        XCTAssertEqual(fridge.parent, garage)

        try store.moveAsset(assetID: fridge.id, toParentID: kitchen.id)
        XCTAssertEqual(fridge.parent, kitchen)
        XCTAssertTrue(garage.children.isEmpty)
        XCTAssertEqual(kitchen.children.count, 1)
    }

    func testCycleDetectionDirectThrows() throws {
        let house = try store.createTypeNode(name: "House")
        let appliance = try store.createTypeNode(name: "Appliance")
        let myHouse = try store.createAsset(name: "My House", typeID: house.id)
        let fridge = try store.createAsset(name: "Refrigerator", typeID: appliance.id)

        try store.addChild(assetID: fridge.id, toParentID: myHouse.id)

        XCTAssertThrowsError(try store.addChild(assetID: myHouse.id, toParentID: fridge.id)) { error in
            if case AssetStoreError.hierarchyCycle = error { } else { XCTFail("Expected hierarchyCycle, got \(error)") }
        }
    }

    func testCycleDetectionDeepThrows() throws {
        let house = try store.createTypeNode(name: "House")
        let a = try store.createAsset(name: "A", typeID: house.id)
        let b = try store.createAsset(name: "B", typeID: house.id)
        let c = try store.createAsset(name: "C", typeID: house.id)

        try store.addChild(assetID: b.id, toParentID: a.id)
        try store.addChild(assetID: c.id, toParentID: b.id)

        XCTAssertThrowsError(try store.addChild(assetID: a.id, toParentID: c.id)) { error in
            if case AssetStoreError.hierarchyCycle = error { } else { XCTFail("Expected hierarchyCycle, got \(error)") }
        }
    }

    func testSelfParentThrows() throws {
        let house = try store.createTypeNode(name: "House")
        let a = try store.createAsset(name: "A", typeID: house.id)
        XCTAssertThrowsError(try store.addChild(assetID: a.id, toParentID: a.id)) { error in
            if case AssetStoreError.hierarchyCycle = error { } else { XCTFail("Expected hierarchyCycle, got \(error)") }
        }
    }

    func testDeleteParentReparentsChildren() throws {
        let house = try store.createTypeNode(name: "House")
        let appliance = try store.createTypeNode(name: "Appliance")
        let part = try store.createTypeNode(name: "Part")
        let myHouse     = try store.createAsset(name: "My House",    typeID: house.id)
        let fridge      = try store.createAsset(name: "Refrigerator", typeID: appliance.id)
        let waterFilter = try store.createAsset(name: "Water Filter", typeID: part.id)

        try store.addChild(assetID: fridge.id,      toParentID: myHouse.id)
        try store.addChild(assetID: waterFilter.id, toParentID: fridge.id)

        // Deleting fridge should promote waterFilter to myHouse's direct child
        try store.deleteAsset(id: fridge.id)

        XCTAssertNil(store.assets[fridge.id])
        XCTAssertEqual(waterFilter.parent, myHouse)
        XCTAssertTrue(myHouse.children.contains(waterFilter))
    }

    func testRootAssets() throws {
        let house = try store.createTypeNode(name: "House")
        let appliance = try store.createTypeNode(name: "Appliance")
        let myHouse = try store.createAsset(name: "My House", typeID: house.id)
        let fridge = try store.createAsset(name: "Refrigerator", typeID: appliance.id)
        try store.addChild(assetID: fridge.id, toParentID: myHouse.id)

        let roots = store.rootAssets
        XCTAssertTrue(roots.contains(myHouse))
        XCTAssertFalse(roots.contains(fridge))
    }

    // MARK: - Real-world scenario

    func testHouseWithApplianceHierarchyAndCustomProperty() throws {
        // House asset contains a Refrigerator asset; the Refrigerator declares
        // an instance-level (custom) property the type doesn't model.
        let house = try store.createTypeNode(
            name: "House",
            localFields: [
                PropertyDefinition(name: "Roof Age (Years)", type: .basic(.number)),
                PropertyDefinition(name: "HVAC Filter Size", type: .basic(.text)),
            ]
        )
        let appliance = try store.createTypeNode(
            name: "Appliance",
            localFields: [PropertyDefinition(name: "Make", type: .basic(.text))]
        )

        let myHouse = try store.createAsset(name: "123 Main St", typeID: house.id)
        let roofDef = house.allFields.first { $0.name == "Roof Age (Years)" }!
        let filterDef = house.allFields.first { $0.name == "HVAC Filter Size" }!
        try store.setPropertyValue(.number(12),       forDefinitionID: roofDef.id,   onAssetID: myHouse.id)
        try store.setPropertyValue(.text("20x25x1"), forDefinitionID: filterDef.id, onAssetID: myHouse.id)

        let fridge = try store.createAsset(name: "Samsung", typeID: appliance.id)
        try store.addChild(assetID: fridge.id, toParentID: myHouse.id)
        let serialNumberDef = PropertyDefinition(name: "Serial #", type: .basic(.text))
        try store.addCustomProperty(definition: serialNumberDef, value: .text("SN-12345"), toAssetID: fridge.id)

        XCTAssertEqual(myHouse.descendants, [fridge])
        XCTAssertEqual(myHouse.value(for: roofDef.id)?.value, .number(12))
        XCTAssertEqual(fridge.customProperties.first?.value?.value, .text("SN-12345"))
    }
}
