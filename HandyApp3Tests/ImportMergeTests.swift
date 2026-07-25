import XCTest
@testable import HandyApp3

/// Coverage for merge-on-import (`AssetStore.importJSON`): incoming records the local
/// store is missing get added; everything already present (by uuid) is left untouched.
/// Many tests doctor an exported JSON via `JSONSerialization` to fabricate "incoming"
/// records the store API alone can't produce (fixed ids, dangling references, etc.),
/// then re-import it — either into the same store (a uuid collision / "present locally"
/// merge) or into a second, empty store standing in for another device ("absent
/// locally").
final class ImportMergeTests: XCTestCase {

    var store: AssetStore!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        AssetStore.baseDirOverride = tempDir
        store = AssetStore()
    }

    override func tearDown() {
        super.tearDown()
        AssetStore.baseDirOverride = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - JSON doctoring helpers

    private func withJSON(_ data: Data, _ transform: (inout [String: Any]) throws -> Void) throws -> Data {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try transform(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func mutatingCategory(id: UUID, in data: Data, _ transform: (inout [String: Any]) -> Void) throws -> Data {
        try withJSON(data) { json in
            guard var categories = json["categories"] as? [[String: Any]] else { return }
            for i in categories.indices where (categories[i]["id"] as? String) == id.uuidString {
                transform(&categories[i])
            }
            json["categories"] = categories
        }
    }

    private func mutatingAsset(id: UUID, in data: Data, _ transform: (inout [String: Any]) -> Void) throws -> Data {
        try withJSON(data) { json in
            guard var assets = json["assets"] as? [[String: Any]] else { return }
            for i in assets.indices where (assets[i]["id"] as? String) == id.uuidString {
                transform(&assets[i])
            }
            json["assets"] = assets
        }
    }

    private func removingAsset(id: UUID, from data: Data) throws -> Data {
        try withJSON(data) { json in
            guard var assets = json["assets"] as? [[String: Any]] else { return }
            assets.removeAll { ($0["id"] as? String) == id.uuidString }
            json["assets"] = assets
        }
    }

    private func addingAsset(_ assetJSON: [String: Any], to data: Data) throws -> Data {
        try withJSON(data) { json in
            var assets = json["assets"] as? [[String: Any]] ?? []
            assets.append(assetJSON)
            json["assets"] = assets
        }
    }

    private func fabricatedAssetJSON(id: UUID, name: String, categoryID: UUID, parentID: UUID?) -> [String: Any] {
        let now = ISO8601DateFormatter().string(from: Date())
        var dict: [String: Any] = [
            "id": id.uuidString,
            "name": name,
            "categoryID": categoryID.uuidString,
            "baseProperties": [],
            "customProperties": [],
            "photos": [],
            "events": [],
            "transactions": [],
            "isDeleted": false,
            "createdDate": now,
            "modifiedDate": now,
        ]
        if let parentID { dict["parentID"] = parentID.uuidString }
        return dict
    }

    private func fabricatedPhotoJSON(id: UUID, fullBytes: Data, thumbBytes: Data) -> [String: Any] {
        [
            "id": id.uuidString,
            "caption": "",
            "addedDate": ISO8601DateFormatter().string(from: Date()),
            "fullImage": fullBytes.base64EncodedString(),
            "thumbnail": thumbBytes.base64EncodedString(),
        ]
    }

    /// A second, empty store in its own temp directory — stands in for another device.
    private func makeSecondStore() -> AssetStore {
        let dir2 = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        AssetStore.baseDirOverride = dir2
        let s = AssetStore()
        addTeardownBlock {
            AssetStore.baseDirOverride = self.tempDir
            try? FileManager.default.removeItem(at: dir2)
        }
        return s
    }

    // MARK: - Categories

    func testMergeAddsCategoryAbsentLocally() throws {
        let cat = try store.createCategory(name: "Source Category", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text)))
        ])
        let export = try XCTUnwrap(store.exportJSON())

        let store2 = makeSecondStore()
        try store2.importJSON(data: export)

        let merged = try XCTUnwrap(store2.categories[cat.id])
        XCTAssertEqual(merged.name, "Source Category")
        XCTAssertEqual(merged.propertyTemplates.count, 1)
    }

    func testMergeKeepsLocalCategoryNameAndIconOnUUIDCollision() throws {
        let cat = try store.createCategory(name: "Original", iconName: "car")
        let export = try XCTUnwrap(store.exportJSON())
        let doctored = try mutatingCategory(id: cat.id, in: export) { dict in
            dict["name"] = "Renamed"
            dict["iconName"] = "bolt"
        }

        try store.importJSON(data: doctored)

        let merged = try XCTUnwrap(store.categories[cat.id])
        XCTAssertEqual(merged.name, "Original", "local category name must survive a uuid collision")
        XCTAssertEqual(merged.iconName, "car")
    }

    func testMergeAppendsTemplatePropertyMissingLocally() throws {
        let cat = try store.createCategory(name: "Vehicle", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text)), sortOrder: 0)
        ])
        let newDefID = UUID()
        let export = try XCTUnwrap(store.exportJSON())
        let doctored = try mutatingCategory(id: cat.id, in: export) { dict in
            var templates = dict["propertyTemplates"] as? [[String: Any]] ?? []
            templates.append([
                "id": UUID().uuidString,
                "definition": [
                    "id": newDefID.uuidString, "name": "Model",
                    "type": ["kind": "basic", "basicType": "text"], "isRequired": false,
                ],
                "sortOrder": 0,
            ])
            dict["propertyTemplates"] = templates
        }

        try store.importJSON(data: doctored)

        let merged = try XCTUnwrap(store.categories[cat.id])
        XCTAssertEqual(merged.propertyTemplates.count, 2)
        let makeOrder = merged.propertyTemplates.first { $0.definition.name == "Make" }?.sortOrder ?? 0
        let modelOrder = merged.propertyTemplates.first { $0.definition.id == newDefID }?.sortOrder ?? 0
        XCTAssertGreaterThan(modelOrder, makeOrder, "appended template must sort after the existing one, not tie at 0")
    }

    func testMergeSkipsTemplateAlreadyPresentByDefinitionID() throws {
        let cat = try store.createCategory(name: "Vehicle", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text)))
        ])
        let export = try XCTUnwrap(store.exportJSON())
        let doctored = try mutatingCategory(id: cat.id, in: export) { dict in
            guard var templates = dict["propertyTemplates"] as? [[String: Any]], var dup = templates.first else { return }
            dup["id"] = UUID().uuidString   // distinct AssetProperty.id, same embedded definition.id
            templates.append(dup)
            dict["propertyTemplates"] = templates
        }

        try store.importJSON(data: doctored)

        let merged = try XCTUnwrap(store.categories[cat.id])
        XCTAssertEqual(merged.propertyTemplates.count, 1,
                       "a template sharing an existing definition.id must be skipped even with a new AssetProperty.id")
    }

    /// `BuiltInTypes.applianceBaseDefinitions` is a shared `static let` reused across four
    /// built-in categories, so the same `definition.id` legitimately appears in more than
    /// one category. The per-category dedupe must not let one category's existing property
    /// block an unrelated category from receiving the same definition id.
    func testMergeScopesDefinitionDedupePerCategory() throws {
        let sharedDefID = UUID()
        let sharedDef = PropertyDefinition(id: sharedDefID, name: "Make", type: .basic(.text))
        let catA = try store.createCategory(name: "Appliance", propertyTemplates: [AssetProperty(definition: sharedDef)])
        let catB = try store.createCategory(name: "Refrigerator")

        let export = try XCTUnwrap(store.exportJSON())
        let doctored = try withJSON(export) { json in
            guard var categories = json["categories"] as? [[String: Any]] else { return }
            guard let aIndex = categories.firstIndex(where: { ($0["id"] as? String) == catA.id.uuidString }),
                  let templatesA = categories[aIndex]["propertyTemplates"] as? [[String: Any]],
                  var template = templatesA.first else {
                return XCTFail("expected category A to already carry the shared template")
            }
            template["id"] = UUID().uuidString   // distinct AssetProperty.id; definition.id stays shared

            guard let bIndex = categories.firstIndex(where: { ($0["id"] as? String) == catB.id.uuidString }) else {
                return XCTFail("expected category B in export")
            }
            var templatesB = categories[bIndex]["propertyTemplates"] as? [[String: Any]] ?? []
            templatesB.append(template)
            categories[bIndex]["propertyTemplates"] = templatesB
            json["categories"] = categories
        }

        try store.importJSON(data: doctored)

        let mergedB = try XCTUnwrap(store.categories[catB.id])
        XCTAssertEqual(mergedB.propertyTemplates.count, 1,
                       "category B must receive the template even though its definition.id already exists on category A")
        XCTAssertEqual(mergedB.propertyTemplates.first?.definition.id, sharedDefID)
    }

    /// A surviving asset's soft-deleted category (present in the incoming file, absent
    /// locally) must be recovered with its real name/icon and `isDeleted` preserved,
    /// rather than falling back to a generic "Recovered" placeholder.
    func testMergeRecoversSoftDeletedCategoryForSurvivingAsset() throws {
        let cat = try store.createCategory(name: "Trailer Types", iconName: "car.2")
        let asset = try store.createAsset(name: "Utility Trailer", categoryID: cat.id)
        try store.softDeleteCategory(id: cat.id)

        let export = try XCTUnwrap(store.exportJSON())
        let store2 = makeSecondStore()
        try store2.importJSON(data: export)

        let mergedAsset = try XCTUnwrap(store2.assets[asset.id])
        XCTAssertEqual(mergedAsset.category.id, cat.id)
        XCTAssertEqual(mergedAsset.category.name, "Trailer Types",
                       "a surviving asset's soft-deleted category must be recovered with its real name")
        XCTAssertTrue(mergedAsset.category.isDeleted)
        XCTAssertTrue(store2.deletedCategories.contains { $0.id == cat.id })
    }

    func testMergeSkipsIncomingSoftDeletedCategory() throws {
        let cat = try store.createCategory(name: "Gone")
        try store.softDeleteCategory(id: cat.id)
        let export = try XCTUnwrap(store.exportJSON())

        let store2 = makeSecondStore()
        try store2.importJSON(data: export)

        XCTAssertNil(store2.categories[cat.id],
                     "a soft-deleted category with no surviving referencing asset must not be merged in")
    }

    // MARK: - Assets

    func testMergeAddsAssetAbsentLocally() throws {
        let cat = try store.createCategory(name: "Garage")
        let export = try XCTUnwrap(store.exportJSON())
        let newID = UUID()
        let doctored = try addingAsset(
            fabricatedAssetJSON(id: newID, name: "New Asset", categoryID: cat.id, parentID: nil), to: export
        )

        try store.importJSON(data: doctored)

        XCTAssertEqual(store.assets[newID]?.name, "New Asset")
    }

    func testMergeSkipsIncomingSoftDeletedAsset() throws {
        let cat = try store.createCategory(name: "Garage")
        let asset = try store.createAsset(name: "Old Car", categoryID: cat.id)
        try store.softDeleteAsset(id: asset.id)
        let export = try XCTUnwrap(store.exportJSON())

        let store2 = makeSecondStore()
        try store2.importJSON(data: export)

        XCTAssertNil(store2.assets[asset.id], "a soft-deleted incoming asset must be skipped by merge")
    }

    func testMergeKeepsLocalAssetNameAndPropertyValues() throws {
        let cat = try store.createCategory(name: "Garage", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Color", type: .basic(.text)))
        ])
        let asset = try store.createAsset(name: "Camry", categoryID: cat.id)
        try store.setPropertyValue(.text("Red"), forDefinitionID: asset.baseProperties[0].definition.id, onAssetID: asset.id)

        let export = try XCTUnwrap(store.exportJSON())
        let doctored = try mutatingAsset(id: asset.id, in: export) { dict in
            dict["name"] = "Renamed"
            guard var baseProps = dict["baseProperties"] as? [[String: Any]] else { return }
            for i in baseProps.indices {
                guard var value = baseProps[i]["value"] as? [String: Any] else { continue }
                value["value"] = "Blue"
                baseProps[i]["value"] = value
            }
            dict["baseProperties"] = baseProps
        }

        try store.importJSON(data: doctored)

        let merged = try XCTUnwrap(store.assets[asset.id])
        XCTAssertEqual(merged.name, "Camry", "local name must survive")
        XCTAssertEqual(merged.baseProperties.first?.value, .text("Red"), "local property value must survive")
    }

    func testMergeAddsMissingEventToExistingAsset() throws {
        let cat = try store.createCategory(name: "Garage")
        let asset = try store.createAsset(name: "Camry", categoryID: cat.id)
        _ = try store.addEvent(title: "Existing", date: Date(), toAssetID: asset.id)

        let export = try XCTUnwrap(store.exportJSON())
        let newEventID = UUID()
        let doctored = try mutatingAsset(id: asset.id, in: export) { dict in
            var events = dict["events"] as? [[String: Any]] ?? []
            events.append([
                "id": newEventID.uuidString, "title": "New Event",
                "date": ISO8601DateFormatter().string(from: Date()), "notes": "",
            ])
            dict["events"] = events
        }

        try store.importJSON(data: doctored)

        let merged = try XCTUnwrap(store.assets[asset.id])
        XCTAssertEqual(merged.events.count, 2)
        XCTAssertTrue(merged.events.contains { $0.id == newEventID })
    }

    func testMergeAddsMissingTransactionToExistingAsset() throws {
        let cat = try store.createCategory(name: "Garage")
        let asset = try store.createAsset(name: "Camry", categoryID: cat.id)
        _ = try store.addTransaction(details: "Existing", amount: 10, date: Date(), kind: .expense, toAssetID: asset.id)

        let export = try XCTUnwrap(store.exportJSON())
        let newTxnID = UUID()
        let doctored = try mutatingAsset(id: asset.id, in: export) { dict in
            var txns = dict["transactions"] as? [[String: Any]] ?? []
            txns.append([
                "id": newTxnID.uuidString, "details": "New Txn", "amount": "25",
                "date": ISO8601DateFormatter().string(from: Date()), "kind": "Expense", "notes": "",
            ])
            dict["transactions"] = txns
        }

        try store.importJSON(data: doctored)

        let merged = try XCTUnwrap(store.assets[asset.id])
        XCTAssertEqual(merged.transactions.count, 2)
        XCTAssertTrue(merged.transactions.contains { $0.id == newTxnID })
    }

    func testMergeAddsMissingCustomPropertyToExistingAsset() throws {
        let cat = try store.createCategory(name: "Garage")
        let asset = try store.createAsset(name: "Camry", categoryID: cat.id)
        _ = try store.addCustomProperty(definition: PropertyDefinition(name: "Existing", type: .basic(.text)), toAssetID: asset.id)

        let export = try XCTUnwrap(store.exportJSON())
        let newDefID = UUID()
        let doctored = try mutatingAsset(id: asset.id, in: export) { dict in
            var customProps = dict["customProperties"] as? [[String: Any]] ?? []
            customProps.append([
                "id": UUID().uuidString,
                "definition": [
                    "id": newDefID.uuidString, "name": "Paint Code",
                    "type": ["kind": "basic", "basicType": "text"], "isRequired": false,
                ],
                "sortOrder": 0,
            ])
            dict["customProperties"] = customProps
        }

        try store.importJSON(data: doctored)

        let merged = try XCTUnwrap(store.assets[asset.id])
        XCTAssertEqual(merged.customProperties.count, 2)
        let existingOrder = merged.customProperties.first { $0.definition.name == "Existing" }?.sortOrder ?? 0
        let newOrder = merged.customProperties.first { $0.definition.id == newDefID }?.sortOrder ?? 0
        XCTAssertGreaterThan(newOrder, existingOrder, "appended property must sort after the existing one")
    }

    func testMergeAddsMissingPhotoToExistingAssetAndWritesBytes() throws {
        let cat = try store.createCategory(name: "Garage")
        let asset = try store.createAsset(name: "Camry", categoryID: cat.id)

        let export = try XCTUnwrap(store.exportJSON())
        let photoID = UUID()
        let doctored = try mutatingAsset(id: asset.id, in: export) { dict in
            dict["photos"] = [fabricatedPhotoJSON(id: photoID, fullBytes: Data("full".utf8), thumbBytes: Data("thumb".utf8))]
        }

        try store.importJSON(data: doctored)

        let merged = try XCTUnwrap(store.assets[asset.id])
        XCTAssertEqual(merged.photos.count, 1)
        XCTAssertEqual(merged.photos.first?.id, photoID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: PhotoStorage.fullURL(id: photoID).path),
                      "merge must write embedded photo bytes for a newly merged photo")
        XCTAssertTrue(FileManager.default.fileExists(atPath: PhotoStorage.thumbURL(id: photoID).path))
    }

    func testMergeKeepsExistingAssetObjectIdentity() throws {
        let cat = try store.createCategory(name: "Garage")
        let asset = try store.createAsset(name: "Camry", categoryID: cat.id)

        let export = try XCTUnwrap(store.exportJSON())
        try store.importJSON(data: export)

        XCTAssertTrue(store.assets[asset.id] === asset,
                      "merge must preserve object identity so @Observable views holding this Asset keep working")
    }

    /// A foreign `categoryID` (only reachable via a hand-edited file) must skip *only* the
    /// base-property merge — those definitions belong to another category's template. Events,
    /// transactions, photos and custom properties are category-independent and must still land.
    func testForeignCategoryIDStillMergesEventsAndPhotos() throws {
        let catA = try store.createCategory(name: "A")
        let catB = try store.createCategory(name: "B")
        let asset = try store.createAsset(name: "Thing", categoryID: catA.id)

        let export = try XCTUnwrap(store.exportJSON())
        let newEventID = UUID()
        let photoID = UUID()
        let doctored = try mutatingAsset(id: asset.id, in: export) { dict in
            dict["categoryID"] = catB.id.uuidString
            var events = dict["events"] as? [[String: Any]] ?? []
            events.append([
                "id": newEventID.uuidString, "title": "Should still merge",
                "date": ISO8601DateFormatter().string(from: Date()), "notes": "",
            ])
            dict["events"] = events
            dict["photos"] = [fabricatedPhotoJSON(id: photoID, fullBytes: Data("f".utf8), thumbBytes: Data("t".utf8))]
        }

        try store.importJSON(data: doctored)

        let merged = try XCTUnwrap(store.assets[asset.id])
        XCTAssertTrue(merged.events.contains { $0.id == newEventID },
                      "a foreign categoryID must not block the event merge")
        XCTAssertTrue(merged.photos.contains { $0.id == photoID },
                      "a foreign categoryID must not block the photo merge")
        XCTAssertEqual(merged.category.id, catA.id, "the local asset's category must be untouched")
    }

    // MARK: - Composite type / combo list hazard

    func testMergeKeepsPropertyReferencingCompositeTypeAbsentLocally() throws {
        let ct = store.createCompositeType(name: "3D Size", fields: [
            PropertyDefinition(name: "W", type: .basic(.number)),
            PropertyDefinition(name: "L", type: .basic(.number)),
        ])
        let cat = try store.createCategory(name: "Appliance", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Size", type: .composite(ct)))
        ])
        let asset = try store.createAsset(name: "Fridge", categoryID: cat.id)
        try store.setPropertyValue(.composite(["W": .number(10), "L": .number(20)]),
                                   forDefinitionID: asset.baseProperties[0].definition.id, onAssetID: asset.id)

        let export = try XCTUnwrap(store.exportJSON())
        let store2 = makeSecondStore()
        try store2.importJSON(data: export)

        XCTAssertNotNil(store2.compositeTypes[ct.id], "merge must create the composite type the incoming property references")
        let merged = try XCTUnwrap(store2.assets[asset.id])
        XCTAssertEqual(merged.baseProperties.count, 1,
                       "the Size property must survive merge, not be silently dropped for referencing an unknown composite type")
        XCTAssertNotNil(merged.baseProperties.first?.value)
    }

    func testMergeKeepsPropertyReferencingComboListAbsentLocally() throws {
        let cl = store.createComboList(name: "Power source", systemOptions: ["Gas", "Electric"])
        let cat = try store.createCategory(name: "Range", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Power source", type: .comboList(cl)))
        ])
        let asset = try store.createAsset(name: "Oven", categoryID: cat.id)
        try store.setPropertyValue(.text("Gas"), forDefinitionID: asset.baseProperties[0].definition.id, onAssetID: asset.id)

        let export = try XCTUnwrap(store.exportJSON())
        let store2 = makeSecondStore()
        try store2.importJSON(data: export)

        XCTAssertNotNil(store2.comboListDefinitions[cl.id])
        let merged = try XCTUnwrap(store2.assets[asset.id])
        XCTAssertEqual(merged.baseProperties.count, 1,
                       "the Power source property must survive merge, not be dropped for referencing an unknown combo list")
    }

    func testMergeUnionsComboListUserOptions() throws {
        let cl = store.createComboList(name: "Colors", systemOptions: ["Red"], userOptions: ["Blue"])
        let export = try XCTUnwrap(store.exportJSON())
        let doctored = try withJSON(export) { json in
            guard var lists = json["comboLists"] as? [[String: Any]] else { return }
            for i in lists.indices where (lists[i]["id"] as? String) == cl.id.uuidString {
                lists[i]["userOptions"] = ["Blue", "Green"]
            }
            json["comboLists"] = lists
        }

        try store.importJSON(data: doctored)

        let merged = try XCTUnwrap(store.comboListDefinitions[cl.id])
        XCTAssertEqual(Set(merged.userOptions), Set(["Blue", "Green"]), "userOptions must union, not duplicate or replace")
    }

    func testMergeDoesNotAlterExistingCompositeTypeFields() throws {
        let ct = store.createCompositeType(name: "2D Size", fields: [
            PropertyDefinition(name: "W", type: .basic(.number))
        ])
        let export = try XCTUnwrap(store.exportJSON())
        let doctored = try withJSON(export) { json in
            guard var types = json["compositeTypes"] as? [[String: Any]] else { return }
            for i in types.indices where (types[i]["id"] as? String) == ct.id.uuidString {
                var fields = types[i]["fields"] as? [[String: Any]] ?? []
                fields.append([
                    "id": UUID().uuidString, "name": "L",
                    "type": ["kind": "basic", "basicType": "number"], "isRequired": true,
                ])
                types[i]["fields"] = fields
            }
            json["compositeTypes"] = types
        }

        try store.importJSON(data: doctored)

        let merged = try XCTUnwrap(store.compositeTypes[ct.id])
        XCTAssertEqual(merged.fields.count, 1,
                       "merge must not add fields to an existing composite type — a new required field would make validate() reject every value already stored against that type")
        XCTAssertEqual(merged.fields.first?.name, "W")
    }

    // MARK: - Hierarchy

    func testMergeDoesNotReparentExistingLocalAsset() throws {
        let cat = try store.createCategory(name: "Garage")
        let root = try store.createAsset(name: "Root", categoryID: cat.id)
        let other = try store.createAsset(name: "Other", categoryID: cat.id)

        let export = try XCTUnwrap(store.exportJSON())
        let doctored = try mutatingAsset(id: root.id, in: export) { dict in
            dict["parentID"] = other.id.uuidString
        }

        try store.importJSON(data: doctored)

        XCTAssertNil(store.assets[root.id]?.parentID, "an existing local asset must never be re-parented by merge")
        XCTAssertTrue(store.assets[other.id]?.children.isEmpty ?? true)
    }

    func testMergeWiresNewChildUnderNewParent() throws {
        let cat = try store.createCategory(name: "Garage")
        let export = try XCTUnwrap(store.exportJSON())
        let shedID = UUID()
        let mowerID = UUID()
        var doctored = try addingAsset(
            fabricatedAssetJSON(id: shedID, name: "Shed", categoryID: cat.id, parentID: nil), to: export
        )
        doctored = try addingAsset(
            fabricatedAssetJSON(id: mowerID, name: "Mower", categoryID: cat.id, parentID: shedID), to: doctored
        )

        try store.importJSON(data: doctored)

        let shed = try XCTUnwrap(store.assets[shedID])
        let mower = try XCTUnwrap(store.assets[mowerID])
        XCTAssertEqual(mower.parentID, shedID)
        XCTAssertTrue(shed.children.contains { $0.id == mowerID },
                      "two assets that both arrive in the same merge must still be wired to each other")
        XCTAssertTrue(shed.isRoot)
        XCTAssertFalse(mower.isRoot)
    }

    func testMergeWiresNewChildUnderExistingLocalParent() throws {
        let cat = try store.createCategory(name: "Garage")
        let garage = try store.createAsset(name: "Garage", categoryID: cat.id)

        let export = try XCTUnwrap(store.exportJSON())
        let toolboxID = UUID()
        let doctored = try addingAsset(
            fabricatedAssetJSON(id: toolboxID, name: "Toolbox", categoryID: cat.id, parentID: garage.id), to: export
        )

        try store.importJSON(data: doctored)

        let toolbox = try XCTUnwrap(store.assets[toolboxID])
        XCTAssertEqual(toolbox.parentID, garage.id)
        XCTAssertTrue(store.assets[garage.id]?.children.contains { $0.id == toolboxID } ?? false)
    }

    func testMergeLeavesNewAssetAsRootWhenParentMissing() throws {
        let cat = try store.createCategory(name: "Garage")
        let export = try XCTUnwrap(store.exportJSON())
        let orphanID = UUID()
        let doctored = try addingAsset(
            fabricatedAssetJSON(id: orphanID, name: "Orphan", categoryID: cat.id, parentID: UUID()), to: export
        )

        try store.importJSON(data: doctored)

        let orphan = try XCTUnwrap(store.assets[orphanID])
        XCTAssertNil(orphan.parentID, "a new asset whose incoming parent is missing must become a root, not keep a dangling parentID")
        XCTAssertTrue(orphan.isRoot)
    }

    func testMergeDoesNotWireNewChildUnderSoftDeletedParent() throws {
        let cat = try store.createCategory(name: "Garage")
        let deletedParent = try store.createAsset(name: "Gone", categoryID: cat.id)
        try store.softDeleteAsset(id: deletedParent.id)

        let export = try XCTUnwrap(store.exportJSON())
        let childID = UUID()
        let doctored = try addingAsset(
            fabricatedAssetJSON(id: childID, name: "Child", categoryID: cat.id, parentID: deletedParent.id), to: export
        )

        try store.importJSON(data: doctored)

        let child = try XCTUnwrap(store.assets[childID])
        XCTAssertNil(child.parentID, "must not wire a new child under a soft-deleted parent")
    }

    func testMergeBreaksIncomingParentCycle() throws {
        let cat = try store.createCategory(name: "Garage")
        let export = try XCTUnwrap(store.exportJSON())
        let aID = UUID()
        let bID = UUID()
        var doctored = try addingAsset(fabricatedAssetJSON(id: aID, name: "A", categoryID: cat.id, parentID: bID), to: export)
        doctored = try addingAsset(fabricatedAssetJSON(id: bID, name: "B", categoryID: cat.id, parentID: aID), to: doctored)

        // Run the merge (and the unbounded `descendants` walk that would spin forever on a
        // surviving cycle) off the main thread behind a timeout, so a regressed cycle guard
        // fails this one test instead of hanging the whole suite. Safe only because this
        // store is isolated and has no UI observers — `importJSON` is main-thread in the app.
        let finished = expectation(description: "merge completes without hanging")
        let payload = doctored
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.store.importJSON(data: payload)
                _ = self.store.assets[aID]?.descendants
                _ = self.store.assets[bID]?.descendants
            } catch {
                XCTFail("importJSON threw: \(error)")
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 10)

        let a = try XCTUnwrap(store.assets[aID])
        let b = try XCTUnwrap(store.assets[bID])
        XCTAssertTrue(a.isRoot || b.isRoot, "an incoming parent cycle must be broken — at least one must end up a root")
    }

    // MARK: - Undelete on match

    func testMergeUndeletesLocalSoftDeletedCategory() throws {
        let cat = try store.createCategory(name: "Tools")
        let export = try XCTUnwrap(store.exportJSON())   // exported while still live
        try store.softDeleteCategory(id: cat.id)

        try store.importJSON(data: export)

        let merged = try XCTUnwrap(store.categories[cat.id])
        XCTAssertFalse(merged.isDeleted, "a live incoming category must restore its locally trashed match")
        XCTAssertNil(merged.deletedAt)
        XCTAssertTrue(store.allCategories.contains { $0.id == cat.id })
    }

    func testMergeUndeletesLocalSoftDeletedAsset() throws {
        let cat = try store.createCategory(name: "Garage")
        let asset = try store.createAsset(name: "Camry", categoryID: cat.id)
        let export = try XCTUnwrap(store.exportJSON())   // exported while still live
        try store.softDeleteAsset(id: asset.id)

        try store.importJSON(data: export)

        let merged = try XCTUnwrap(store.assets[asset.id])
        XCTAssertFalse(merged.isDeleted, "a live incoming asset must restore its locally trashed match")
        XCTAssertNil(merged.deletedAt)
        XCTAssertTrue(store.allAssets.contains { $0.id == asset.id })
    }

    func testMergeLeavesLocalDeletedRecordsAloneWhenIncomingIsAlsoDeleted() throws {
        let cat = try store.createCategory(name: "Garage")
        let asset = try store.createAsset(name: "Camry", categoryID: cat.id)
        try store.softDeleteAsset(id: asset.id)
        try store.softDeleteCategory(id: cat.id)
        let export = try XCTUnwrap(store.exportJSON())   // exported while both are trashed

        try store.importJSON(data: export)

        XCTAssertTrue(store.assets[asset.id]?.isDeleted ?? false,
                      "an incoming record that is itself deleted must not resurrect anything")
        XCTAssertTrue(store.categories[cat.id]?.isDeleted ?? false)
    }

    /// `softDeleteAsset` trashes a whole subtree, but an incoming file can revive only part
    /// of it. A still-deleted child left under a revived parent is filtered out of the asset
    /// tree yet isn't `isRoot`, so Deleted Assets wouldn't list it either — it must be detached.
    func testMergeDetachesStillDeletedChildFromRevivedParent() throws {
        let cat = try store.createCategory(name: "Garage")
        let parent = try store.createAsset(name: "Shed", categoryID: cat.id)
        let child = try store.createAsset(name: "Mower", categoryID: cat.id)
        try store.addChild(assetID: child.id, toParentID: parent.id)
        let export = try XCTUnwrap(store.exportJSON())   // both live, child linked
        try store.softDeleteAsset(id: parent.id)          // cascades to the child

        // Incoming knows only about the parent, so the child stays trashed.
        let doctored = try removingAsset(id: child.id, from: export)
        try store.importJSON(data: doctored)

        let revivedParent = try XCTUnwrap(store.assets[parent.id])
        let strandedChild = try XCTUnwrap(store.assets[child.id])
        XCTAssertFalse(revivedParent.isDeleted, "parent must be revived")
        XCTAssertTrue(strandedChild.isDeleted, "child was not in the incoming file, so it stays trashed")
        XCTAssertNil(strandedChild.parentID, "the still-deleted child must be detached from its revived parent")
        XCTAssertTrue(strandedChild.isRoot, "so that Deleted Assets, which lists only roots, can still reach it")
        XCTAssertFalse(revivedParent.children.contains { $0.id == child.id })
    }

    /// The mirror case: reviving a child while its parent stays trashed would leave the
    /// child live but absent from `rootAssets`, i.e. invisible in the asset tree.
    func testMergeDetachesRevivedAssetFromStillDeletedParent() throws {
        let cat = try store.createCategory(name: "Garage")
        let parent = try store.createAsset(name: "Shed", categoryID: cat.id)
        let child = try store.createAsset(name: "Mower", categoryID: cat.id)
        try store.addChild(assetID: child.id, toParentID: parent.id)
        let export = try XCTUnwrap(store.exportJSON())
        try store.softDeleteAsset(id: parent.id)          // cascades to the child

        // Incoming knows only about the child, so the parent stays trashed.
        let doctored = try removingAsset(id: parent.id, from: export)
        try store.importJSON(data: doctored)

        let revivedChild = try XCTUnwrap(store.assets[child.id])
        XCTAssertFalse(revivedChild.isDeleted, "child must be revived")
        XCTAssertTrue(store.assets[parent.id]?.isDeleted ?? false, "parent stays trashed")
        XCTAssertNil(revivedChild.parentID, "the revived child must be detached from its still-deleted parent")
        XCTAssertTrue(store.rootAssets.contains { $0.id == child.id },
                      "otherwise the revived asset would be live but invisible in the asset tree")
    }

    func testMergeRevivesWholeFamilyWhenIncomingHasAllOfIt() throws {
        let cat = try store.createCategory(name: "Garage")
        let parent = try store.createAsset(name: "Shed", categoryID: cat.id)
        let child = try store.createAsset(name: "Mower", categoryID: cat.id)
        try store.addChild(assetID: child.id, toParentID: parent.id)
        let export = try XCTUnwrap(store.exportJSON())
        try store.softDeleteAsset(id: parent.id)

        try store.importJSON(data: export)

        let revivedParent = try XCTUnwrap(store.assets[parent.id])
        let revivedChild = try XCTUnwrap(store.assets[child.id])
        XCTAssertFalse(revivedParent.isDeleted)
        XCTAssertFalse(revivedChild.isDeleted)
        XCTAssertEqual(revivedChild.parentID, parent.id, "a fully revived family must keep its hierarchy intact")
        XCTAssertTrue(revivedParent.children.contains { $0.id == child.id })
    }

    // MARK: - Whole-merge

    func testMergeIsIdempotent() throws {
        let cat = try store.createCategory(name: "Garage")
        let asset = try store.createAsset(name: "Camry", categoryID: cat.id)
        _ = try store.addEvent(title: "Oil change", date: Date(), toAssetID: asset.id)

        let export = try XCTUnwrap(store.exportJSON())
        try store.importJSON(data: export)
        let firstPass = (store.categories.count, store.assets.count, store.activityLog.count)

        try store.importJSON(data: export)
        let secondPass = (store.categories.count, store.assets.count, store.activityLog.count)

        XCTAssertEqual(firstPass.0, secondPass.0)
        XCTAssertEqual(firstPass.1, secondPass.1)
        XCTAssertEqual(firstPass.2, secondPass.2)
        XCTAssertEqual(store.assets[asset.id]?.events.count, 1, "re-importing the same file must not duplicate the event")
    }

    func testMergeKeepsLocalBackgroundTheme() throws {
        store.backgroundTheme = .sand
        let export = try XCTUnwrap(store.exportJSON())
        let doctored = try withJSON(export) { json in json["backgroundTheme"] = "facets" }

        try store.importJSON(data: doctored)

        XCTAssertEqual(store.backgroundTheme, .sand, "backgroundTheme is a local device preference and must survive merge")
    }

    func testMergePreservesLocalOnlyRecords() throws {
        let localOnlyCat = try store.createCategory(name: "Local Only")
        let localOnlyAsset = try store.createAsset(name: "Local Asset", categoryID: localOnlyCat.id)
        let unrelatedCat = try store.createCategory(name: "Unrelated")

        let export = try XCTUnwrap(store.exportJSON())
        let doctored = try mutatingCategory(id: unrelatedCat.id, in: export) { dict in dict["name"] = "Renamed Elsewhere" }

        try store.importJSON(data: doctored)

        XCTAssertNotNil(store.categories[localOnlyCat.id])
        XCTAssertNotNil(store.assets[localOnlyAsset.id])
        XCTAssertEqual(store.categories[unrelatedCat.id]?.name, "Unrelated", "unrelated local category must be untouched")
    }
}
