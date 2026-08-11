import XCTest
@testable import HandyApp3

/// Coverage for the per-record edit timestamps: `AssetProperty.modifyDate` (advanced by any
/// definition or value write) and `Asset.parentageModifyDate` (advanced only when the parent
/// link changes). Tests back-date the field to `.distantPast` before acting, so a passing
/// assertion means the stamp actually fired rather than two `Date()` calls landing apart.
final class RecordTimestampTests: XCTestCase {

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

    // MARK: - Fixtures

    /// A category with two text templates, and an asset built from it.
    private func makeAssetWithTwoProperties() throws -> (Asset, AssetProperty, AssetProperty) {
        let cat = try store.createCategory(name: "Vehicle", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text))),
            AssetProperty(definition: PropertyDefinition(name: "Model", type: .basic(.text))),
        ])
        let asset = try store.createAsset(name: "Car", categoryID: cat.id)
        return (asset, asset.baseProperties[0], asset.baseProperties[1])
    }

    // MARK: - AssetProperty.modifyDate

    func testSetPropertyValueAdvancesModifyDate() throws {
        let (asset, make, _) = try makeAssetWithTwoProperties()
        make.modifyDate = .distantPast

        try store.setPropertyValue(.text("Toyota"), forDefinitionID: make.definition.id, onAssetID: asset.id)

        XCTAssertGreaterThan(make.modifyDate, .distantPast)
    }

    func testRemovePropertyValueAdvancesModifyDate() throws {
        let (asset, make, _) = try makeAssetWithTwoProperties()
        try store.setPropertyValue(.text("Toyota"), forDefinitionID: make.definition.id, onAssetID: asset.id)
        make.modifyDate = .distantPast

        try store.removePropertyValue(forDefinitionID: make.definition.id, fromAssetID: asset.id)

        XCTAssertGreaterThan(make.modifyDate, .distantPast)
    }

    func testEditingOnePropertyLeavesSiblingModifyDateUntouched() throws {
        let (asset, make, model) = try makeAssetWithTwoProperties()
        model.modifyDate = .distantPast

        try store.setPropertyValue(.text("Toyota"), forDefinitionID: make.definition.id, onAssetID: asset.id)

        XCTAssertEqual(model.modifyDate, .distantPast,
                       "a sibling property must not be stamped — per-property freshness is the point of the field")
        XCTAssertGreaterThan(asset.modifiedDate, model.modifyDate)
    }

    func testAddCustomPropertyStampsNow() throws {
        let (asset, _, _) = try makeAssetWithTwoProperties()

        let prop = try store.addCustomProperty(
            definition: PropertyDefinition(name: "Paint", type: .basic(.text), isRequired: false),
            toAssetID: asset.id
        )

        XCTAssertEqual(prop.modifyDate.timeIntervalSinceNow, 0, accuracy: 1)
    }

    func testSetCustomPropertyValueAdvancesModifyDate() throws {
        let (asset, _, _) = try makeAssetWithTwoProperties()
        let prop = try store.addCustomProperty(
            definition: PropertyDefinition(name: "Paint", type: .basic(.text), isRequired: false),
            toAssetID: asset.id
        )
        prop.modifyDate = .distantPast

        try store.setCustomPropertyValue(.text("Red"), forCustomPropertyID: prop.id, onAssetID: asset.id)

        XCTAssertGreaterThan(prop.modifyDate, .distantPast)
    }

    func testUpdateCustomPropertyAdvancesModifyDate() throws {
        let (asset, _, _) = try makeAssetWithTwoProperties()
        let prop = try store.addCustomProperty(
            definition: PropertyDefinition(name: "Paint", type: .basic(.text), isRequired: false),
            toAssetID: asset.id
        )
        prop.modifyDate = .distantPast

        try store.updateCustomProperty(id: prop.id, onAssetID: asset.id, name: "Paint Color")

        XCTAssertGreaterThan(prop.modifyDate, .distantPast)
    }

    func testTemplatePropertyEditsAdvanceModifyDate() throws {
        let cat = try store.createCategory(name: "Vehicle", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text)))
        ])
        let template = cat.propertyTemplates[0]

        template.modifyDate = .distantPast
        try store.setTemplatePropertyValue(.text("Toyota"), forPropertyID: template.id, inCategoryID: cat.id)
        XCTAssertGreaterThan(template.modifyDate, .distantPast)

        template.modifyDate = .distantPast
        try store.updateTemplateProperty(id: template.id, inCategoryID: cat.id, name: "Manufacturer")
        XCTAssertGreaterThan(template.modifyDate, .distantPast)
    }

    /// Base properties are fresh per-instance copies, so they carry the asset's creation
    /// time — not whenever the category template they were copied from was last edited.
    func testCreateAssetStampsBasePropertiesFreshRatherThanInheritingTemplate() throws {
        let cat = try store.createCategory(name: "Vehicle", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text)))
        ])
        cat.propertyTemplates[0].modifyDate = .distantPast

        let asset = try store.createAsset(name: "Car", categoryID: cat.id)

        XCTAssertEqual(asset.baseProperties[0].modifyDate.timeIntervalSinceNow, 0, accuracy: 1)
    }

    // MARK: - Asset.parentageModifyDate

    func testAddChildStampsParentageAndModifiedDate() throws {
        let cat = try store.createCategory(name: "Storage")
        let parent = try store.createAsset(name: "Garage", categoryID: cat.id)
        let child = try store.createAsset(name: "Mower", categoryID: cat.id)
        child.parentageModifyDate = .distantPast
        child.modifiedDate = .distantPast

        try store.addChild(assetID: child.id, toParentID: parent.id)

        XCTAssertGreaterThan(child.parentageModifyDate, .distantPast)
        XCTAssertGreaterThan(child.modifiedDate, .distantPast)
    }

    func testRemoveFromParentStampsParentage() throws {
        let cat = try store.createCategory(name: "Storage")
        let parent = try store.createAsset(name: "Garage", categoryID: cat.id)
        let child = try store.createAsset(name: "Mower", categoryID: cat.id)
        try store.addChild(assetID: child.id, toParentID: parent.id)
        child.parentageModifyDate = .distantPast

        try store.removeFromParent(assetID: child.id)

        XCTAssertGreaterThan(child.parentageModifyDate, .distantPast)
    }

    func testMoveAssetStampsParentage() throws {
        let cat = try store.createCategory(name: "Storage")
        let garage = try store.createAsset(name: "Garage", categoryID: cat.id)
        let shed = try store.createAsset(name: "Shed", categoryID: cat.id)
        let mower = try store.createAsset(name: "Mower", categoryID: cat.id)
        try store.addChild(assetID: mower.id, toParentID: garage.id)
        mower.parentageModifyDate = .distantPast

        try store.moveAsset(assetID: mower.id, toParentID: shed.id)

        XCTAssertEqual(mower.parentID, shed.id)
        XCTAssertGreaterThan(mower.parentageModifyDate, .distantPast)
    }

    func testRemoveFromParentOnRootLeavesTimestampsAlone() throws {
        let cat = try store.createCategory(name: "Storage")
        let root = try store.createAsset(name: "Garage", categoryID: cat.id)
        root.parentageModifyDate = .distantPast
        root.modifiedDate = .distantPast

        try store.removeFromParent(assetID: root.id)

        XCTAssertEqual(root.parentageModifyDate, .distantPast, "detaching an already-root asset changes nothing")
        XCTAssertEqual(root.modifiedDate, .distantPast)
    }

    func testPropertyEditDoesNotAdvanceParentageModifyDate() throws {
        let (asset, make, _) = try makeAssetWithTwoProperties()
        asset.parentageModifyDate = .distantPast

        try store.setPropertyValue(.text("Toyota"), forDefinitionID: make.definition.id, onAssetID: asset.id)
        try store.updateAsset(id: asset.id, name: "Renamed")

        XCTAssertEqual(asset.parentageModifyDate, .distantPast,
                       "content edits are not parentage changes")
        XCTAssertGreaterThan(asset.modifiedDate, .distantPast)
    }

    /// `deleteAsset` re-parents the deleted asset's children onto their grandparent —
    /// a genuine move for the survivors.
    func testHardDeleteReparentsChildrenAndStampsThem() throws {
        let cat = try store.createCategory(name: "Storage")
        let grandparent = try store.createAsset(name: "House", categoryID: cat.id)
        let parent = try store.createAsset(name: "Garage", categoryID: cat.id)
        let child = try store.createAsset(name: "Mower", categoryID: cat.id)
        try store.addChild(assetID: parent.id, toParentID: grandparent.id)
        try store.addChild(assetID: child.id, toParentID: parent.id)
        child.parentageModifyDate = .distantPast

        try store.deleteAsset(id: parent.id)

        XCTAssertEqual(child.parentID, grandparent.id)
        XCTAssertGreaterThan(child.parentageModifyDate, .distantPast)
    }

    // MARK: - Persistence round trip

    /// Loading a snapshot rehydrates the tree through `_addChild`; that must not read as a
    /// move, or every launch would reset the whole store's parentage clock to now.
    func testSaveLoadPreservesBothTimestamps() throws {
        let cat = try store.createCategory(name: "Storage", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text)))
        ])
        let parent = try store.createAsset(name: "Garage", categoryID: cat.id)
        let child = try store.createAsset(name: "Mower", categoryID: cat.id)
        try store.addChild(assetID: child.id, toParentID: parent.id)

        let stamp = Date(timeIntervalSince1970: 1_500_000_000)
        child.parentageModifyDate = stamp
        child.baseProperties[0].modifyDate = stamp
        store.save()

        let reloaded = AssetStore()
        XCTAssertTrue(reloaded.load())

        let loadedChild = try XCTUnwrap(reloaded.assets[child.id])
        XCTAssertEqual(loadedChild.parentID, parent.id)
        XCTAssertEqual(loadedChild.parentageModifyDate, stamp)
        XCTAssertEqual(loadedChild.baseProperties[0].modifyDate, stamp)
    }

    // MARK: - Event / Transaction / Photo modifyDate and tombstones

    func testUpdateEventAdvancesEventModifyDate() throws {
        let cat = try store.createCategory(name: "Storage")
        let asset = try store.createAsset(name: "Garage", categoryID: cat.id)
        let event = try store.addEvent(title: "Old", date: Date(), toAssetID: asset.id)
        event.modifyDate = .distantPast

        try store.updateEvent(id: event.id, onAssetID: asset.id, title: "New", date: Date(), notes: "", recurrence: nil)

        XCTAssertGreaterThan(event.modifyDate, .distantPast)
    }

    func testUpdateTransactionAdvancesTransactionModifyDate() throws {
        let cat = try store.createCategory(name: "Storage")
        let asset = try store.createAsset(name: "Garage", categoryID: cat.id)
        let txn = try store.addTransaction(details: "Old", amount: 10, date: Date(), kind: .expense, toAssetID: asset.id)
        txn.modifyDate = .distantPast

        try store.updateTransaction(id: txn.id, onAssetID: asset.id, details: "New", amount: 20, date: Date(), kind: .income, payeeContactID: nil, notes: "", recurrence: nil)

        XCTAssertGreaterThan(txn.modifyDate, .distantPast)
    }

    func testUpdatePhotoCaptionAdvancesPhotoModifyDate() throws {
        let cat = try store.createCategory(name: "Storage")
        let asset = try store.createAsset(name: "Garage", categoryID: cat.id)
        let photo = try store.addPhoto(imageData: Data([1]), thumbnailData: Data([2]), toAssetID: asset.id)
        photo.modifyDate = .distantPast

        try store.updatePhotoCaption("New caption", forPhotoID: photo.id, onAssetID: asset.id)

        XCTAssertGreaterThan(photo.modifyDate, .distantPast)
    }

    func testRemoveEventStampsModifyDateAndDeletedAt() throws {
        let cat = try store.createCategory(name: "Storage")
        let asset = try store.createAsset(name: "Garage", categoryID: cat.id)
        let event = try store.addEvent(title: "X", date: Date(), toAssetID: asset.id)
        event.modifyDate = .distantPast

        try store.removeEvent(id: event.id, fromAssetID: asset.id)

        XCTAssertGreaterThan(event.modifyDate, .distantPast)
        XCTAssertTrue(event.isDeleted)
        XCTAssertNotNil(event.deletedAt)
    }

    func testEditingOneEventLeavesSiblingModifyDateUntouched() throws {
        let cat = try store.createCategory(name: "Storage")
        let asset = try store.createAsset(name: "Garage", categoryID: cat.id)
        let keep = try store.addEvent(title: "Keep", date: Date(), toAssetID: asset.id)
        let edit = try store.addEvent(title: "Edit", date: Date(), toAssetID: asset.id)
        keep.modifyDate = .distantPast

        try store.updateEvent(id: edit.id, onAssetID: asset.id, title: "Edited", date: Date(), notes: "", recurrence: nil)

        XCTAssertEqual(keep.modifyDate, .distantPast,
                       "a sibling event must not be stamped — per-record freshness is the point of the field")
    }

    func testSaveLoadPreservesInlineTombstonesAndTimestamps() throws {
        let cat = try store.createCategory(name: "Storage")
        let asset = try store.createAsset(name: "Garage", categoryID: cat.id)
        let event = try store.addEvent(title: "X", date: Date(), toAssetID: asset.id)
        try store.removeEvent(id: event.id, fromAssetID: asset.id)

        let stamp = Date(timeIntervalSince1970: 1_500_000_000)
        event.modifyDate = stamp
        event.deletedAt = stamp
        store.save()

        let reloaded = AssetStore()
        XCTAssertTrue(reloaded.load())

        let loadedAsset = try XCTUnwrap(reloaded.assets[asset.id])
        let loadedEvent = try XCTUnwrap(loadedAsset.events.first { $0.id == event.id })
        XCTAssertTrue(loadedEvent.isDeleted)
        XCTAssertEqual(loadedEvent.deletedAt, stamp)
        XCTAssertEqual(loadedEvent.modifyDate, stamp)
        XCTAssertEqual(loadedAsset.liveEvents.count, 0)
    }

    func testRemoveCustomPropertyStampsModifyDateAndDeletedAt() throws {
        let (asset, _, _) = try makeAssetWithTwoProperties()
        let prop = try store.addCustomProperty(
            definition: PropertyDefinition(name: "Paint", type: .basic(.text), isRequired: false),
            toAssetID: asset.id
        )
        prop.modifyDate = .distantPast
        asset.modifiedDate = .distantPast

        try store.removeCustomProperty(id: prop.id, fromAssetID: asset.id)

        XCTAssertGreaterThan(prop.modifyDate, .distantPast)
        XCTAssertGreaterThan(asset.modifiedDate, .distantPast)
        XCTAssertTrue(prop.isDeleted)
        XCTAssertNotNil(prop.deletedAt)
    }

    func testSaveLoadPreservesCustomPropertyTombstoneAndTimestamps() throws {
        let (asset, _, _) = try makeAssetWithTwoProperties()
        let prop = try store.addCustomProperty(
            definition: PropertyDefinition(name: "Paint", type: .basic(.text), isRequired: false),
            toAssetID: asset.id
        )
        try store.removeCustomProperty(id: prop.id, fromAssetID: asset.id)

        let stamp = Date(timeIntervalSince1970: 1_500_000_000)
        prop.modifyDate = stamp
        prop.deletedAt = stamp
        store.save()

        let reloaded = AssetStore()
        XCTAssertTrue(reloaded.load())

        let loadedAsset = try XCTUnwrap(reloaded.assets[asset.id])
        let loadedProp = try XCTUnwrap(loadedAsset.customProperties.first { $0.id == prop.id })
        XCTAssertTrue(loadedProp.isDeleted)
        XCTAssertEqual(loadedProp.deletedAt, stamp)
        XCTAssertEqual(loadedProp.modifyDate, stamp)
        XCTAssertEqual(loadedAsset.liveCustomProperties.count, 0)
    }
}
