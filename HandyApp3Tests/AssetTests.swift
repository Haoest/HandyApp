import XCTest
@testable import HandyApp3

final class AssetTests: XCTestCase {

    var store: AssetStore!

    override func setUp() {
        super.setUp()
        store = AssetStore()
    }

    private func makeCategory(name: String = "Test") -> AssetCategory {
        AssetCategory(name: name)
    }

    private func makeAsset(name: String = "Asset", baseProperties: [AssetProperty] = [], customProperties: [AssetProperty] = []) -> Asset {
        Asset(name: name, category: makeCategory(), baseProperties: baseProperties, customProperties: customProperties)
    }

    // value(for:) searches base properties before custom properties.
    func testValueLookupPrefersBaseOverCustom() {
        let baseDef = PropertyDefinition(name: "Color", type: .basic(.text))
        let customDef = PropertyDefinition(name: "Notes", type: .basic(.text))
        let baseProperty = AssetProperty(definition: baseDef, value: .text("Red"))
        let customProperty = AssetProperty(definition: customDef, value: .text("Custom note"))

        let asset = makeAsset(baseProperties: [baseProperty], customProperties: [customProperty])

        XCTAssertEqual(asset.value(for: baseDef.id), .text("Red"))
        XCTAssertEqual(asset.value(for: customDef.id), .text("Custom note"))
        XCTAssertNil(asset.value(for: UUID()))
    }

    // ancestors returns the chain from root down to (but not including) self.
    func testAncestorsOrdersFromRootToParent() {
        let grandparent = makeAsset(name: "Grandparent")
        let parent = makeAsset(name: "Parent")
        let child = makeAsset(name: "Child")

        grandparent._addChild(parent)
        parent._addChild(child)

        XCTAssertEqual(child.ancestors.map(\.name), ["Grandparent", "Parent"])
        XCTAssertTrue(grandparent.ancestors.isEmpty)
    }

    //automobile test
    func testAutomobileAssetWithCustomPropertyAndRandomizedValues() throws {
        store.seedBuiltInCategories()

        let category = try XCTUnwrap(store.allCategories.first { $0.name == SystemCategory.automobile.rawValue })
        let asset = try store.createAsset(name: "My Car", categoryID: category.id)

        // Randomize template property values
        var expectedValues: [String: StoredValue] = [:]
        for prop in asset.baseProperties {
            let value: StoredValue
            switch prop.definition.type {
            case .basic(.text):   value = .text(UUID().uuidString)
            case .basic(.number): value = .number(Double.random(in: 1900...2100))
            default: continue
            }
            try store.setPropertyValue(value, forDefinitionID: prop.definition.id, onAssetID: asset.id)
            expectedValues[prop.definition.name] = value
        }

        // Add custom "Purchase Price" property
        let priceDef = PropertyDefinition(name: "Purchase Price", type: .basic(.currency))
        let priceValue: StoredValue = .currency(10000)
        try store.addCustomProperty(definition: priceDef, value: priceValue, toAssetID: asset.id)
        expectedValues["Purchase Price"] = priceValue

        // Verify all template properties are present with correct values
        let templateNames = Set(category.propertyTemplates.map { $0.definition.name })
        XCTAssertTrue(templateNames.isSubset(of: Set(asset.baseProperties.map { $0.definition.name })))
        for prop in asset.baseProperties {
            XCTAssertEqual(prop.value, expectedValues[prop.definition.name], "Value mismatch for '\(prop.definition.name)'")
        }

        // Verify custom property is present with correct value
        let customProp = try XCTUnwrap(asset.customProperties.first { $0.definition.name == "Purchase Price" })
        XCTAssertEqual(customProp.definition.type, .basic(.currency))
        XCTAssertEqual(customProp.value, priceValue)
    }

    //residential housing test
    func testResidentialHousingAssetMatchesTemplate() throws {
        store.seedBuiltInCategories()

        let categoryName = SystemCategory.residentialHousing.rawValue
        let category = try XCTUnwrap(store.allCategories.first { $0.name == categoryName })
        let asset = try store.createAsset(name: "My House", categoryID: category.id)

        let templateNames = Set(category.propertyTemplates.map { $0.definition.name })
        let assetPropertyNames = Set(asset.baseProperties.map { $0.definition.name })
        XCTAssertEqual(assetPropertyNames, templateNames)

        let templateTypes = Dictionary(uniqueKeysWithValues: category.propertyTemplates.map { ($0.definition.name, $0.definition.type) })
        for prop in asset.baseProperties {
            XCTAssertEqual(prop.definition.type, templateTypes[prop.definition.name], "Type mismatch for '\(prop.definition.name)'")
        }

        XCTAssertTrue(asset.baseProperties.allSatisfy { $0.value == nil })
    }

    // appliance base properties match template and sortOrder starts at 0, incremented by sortOrderIncrement
    func testApplianceBasePropertiesMatchTemplateWithSortOrder() throws {
        store.seedBuiltInCategories()

        let category = try XCTUnwrap(store.allCategories.first { $0.name == SystemCategory.appliance.rawValue })
        let asset = try store.createAsset(name: "My Appliance", categoryID: category.id)

        XCTAssertEqual(asset.baseProperties.count, category.propertyTemplates.count)

        for (index, (assetProp, templateProp)) in zip(asset.baseProperties, category.propertyTemplates).enumerated() {
            XCTAssertEqual(assetProp.definition.name, templateProp.definition.name, "Name mismatch at index \(index)")
            XCTAssertEqual(assetProp.sortOrder, Double(index) * AssetProperty.sortOrderIncrement, "sortOrder mismatch at index \(index)")
        }
    }

    // range appliance with power source, color, and installation type
    func testRangeAssetWithPowerSourceAndCustomAttributes() throws {
        store.seedBuiltInCategories()

        let category = try XCTUnwrap(store.allCategories.first { $0.name == SystemCategory.range.rawValue })
        let asset = try store.createAsset(name: "Range", categoryID: category.id)

        let powerSourceProp = try XCTUnwrap(asset.baseProperties.first { $0.definition.name == "Power source" })
        try store.setPropertyValue(.text("Natural Gas"), forDefinitionID: powerSourceProp.definition.id, onAssetID: asset.id)

        try store.addCustomProperty(definition: PropertyDefinition(name: "Color", type: .basic(.text)), value: .text("black"), toAssetID: asset.id)
        try store.addCustomProperty(definition: PropertyDefinition(name: "Installation type", type: .basic(.text)), value: .text("slide in"), toAssetID: asset.id)

        XCTAssertEqual(asset.value(for: powerSourceProp.definition.id), .text("Natural Gas"))

        let colorProp = try XCTUnwrap(asset.customProperties.first { $0.definition.name == "Color" })
        XCTAssertEqual(colorProp.value, .text("black"))

        let installProp = try XCTUnwrap(asset.customProperties.first { $0.definition.name == "Installation type" })
        XCTAssertEqual(installProp.value, .text("slide in"))
    }

    // descendants returns all nodes in the subtree (breadth-first, excluding self).
    func testDescendantsIncludesAllSubtreeNodes() {
        let root = makeAsset(name: "Root")
        let childA = makeAsset(name: "A")
        let childB = makeAsset(name: "B")
        let grandchild = makeAsset(name: "C")

        root._addChild(childA)
        root._addChild(childB)
        childA._addChild(grandchild)

        let names = root.descendants.map(\.name)
        XCTAssertEqual(names, ["A", "B", "C"])
    }
}
