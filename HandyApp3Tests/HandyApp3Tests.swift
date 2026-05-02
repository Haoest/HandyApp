//
//  HandyApp3Tests.swift
//  HandyApp3Tests
//
//  Created by Hao Deng on 5/2/26.
//

import XCTest
@testable import HandyApp3

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

    // MARK: - Category Tests

    func testCreateCategory() {
        let cat = store.createCategory(name: "House")
        XCTAssertEqual(store.allCategories.count, 1)
        XCTAssertEqual(cat.name, "House")
    }

    func testUpdateCategory() throws {
        let cat = store.createCategory(name: "Old Name")
        try store.updateCategory(id: cat.id, name: "House")
        XCTAssertEqual(store.categories[cat.id]?.name, "House")
    }

    func testDeleteCategory() throws {
        let cat = store.createCategory(name: "House")
        try store.deleteCategory(id: cat.id)
        XCTAssertNil(store.categories[cat.id])
    }

    func testDeleteCategoryAlsoDeletesItsAssets() throws {
        let cat = store.createCategory(name: "House")
        let asset = try store.createAsset(name: "My House", categoryID: cat.id)
        try store.deleteCategory(id: cat.id)
        XCTAssertNil(store.assets[asset.id])
    }

    func testDeleteCategoryNotFoundThrows() {
        XCTAssertThrowsError(try store.deleteCategory(id: UUID())) { error in
            if case AssetStoreError.categoryNotFound = error { } else { XCTFail("Wrong error") }
        }
    }

    // MARK: - PropertyDefinition on Category Tests

    func testAddPropertyDefinitionToCategory() throws {
        let cat = store.createCategory(name: "Car")
        let def = PropertyDefinition(name: "Engine Oil Type", type: .basic(.text))
        try store.addPropertyDefinition(def, toCategoryID: cat.id)
        XCTAssertEqual(cat.propertyDefinitions.count, 1)
        XCTAssertEqual(cat.propertyDefinitions.first?.name, "Engine Oil Type")
    }

    func testUpdatePropertyDefinition() throws {
        let cat = store.createCategory(name: "Car")
        let def = PropertyDefinition(name: "Oil Type", type: .basic(.text))
        try store.addPropertyDefinition(def, toCategoryID: cat.id)
        try store.updatePropertyDefinition(id: def.id, inCategoryID: cat.id, name: "Engine Oil Type", type: .basic(.number))
        let updated = cat.propertyDefinitions.first!
        XCTAssertEqual(updated.name, "Engine Oil Type")
        XCTAssertEqual(updated.type, .basic(.number))
    }

    func testRemovePropertyDefinitionAlsoCleansAssetValues() throws {
        let cat = store.createCategory(name: "Car")
        let def = PropertyDefinition(name: "Tire Pressure", type: .basic(.number))
        try store.addPropertyDefinition(def, toCategoryID: cat.id)
        let asset = try store.createAsset(name: "Camry", categoryID: cat.id)
        try store.setPropertyValue(.number(32), forDefinitionID: def.id, onAssetID: asset.id)
        XCTAssertEqual(asset.propertyValues.count, 1)
        try store.removePropertyDefinition(id: def.id, fromCategoryID: cat.id)
        XCTAssertEqual(asset.propertyValues.count, 0)
        XCTAssertEqual(cat.propertyDefinitions.count, 0)
    }

    // MARK: - Asset Tests

    func testCreateAsset() throws {
        let cat = store.createCategory(name: "Appliance")
        let asset = try store.createAsset(name: "Refrigerator", categoryID: cat.id)
        XCTAssertEqual(store.allAssets.count, 1)
        XCTAssertEqual(asset.category, cat)
    }

    func testCreateAssetUnknownCategoryThrows() {
        XCTAssertThrowsError(try store.createAsset(name: "X", categoryID: UUID())) { error in
            if case AssetStoreError.categoryNotFound = error { } else { XCTFail("Wrong error") }
        }
    }

    func testUpdateAsset() throws {
        let cat = store.createCategory(name: "Car")
        let asset = try store.createAsset(name: "Old Car", categoryID: cat.id)
        try store.updateAsset(id: asset.id, name: "2022 Camry")
        XCTAssertEqual(store.assets[asset.id]?.name, "2022 Camry")
    }

    func testDeleteAsset() throws {
        let cat = store.createCategory(name: "Car")
        let asset = try store.createAsset(name: "Camry", categoryID: cat.id)
        try store.deleteAsset(id: asset.id)
        XCTAssertNil(store.assets[asset.id])
    }

    func testAssetsInCategory() throws {
        let car = store.createCategory(name: "Car")
        let house = store.createCategory(name: "House")
        try store.createAsset(name: "Camry", categoryID: car.id)
        try store.createAsset(name: "My House", categoryID: house.id)
        let carAssets = try store.assets(inCategoryID: car.id)
        XCTAssertEqual(carAssets.count, 1)
        XCTAssertEqual(carAssets.first?.name, "Camry")
    }

    // MARK: - PropertyValue: Basic Types

    func testSetTextPropertyValue() throws {
        let cat = store.createCategory(name: "Car")
        let def = PropertyDefinition(name: "Oil Type", type: .basic(.text))
        try store.addPropertyDefinition(def, toCategoryID: cat.id)
        let asset = try store.createAsset(name: "Camry", categoryID: cat.id)
        try store.setPropertyValue(.text("5W-30"), forDefinitionID: def.id, onAssetID: asset.id)
        XCTAssertEqual(asset.value(for: def.id)?.value, .text("5W-30"))
    }

    func testSetNumberPropertyValue() throws {
        let cat = store.createCategory(name: "Car")
        let def = PropertyDefinition(name: "Tire Pressure", type: .basic(.number))
        try store.addPropertyDefinition(def, toCategoryID: cat.id)
        let asset = try store.createAsset(name: "Camry", categoryID: cat.id)
        try store.setPropertyValue(.number(32.5), forDefinitionID: def.id, onAssetID: asset.id)
        XCTAssertEqual(asset.value(for: def.id)?.value, .number(32.5))
    }

    func testSetCurrencyPropertyValue() throws {
        let cat = store.createCategory(name: "Appliance")
        let def = PropertyDefinition(name: "Purchase Price", type: .basic(.currency))
        try store.addPropertyDefinition(def, toCategoryID: cat.id)
        let asset = try store.createAsset(name: "Washer", categoryID: cat.id)
        try store.setPropertyValue(.currency(Decimal(799.99)), forDefinitionID: def.id, onAssetID: asset.id)
        XCTAssertEqual(asset.value(for: def.id)?.value, .currency(Decimal(799.99)))
    }

    func testSetDatePropertyValue() throws {
        let cat = store.createCategory(name: "Appliance")
        let def = PropertyDefinition(name: "Purchase Date", type: .basic(.date))
        try store.addPropertyDefinition(def, toCategoryID: cat.id)
        let asset = try store.createAsset(name: "Washer", categoryID: cat.id)
        let date = Date(timeIntervalSince1970: 1_000_000)
        try store.setPropertyValue(.date(date), forDefinitionID: def.id, onAssetID: asset.id)
        XCTAssertEqual(asset.value(for: def.id)?.value, .date(date))
    }

    func testOverwritePropertyValue() throws {
        let cat = store.createCategory(name: "Car")
        let def = PropertyDefinition(name: "Oil Type", type: .basic(.text))
        try store.addPropertyDefinition(def, toCategoryID: cat.id)
        let asset = try store.createAsset(name: "Camry", categoryID: cat.id)
        try store.setPropertyValue(.text("5W-30"), forDefinitionID: def.id, onAssetID: asset.id)
        try store.setPropertyValue(.text("0W-20"), forDefinitionID: def.id, onAssetID: asset.id)
        XCTAssertEqual(asset.propertyValues.count, 1)
        XCTAssertEqual(asset.value(for: def.id)?.value, .text("0W-20"))
    }

    func testTypeMismatchThrows() throws {
        let cat = store.createCategory(name: "Car")
        let def = PropertyDefinition(name: "Oil Type", type: .basic(.text))
        try store.addPropertyDefinition(def, toCategoryID: cat.id)
        let asset = try store.createAsset(name: "Camry", categoryID: cat.id)
        XCTAssertThrowsError(
            try store.setPropertyValue(.number(5), forDefinitionID: def.id, onAssetID: asset.id)
        ) { error in
            if case AssetStoreError.typeMismatch(let expected, _) = error {
                XCTAssertEqual(expected, "text")
            } else { XCTFail("Wrong error: \(error)") }
        }
    }

    func testRemovePropertyValue() throws {
        let cat = store.createCategory(name: "Car")
        let def = PropertyDefinition(name: "Oil Type", type: .basic(.text))
        try store.addPropertyDefinition(def, toCategoryID: cat.id)
        let asset = try store.createAsset(name: "Camry", categoryID: cat.id)
        try store.setPropertyValue(.text("5W-30"), forDefinitionID: def.id, onAssetID: asset.id)
        try store.removePropertyValue(forDefinitionID: def.id, fromAssetID: asset.id)
        XCTAssertNil(asset.value(for: def.id))
    }

    // MARK: - Composite Type Tests

    func testCreateGlobalCompositeType() {
        let insuranceType = store.createCompositeType(
            name: "Insurance Info",
            fields: [
                PropertyDefinition(name: "Vendor", type: .basic(.text)),
                PropertyDefinition(name: "Annual Premium", type: .basic(.currency))
            ],
            scope: .global
        )
        XCTAssertEqual(store.allCompositeTypes.count, 1)
        XCTAssertEqual(insuranceType.fields.count, 2)
    }

    func testCompositeTypeAvailableGlobally() throws {
        let house = store.createCategory(name: "House")
        let car = store.createCategory(name: "Car")
        store.createCompositeType(name: "Insurance Info", fields: [], scope: .global)
        let houseTypes = try store.compositeTypes(availableForCategoryID: house.id)
        let carTypes = try store.compositeTypes(availableForCategoryID: car.id)
        XCTAssertEqual(houseTypes.count, 1)
        XCTAssertEqual(carTypes.count, 1)
    }

    func testCompositeTypeCategoryScoped() throws {
        let house = store.createCategory(name: "House")
        let car = store.createCategory(name: "Car")
        store.createCompositeType(name: "Roof Info", fields: [], scope: .category(house))
        let houseTypes = try store.compositeTypes(availableForCategoryID: house.id)
        let carTypes = try store.compositeTypes(availableForCategoryID: car.id)
        XCTAssertEqual(houseTypes.count, 1)
        XCTAssertEqual(carTypes.count, 0)
    }

    func testSetCompositePropertyValue() throws {
        let house = store.createCategory(name: "House")
        let insuranceType = store.createCompositeType(
            name: "Insurance Info",
            fields: [
                PropertyDefinition(name: "Vendor", type: .basic(.text)),
                PropertyDefinition(name: "Annual Premium", type: .basic(.currency))
            ],
            scope: .global
        )
        let def = PropertyDefinition(name: "Insurance", type: .composite(insuranceType))
        try store.addPropertyDefinition(def, toCategoryID: house.id)
        let asset = try store.createAsset(name: "My House", categoryID: house.id)
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
        let house = store.createCategory(name: "House")
        let insuranceType = store.createCompositeType(
            name: "Insurance Info",
            fields: [PropertyDefinition(name: "Vendor", type: .basic(.text))],
            scope: .global
        )
        let def = PropertyDefinition(name: "Insurance", type: .composite(insuranceType))
        try store.addPropertyDefinition(def, toCategoryID: house.id)
        let asset = try store.createAsset(name: "My House", categoryID: house.id)
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
        let house = store.createCategory(name: "House")
        let insuranceType = store.createCompositeType(
            name: "Insurance Info",
            fields: [PropertyDefinition(name: "Vendor", type: .basic(.text))],
            scope: .global
        )
        let def = PropertyDefinition(name: "Insurance", type: .composite(insuranceType))
        try store.addPropertyDefinition(def, toCategoryID: house.id)
        let asset = try store.createAsset(name: "My House", categoryID: house.id)
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

    // MARK: - Nested Composite Type Tests

    func testNestedCompositeType() throws {
        let house = store.createCategory(name: "House")

        let addressType = store.createCompositeType(
            name: "Address",
            fields: [
                PropertyDefinition(name: "Street", type: .basic(.text)),
                PropertyDefinition(name: "City", type: .basic(.text)),
                PropertyDefinition(name: "Zip", type: .basic(.text))
            ],
            scope: .global
        )

        let insuranceType = store.createCompositeType(
            name: "Insurance Details",
            fields: [
                PropertyDefinition(name: "Vendor", type: .basic(.text)),
                PropertyDefinition(name: "Mailing Address", type: .composite(addressType))
            ],
            scope: .global
        )

        let def = PropertyDefinition(name: "Insurance", type: .composite(insuranceType))
        try store.addPropertyDefinition(def, toCategoryID: house.id)
        let asset = try store.createAsset(name: "My House", categoryID: house.id)

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
        let house = store.createCategory(name: "House")
        let addressType = store.createCompositeType(
            name: "Address",
            fields: [PropertyDefinition(name: "Zip", type: .basic(.text))],
            scope: .global
        )
        let insuranceType = store.createCompositeType(
            name: "Insurance",
            fields: [PropertyDefinition(name: "Mailing Address", type: .composite(addressType))],
            scope: .global
        )
        let def = PropertyDefinition(name: "Insurance", type: .composite(insuranceType))
        try store.addPropertyDefinition(def, toCategoryID: house.id)
        let asset = try store.createAsset(name: "My House", categoryID: house.id)

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

    // MARK: - Real-world scenario: House asset

    func testHouseAssetScenario() throws {
        let house = store.createCategory(name: "House")
        try store.addPropertyDefinition(
            PropertyDefinition(name: "Roof Age (Years)", type: .basic(.number)),
            toCategoryID: house.id
        )
        try store.addPropertyDefinition(
            PropertyDefinition(name: "HVAC Filter Size", type: .basic(.text)),
            toCategoryID: house.id
        )
        let insuranceType = store.createCompositeType(
            name: "Insurance Info",
            fields: [
                PropertyDefinition(name: "Vendor", type: .basic(.text)),
                PropertyDefinition(name: "Annual Premium", type: .basic(.currency))
            ],
            scope: .category(house)
        )
        let insuranceDef = PropertyDefinition(name: "Insurance", type: .composite(insuranceType))
        try store.addPropertyDefinition(insuranceDef, toCategoryID: house.id)

        let myHouse = try store.createAsset(name: "123 Main St", categoryID: house.id)
        let roofDef = house.propertyDefinitions.first { $0.name == "Roof Age (Years)" }!
        let filterDef = house.propertyDefinitions.first { $0.name == "HVAC Filter Size" }!

        try store.setPropertyValue(.number(12), forDefinitionID: roofDef.id, onAssetID: myHouse.id)
        try store.setPropertyValue(.text("20x25x1"), forDefinitionID: filterDef.id, onAssetID: myHouse.id)
        try store.setPropertyValue(
            .composite(["Vendor": .text("State Farm"), "Annual Premium": .currency(Decimal(1500))]),
            forDefinitionID: insuranceDef.id,
            onAssetID: myHouse.id
        )

        XCTAssertEqual(myHouse.propertyValues.count, 3)
        XCTAssertEqual(myHouse.value(for: roofDef.id)?.value, .number(12))
        XCTAssertEqual(myHouse.value(for: filterDef.id)?.value, .text("20x25x1"))

        let houseTypes = try store.compositeTypes(availableForCategoryID: house.id)
        XCTAssertTrue(houseTypes.contains { $0.name == "Insurance Info" })
    }

    // MARK: - Real-world scenario: Car asset

    func testCarAssetScenario() throws {
        let car = store.createCategory(name: "Car")
        try store.addPropertyDefinition(
            PropertyDefinition(name: "Engine Oil Type", type: .basic(.text)),
            toCategoryID: car.id
        )
        try store.addPropertyDefinition(
            PropertyDefinition(name: "Tire Pressure (PSI)", type: .basic(.number)),
            toCategoryID: car.id
        )
        try store.addPropertyDefinition(
            PropertyDefinition(name: "Oil Filter Part Number", type: .basic(.text)),
            toCategoryID: car.id
        )

        let camry = try store.createAsset(name: "2022 Toyota Camry", categoryID: car.id)
        for def in car.propertyDefinitions {
            switch def.name {
            case "Engine Oil Type":
                try store.setPropertyValue(.text("0W-20"), forDefinitionID: def.id, onAssetID: camry.id)
            case "Tire Pressure (PSI)":
                try store.setPropertyValue(.number(35), forDefinitionID: def.id, onAssetID: camry.id)
            case "Oil Filter Part Number":
                try store.setPropertyValue(.text("04152-YZZA6"), forDefinitionID: def.id, onAssetID: camry.id)
            default: break
            }
        }
        XCTAssertEqual(camry.propertyValues.count, 3)
    }

    // MARK: - Real-world scenario: Appliance asset

    func testApplianceAssetScenario() throws {
        let appliance = store.createCategory(name: "Appliance")
        try store.addPropertyDefinition(
            PropertyDefinition(name: "Purchase Date", type: .basic(.date)),
            toCategoryID: appliance.id
        )
        try store.addPropertyDefinition(
            PropertyDefinition(name: "Purchase Price", type: .basic(.currency)),
            toCategoryID: appliance.id
        )
        let warrantyType = store.createCompositeType(
            name: "Warranty Info",
            fields: [
                PropertyDefinition(name: "Provider", type: .basic(.text)),
                PropertyDefinition(name: "Expiry Date", type: .basic(.date)),
                PropertyDefinition(name: "Coverage Amount", type: .basic(.currency))
            ],
            scope: .global
        )
        let warrantyDef = PropertyDefinition(name: "Warranty", type: .composite(warrantyType))
        try store.addPropertyDefinition(warrantyDef, toCategoryID: appliance.id)

        let dimType = store.createCompositeType(
            name: "Dimensions",
            fields: [
                PropertyDefinition(name: "Width (in)", type: .basic(.number)),
                PropertyDefinition(name: "Height (in)", type: .basic(.number)),
                PropertyDefinition(name: "Depth (in)", type: .basic(.number))
            ],
            scope: .global
        )
        let dimDef = PropertyDefinition(name: "Dimensions", type: .composite(dimType))
        try store.addPropertyDefinition(dimDef, toCategoryID: appliance.id)

        let washer = try store.createAsset(name: "Samsung Washer WF45", categoryID: appliance.id)
        let purchaseDateDef = appliance.propertyDefinitions.first { $0.name == "Purchase Date" }!
        let priceDef = appliance.propertyDefinitions.first { $0.name == "Purchase Price" }!

        try store.setPropertyValue(.date(Date(timeIntervalSince1970: 1_700_000_000)), forDefinitionID: purchaseDateDef.id, onAssetID: washer.id)
        try store.setPropertyValue(.currency(Decimal(899)), forDefinitionID: priceDef.id, onAssetID: washer.id)
        try store.setPropertyValue(
            .composite([
                "Provider": .text("Samsung Care"),
                "Expiry Date": .date(Date(timeIntervalSince1970: 1_900_000_000)),
                "Coverage Amount": .currency(Decimal(899))
            ]),
            forDefinitionID: warrantyDef.id,
            onAssetID: washer.id
        )
        try store.setPropertyValue(
            .composite(["Width (in)": .number(27), "Height (in)": .number(39), "Depth (in)": .number(31)]),
            forDefinitionID: dimDef.id,
            onAssetID: washer.id
        )

        XCTAssertEqual(washer.propertyValues.count, 4)
    }

    // MARK: - isRequired / optional field tests

    func testOptionalFieldMayBeOmitted() throws {
        let ct = store.createCompositeType(
            name: "Contact",
            fields: [
                PropertyDefinition(name: "Name",  type: .basic(.text), isRequired: true),
                PropertyDefinition(name: "Notes", type: .basic(.text), isRequired: false),
            ]
        )
        // Notes omitted — should not throw
        XCTAssertNoThrow(
            try store.validate(stored: .composite(["Name": .text("Alice")]),
                               against: .composite(ct), definitionName: "Contact")
        )
    }

    func testRequiredFieldMissingThrows() throws {
        let ct = store.createCompositeType(
            name: "Contact",
            fields: [
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

    // MARK: - BuiltInTypes / seedBuiltInTypes tests

    func testSeedBuiltInTypes() {
        store.seedBuiltInTypes()
        XCTAssertTrue(store.allCompositeTypes.contains { $0.name == "W × H" })
    }

    func testSeedBuiltInTypesIsIdempotent() {
        store.seedBuiltInTypes()
        store.seedBuiltInTypes()
        XCTAssertEqual(store.allCompositeTypes.filter { $0.name == "W × H" }.count, 1)
    }

    func testWidthByHeightRequiredFieldsOnly() throws {
        store.seedBuiltInTypes()
        let wxh = store.allCompositeTypes.first { $0.name == "W × H" }!
        // Unit omitted — optional, so this must pass
        XCTAssertNoThrow(
            try store.validate(stored: .composite(["Width": .number(1920), "Height": .number(1080)]),
                               against: .composite(wxh), definitionName: "Screen")
        )
    }

    func testWidthByHeightWithOptionalUnit() throws {
        store.seedBuiltInTypes()
        let wxh = store.allCompositeTypes.first { $0.name == "W × H" }!
        let payload: StoredValue = .composite([
            "Width":  .number(27),
            "Height": .number(39),
            "Unit":   .text(UnitIndex.inch.symbol),   // "in"
        ])
        XCTAssertNoThrow(
            try store.validate(stored: payload, against: .composite(wxh), definitionName: "Dimension")
        )
    }

    func testWidthByHeightMissingWidthThrows() throws {
        store.seedBuiltInTypes()
        let wxh = store.allCompositeTypes.first { $0.name == "W × H" }!
        XCTAssertThrowsError(
            try store.validate(stored: .composite(["Height": .number(1080)]),
                               against: .composite(wxh), definitionName: "Screen")
        ) { error in
            if case AssetStoreError.compositeFieldMismatch(let details) = error {
                XCTAssertTrue(details.contains("Width"))
            } else { XCTFail("Wrong error: \(error)") }
        }
    }

    func testWidthByHeightWrongTypeThrows() throws {
        store.seedBuiltInTypes()
        let wxh = store.allCompositeTypes.first { $0.name == "W × H" }!
        XCTAssertThrowsError(
            try store.validate(stored: .composite(["Width": .text("wide"), "Height": .number(100)]),
                               against: .composite(wxh), definitionName: "Screen")
        ) { error in
            if case AssetStoreError.typeMismatch = error { } else { XCTFail("Wrong error: \(error)") }
        }
    }

    func testWidthByHeightOnAssetWithFeetUnit() throws {
        store.seedBuiltInTypes()
        let wxh = store.allCompositeTypes.first { $0.name == "W × H" }!
        let house = store.createCategory(name: "House")
        let dimDef = PropertyDefinition(name: "Room Size", type: .composite(wxh))
        try store.addPropertyDefinition(dimDef, toCategoryID: house.id)
        let asset = try store.createAsset(name: "Living Room", categoryID: house.id)

        try store.setPropertyValue(
            .composite(["Width": .number(18), "Height": .number(14), "Unit": .text(UnitIndex.feet.symbol)]),
            forDefinitionID: dimDef.id,
            onAssetID: asset.id
        )
        guard case .composite(let v) = asset.value(for: dimDef.id)?.value else {
            XCTFail("Expected composite value"); return
        }
        XCTAssertEqual(v["Width"],  .number(18))
        XCTAssertEqual(v["Height"], .number(14))
        XCTAssertEqual(v["Unit"],   .text("ft"))
    }

    // MARK: - UnitIndex tests

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
}
