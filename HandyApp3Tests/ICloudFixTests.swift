import XCTest
@testable import HandyApp3

// MARK: - Phase 1: cold-start protection

final class ColdStartTests: XCTestCase {

    // MARK: coldStartAction (pure, no disk I/O)

    func testColdStartActionUseLoadedWhenStoreLoaded() {
        XCTAssertEqual(AssetStore.coldStartAction(loaded: true, iCloudActive: true),  .useLoaded)
        XCTAssertEqual(AssetStore.coldStartAction(loaded: true, iCloudActive: false), .useLoaded)
    }

    func testColdStartActionSeedAndPersistWhenNoCloudAndNotLoaded() {
        XCTAssertEqual(AssetStore.coldStartAction(loaded: false, iCloudActive: false), .seedAndPersist)
    }

    func testColdStartActionSeedSuspendedWhenCloudActiveAndNotLoaded() {
        XCTAssertEqual(AssetStore.coldStartAction(loaded: false, iCloudActive: true), .seedSuspended)
    }

    // MARK: savesSuspended blocks save() and markDirty()

    func testSavesSuspendedPreventsDiskWrite() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        AssetStore.baseDirOverride = tempDir
        let store = AssetStore()
        defer {
            AssetStore.baseDirOverride = nil
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Set suspended before any mutations so markDirty() is also a no-op.
        store.savesSuspended = true
        let cat = try store.createCategory(name: "Widgets")
        _ = try store.createAsset(name: "Gadget", categoryID: cat.id)

        store.save()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: AssetStore.storeURL.path),
            "save() must be a no-op while savesSuspended is true"
        )
    }

    func testSavesSuspendedFalseAllowsDiskWrite() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        AssetStore.baseDirOverride = tempDir
        let store = AssetStore()
        defer {
            AssetStore.baseDirOverride = nil
            try? FileManager.default.removeItem(at: tempDir)
        }

        store.savesSuspended = true
        let cat = try store.createCategory(name: "Widgets")
        _ = try store.createAsset(name: "Gadget", categoryID: cat.id)

        store.savesSuspended = false
        store.save()

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: AssetStore.storeURL.path),
            "save() must write to disk once savesSuspended is cleared"
        )
    }
}

// MARK: - Phase 2: import/export photo integrity

final class PhotoImportExportTests: XCTestCase {

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

    func testRoundTripPreservesReferencedPhotoFiles() throws {
        let cat = try store.createCategory(name: "Fleet")
        let asset = try store.createAsset(name: "Truck", categoryID: cat.id)
        let photo = try store.addPhoto(
            imageData: Data("full_bytes".utf8),
            thumbnailData: Data("thumb_bytes".utf8),
            toAssetID: asset.id
        )

        let export = try XCTUnwrap(store.exportJSON())
        try store.importJSON(data: export)

        XCTAssertTrue(FileManager.default.fileExists(atPath: PhotoStorage.fullURL(id: photo.id).path),
                      "importJSON must keep referenced full-image file")
        XCTAssertTrue(FileManager.default.fileExists(atPath: PhotoStorage.thumbURL(id: photo.id).path),
                      "importJSON must keep referenced thumbnail file")
        let restored = try XCTUnwrap(store.assets[asset.id])
        XCTAssertEqual(restored.photos.count, 1)
        XCTAssertEqual(restored.photos.first?.id, photo.id)
    }

    func testImportPreservesUnreferencedLocalPhotoFiles() throws {
        // Write a local-only photo file that the incoming snapshot doesn't reference.
        let localOnlyID = UUID()
        try PhotoStorage.save(id: localOnlyID,
                              imageData: Data("local_full".utf8),
                              thumbnailData: Data("local_thumb".utf8))

        let cat = try store.createCategory(name: "Fleet")
        let export = try XCTUnwrap(store.exportJSON())
        try store.importJSON(data: export)

        XCTAssertTrue(FileManager.default.fileExists(atPath: PhotoStorage.fullURL(id: localOnlyID).path),
                      "merge-on-import must never delete local photo files, referenced or not")
        XCTAssertTrue(FileManager.default.fileExists(atPath: PhotoStorage.thumbURL(id: localOnlyID).path))
    }

    func testExportEmbedsPhotoBytes() throws {
        let cat = try store.createCategory(name: "Fleet")
        let asset = try store.createAsset(name: "Van", categoryID: cat.id)
        _ = try store.addPhoto(
            imageData: Data("full_image".utf8),
            thumbnailData: Data("thumb_image".utf8),
            toAssetID: asset.id
        )

        let export = try XCTUnwrap(store.exportJSON())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: export) as? [String: Any])
        let assets = try XCTUnwrap(json["assets"] as? [[String: Any]])
        let photos = try XCTUnwrap(assets.first?["photos"] as? [[String: Any]])
        let photoJSON = try XCTUnwrap(photos.first)

        XCTAssertNotNil(photoJSON["fullImage"], "exportJSON must embed full image bytes")
        XCTAssertNotNil(photoJSON["thumbnail"], "exportJSON must embed thumbnail bytes")
    }

    func testImportFromExportRecreatesPhotoFilesOnFreshStore() throws {
        // Original store: add photo and export.
        let cat = try store.createCategory(name: "Fleet")
        let asset = try store.createAsset(name: "Bus", categoryID: cat.id)
        let photo = try store.addPhoto(
            imageData: Data("full_image_bytes".utf8),
            thumbnailData: Data("thumb_bytes".utf8),
            toAssetID: asset.id
        )
        let export = try XCTUnwrap(store.exportJSON())

        // Fresh store in a different temp dir (simulates another device).
        let tempDir2 = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        AssetStore.baseDirOverride = tempDir2
        let store2 = AssetStore()
        defer {
            AssetStore.baseDirOverride = tempDir
            try? FileManager.default.removeItem(at: tempDir2)
        }

        try store2.importJSON(data: export)

        XCTAssertTrue(FileManager.default.fileExists(atPath: PhotoStorage.fullURL(id: photo.id).path),
                      "import must recreate full-image file from embedded export bytes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: PhotoStorage.thumbURL(id: photo.id).path),
                      "import must recreate thumbnail file from embedded export bytes")
    }
}

// MARK: - Phase 3: deletion hygiene

final class DeletionHygieneTests: XCTestCase {

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

    func testFactoryResetWritesDecodableStoreSynchronously() throws {
        store.factoryReset()

        XCTAssertTrue(FileManager.default.fileExists(atPath: AssetStore.storeURL.path),
                      "factoryReset must persist synchronously before returning")

        // Assert the invariant, not the on-disk layout: store.json is a manifest now, not a
        // full snapshot, so what matters is that a fresh load() can read the reset store back.
        let reloaded = AssetStore()
        XCTAssertTrue(reloaded.load(), "factoryReset's save must leave a store a fresh load() can read")
        XCTAssertGreaterThan(reloaded.categories.count, 0,
                             "persisted snapshot after factoryReset must contain seeded categories")
    }

    func testFactoryResetDoesNotDeleteStoreFile() throws {
        // Perform an initial save so the file exists before reset.
        let cat = try store.createCategory(name: "Pre-reset")
        let asset = try store.createAsset(name: "Should be purged", categoryID: cat.id)
        let assetID = asset.id
        store.save()
        XCTAssertTrue(FileManager.default.fileExists(atPath: AssetStore.storeURL.path))
        let preResetAssetFile = AssetStore.baseDir
            .appendingPathComponent("Assets/\(assetID.uuidString).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: preResetAssetFile.path))

        store.factoryReset()

        XCTAssertTrue(FileManager.default.fileExists(atPath: AssetStore.storeURL.path),
                      "factoryReset must overwrite store.json, not delete it — deletions are ignored by other devices")
        // The asset's file must still exist — it's now the multi-file equivalent of an ordinary
        // hard delete (overwritten with a purged husk, not swept away), so an empty local map
        // can't have a peer's still-live copy union straight back on the next sync.
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: preResetAssetFile.path),
            "factoryReset must purge the pre-reset asset's file in place, not remove it — an absent file doesn't propagate to peers"
        )
        let purged = try XCTUnwrap(store.assets[assetID], "the purged husk must remain in the store's asset map")
        XCTAssertTrue(purged.isPurged)
        XCTAssertNotNil(purged.purgedAt)
        XCTAssertTrue(purged.baseProperties.isEmpty)
        XCTAssertTrue(purged.customProperties.isEmpty)
        XCTAssertTrue(purged.events.isEmpty)
        XCTAssertTrue(purged.transactions.isEmpty)
        XCTAssertTrue(purged.photos.isEmpty)
        XCTAssertFalse(store.allAssets.contains { $0.id == assetID },
                       "a purged asset must not show up as live")
        XCTAssertFalse(store.deletedAssets.contains { $0.id == assetID },
                       "a purged asset must not show up in Trash either")
    }

    func testFactoryResetLeavesNoNotificationsToSchedule() throws {
        // NotificationScheduler.apply talks to the live UNUserNotificationCenter and needs
        // real authorization, so — as with the rest of this suite's notification coverage
        // (see RecurrenceTests) — this checks the pure planning boundary: what factoryReset's
        // final requestResync(assets:) call would actually hand the scheduler, not the
        // live system side effect.
        let cat = try store.createCategory(name: "Pre-reset")
        let asset = try store.createAsset(name: "Has an event", categoryID: cat.id)
        _ = try store.addEvent(
            title: "Due soon", date: Date(),
            due: DueSettings(dueDate: Date().addingTimeInterval(86_400 * 30), deviceNotificationOn: true),
            toAssetID: asset.id)
        XCTAssertFalse(NotificationPlanner.plan(for: store.allAssets).isEmpty,
                       "sanity check: the pre-reset event must actually plan a notification")

        store.factoryReset()

        XCTAssertTrue(NotificationPlanner.plan(for: store.allAssets).isEmpty,
                      "factoryReset's seeded assets carry no events/transactions, so nothing should remain to notify about")
    }

    func testFactoryResetThenImportDoesNotDuplicateSeededAssets() throws {
        // Seed the store the way a real launch would, then let the user add content to the
        // sample assets before exporting a backup — export/import is the path that used to
        // duplicate "My Home" after a reset (see SeedAssetIdentityTests for the seeder itself).
        store.seedBuiltInComboLists()
        store.seedBuiltInCategories()
        store.seedBuiltInTypes()
        store.seedBuiltInAssets()
        store.seedSampleAutomobile()
        let home = try XCTUnwrap(store.allAssets.first(where: { $0.name == "My Home" }))
        _ = try store.addEvent(title: "Roof inspection", date: Date(), toAssetID: home.id)
        let export = try XCTUnwrap(store.exportJSON())

        store.factoryReset()
        try store.importJSON(data: export)

        XCTAssertEqual(store.allAssets.filter { $0.name == "My Home" }.count, 1,
                       "factory reset followed by importing a backup must not leave two live \"My Home\" assets")
        XCTAssertEqual(store.allAssets.filter { $0.name == "Testarossa 85" }.count, 1,
                       "factory reset followed by importing a backup must not leave two live \"Testarossa 85\" assets")
        let revivedHome = try XCTUnwrap(store.allAssets.first(where: { $0.name == "My Home" }))
        XCTAssertTrue(revivedHome.events.contains { $0.title == "Roof inspection" },
                     "the imported backup's content must be restored onto the revived asset")
    }

    func testDeleteAssetRemovesPhotoFilesFromDisk() throws {
        let cat = try store.createCategory(name: "Vehicles")
        let asset = try store.createAsset(name: "Bike", categoryID: cat.id)
        let photo = try store.addPhoto(
            imageData: Data("full".utf8),
            thumbnailData: Data("thumb".utf8),
            toAssetID: asset.id
        )

        let fullURL = PhotoStorage.fullURL(id: photo.id)
        let thumbURL = PhotoStorage.thumbURL(id: photo.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fullURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbURL.path))

        try store.deleteAsset(id: asset.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fullURL.path),
                       "deleteAsset must remove full-image file")
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbURL.path),
                       "deleteAsset must remove thumbnail file")
    }

    func testHardDeleteAssetRemovesSubtreePhotoFiles() throws {
        let cat = try store.createCategory(name: "Vehicles")
        let parent = try store.createAsset(name: "Car", categoryID: cat.id)
        let child = try store.createAsset(name: "Trailer", categoryID: cat.id)
        try store.addChild(assetID: child.id, toParentID: parent.id)

        let parentPhoto = try store.addPhoto(imageData: Data("p-full".utf8),
                                             thumbnailData: Data("p-thumb".utf8), toAssetID: parent.id)
        let childPhoto = try store.addPhoto(imageData: Data("c-full".utf8),
                                            thumbnailData: Data("c-thumb".utf8), toAssetID: child.id)
        try store.softDeleteAsset(id: parent.id)

        let urls = [parentPhoto, childPhoto].flatMap {
            [PhotoStorage.fullURL(id: $0.id), PhotoStorage.thumbURL(id: $0.id)]
        }
        XCTAssertTrue(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) },
                      "photo files must exist before hard delete")

        try store.hardDeleteAsset(id: parent.id)

        XCTAssertTrue(urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) },
                      "hardDeleteAsset must delete photo files for every node in the subtree")
    }

    func testPurgeRemovesExpiredAssetPhotoFiles() throws {
        let cat = try store.createCategory(name: "Vehicles")
        let asset = try store.createAsset(name: "Bike", categoryID: cat.id)
        let photo = try store.addPhoto(imageData: Data("full".utf8),
                                       thumbnailData: Data("thumb".utf8), toAssetID: asset.id)
        let fullURL = PhotoStorage.fullURL(id: photo.id)
        let thumbURL = PhotoStorage.thumbURL(id: photo.id)

        try store.softDeleteAsset(id: asset.id)
        // Backdate content stamps along with deletedAt — Asset.isProtectedFromAutoPurge
        // (mirroring SnapshotReconciler's sync-merge gate) refuses to purge an asset whose own
        // content is newer than its delete decision; leaving modifiedDate/headModifyDate at
        // "now" would make this look like an edit after the delete and the purge below would
        // be refused, leaving the photo files on disk.
        let backdate = Date().addingTimeInterval(-15 * 86_400)
        asset.deletedAt = backdate
        asset.modifiedDate = backdate
        asset.headModifyDate = backdate
        store.purgeHardDeleted(olderThan: TimeInterval(AppPreference.DaysToRetainDeletedItems) * 86_400)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fullURL.path),
                       "purge must remove full-image file for expired asset")
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbURL.path),
                       "purge must remove thumbnail file for expired asset")
    }

    func testPurgeStripsExpiredAssetToMinimalTombstoneInsteadOfRemovingIt() throws {
        let cat = try store.createCategory(name: "Vehicles")
        let asset = try store.createAsset(name: "Bike", categoryID: cat.id)
        _ = try store.addPhoto(imageData: Data("full".utf8), thumbnailData: Data("thumb".utf8), toAssetID: asset.id)
        _ = try store.addEvent(title: "Checkup", date: Date(), toAssetID: asset.id)
        _ = try store.addTransaction(details: "Repair", amount: 5, date: Date(), kind: .expense, toAssetID: asset.id)
        _ = try store.addCustomProperty(definition: PropertyDefinition(name: "Color", type: .basic(.text)), toAssetID: asset.id)
        let hadBaseProperties = !asset.baseProperties.isEmpty
        let createdDate = asset.createdDate

        try store.softDeleteAsset(id: asset.id)
        // Backdate content stamps along with deletedAt — see the identical comment in
        // testPurgeRemovesExpiredAssetPhotoFiles. The photo/event/transaction/customProperty
        // adds above already bumped modifiedDate to "now", so without this the purge below
        // would be refused as protected content.
        let backdate = Date().addingTimeInterval(-15 * 86_400)
        asset.deletedAt = backdate
        asset.modifiedDate = backdate
        asset.headModifyDate = backdate
        store.purgeHardDeleted(olderThan: TimeInterval(AppPreference.DaysToRetainDeletedItems) * 86_400)

        let survivor = try XCTUnwrap(store.assets[asset.id], "purge must never remove the asset record — a peer that still has the full asset would resurrect it")
        XCTAssertTrue(survivor.isPurged)
        XCTAssertEqual(survivor.name, "Bike", "name survives the strip")
        XCTAssertEqual(survivor.createdDate, createdDate, "purge must not touch timestamps")
        XCTAssertEqual(survivor.category.id, cat.id, "categoryID survives the strip")
        XCTAssertTrue(survivor.photos.isEmpty)
        XCTAssertTrue(survivor.events.isEmpty)
        XCTAssertTrue(survivor.transactions.isEmpty)
        XCTAssertTrue(survivor.customProperties.isEmpty)
        if hadBaseProperties { XCTAssertTrue(survivor.baseProperties.isEmpty) }
        XCTAssertNil(survivor.parentID)
    }

    func testRemovePhotoKeepsFilesOnDiskUntilPurge() throws {
        let cat = try store.createCategory(name: "Vehicles")
        let asset = try store.createAsset(name: "Bike", categoryID: cat.id)
        let photo = try store.addPhoto(imageData: Data("full".utf8),
                                       thumbnailData: Data("thumb".utf8), toAssetID: asset.id)
        let fullURL = PhotoStorage.fullURL(id: photo.id)
        let thumbURL = PhotoStorage.thumbURL(id: photo.id)

        try store.removePhoto(id: photo.id, fromAssetID: asset.id)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fullURL.path),
                      "removePhoto must not delete bytes — a peer that hasn't seen the delete still needs them")
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbURL.path))
    }

    func testPurgeRemovesExpiredPhotoTombstoneFilesFromLiveAsset() throws {
        let cat = try store.createCategory(name: "Vehicles")
        let asset = try store.createAsset(name: "Bike", categoryID: cat.id)
        let photo = try store.addPhoto(imageData: Data("full".utf8),
                                       thumbnailData: Data("thumb".utf8), toAssetID: asset.id)
        let fullURL = PhotoStorage.fullURL(id: photo.id)
        let thumbURL = PhotoStorage.thumbURL(id: photo.id)

        try store.removePhoto(id: photo.id, fromAssetID: asset.id)
        photo.deletedAt = Date().addingTimeInterval(-15 * 86_400)
        store.purgeHardDeleted(olderThan: TimeInterval(AppPreference.DaysToRetainDeletedItems) * 86_400)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fullURL.path),
                       "purge must remove full-image file for an expired photo tombstone on a live asset")
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbURL.path))
        XCTAssertEqual(asset.photos.count, 0, "the expired tombstone itself must be reaped")
    }

    func testPurgeRemovesExpiredEventAndTransactionTombstones() throws {
        let cat = try store.createCategory(name: "Vehicles")
        let asset = try store.createAsset(name: "Bike", categoryID: cat.id)
        let event = try store.addEvent(title: "X", date: Date(), toAssetID: asset.id)
        let txn = try store.addTransaction(details: "X", amount: 5, date: Date(), kind: .expense, toAssetID: asset.id)

        try store.removeEvent(id: event.id, fromAssetID: asset.id)
        try store.removeTransaction(id: txn.id, fromAssetID: asset.id)
        event.deletedAt = Date().addingTimeInterval(-15 * 86_400)
        txn.deletedAt = Date().addingTimeInterval(-15 * 86_400)
        store.purgeHardDeleted(olderThan: TimeInterval(AppPreference.DaysToRetainDeletedItems) * 86_400)

        XCTAssertEqual(asset.events.count, 0)
        XCTAssertEqual(asset.transactions.count, 0)
    }

    func testPurgeKeepsUnexpiredInlineTombstones() throws {
        let cat = try store.createCategory(name: "Vehicles")
        let asset = try store.createAsset(name: "Bike", categoryID: cat.id)
        let event = try store.addEvent(title: "X", date: Date(), toAssetID: asset.id)

        try store.removeEvent(id: event.id, fromAssetID: asset.id)
        store.purgeHardDeleted(olderThan: TimeInterval(AppPreference.DaysToRetainDeletedItems) * 86_400)

        XCTAssertEqual(asset.events.count, 1, "a fresh tombstone must survive to keep syncing")
        XCTAssertEqual(asset.liveEvents.count, 0)
    }

    func testPurgeRemovesExpiredCustomPropertyTombstone() throws {
        let cat = try store.createCategory(name: "Vehicles")
        let asset = try store.createAsset(name: "Bike", categoryID: cat.id)
        let prop = try store.addCustomProperty(definition: PropertyDefinition(name: "Paint", type: .basic(.text)), toAssetID: asset.id)

        try store.removeCustomProperty(id: prop.id, fromAssetID: asset.id)
        prop.deletedAt = Date().addingTimeInterval(-15 * 86_400)
        store.purgeHardDeleted(olderThan: TimeInterval(AppPreference.DaysToRetainDeletedItems) * 86_400)

        XCTAssertEqual(asset.customProperties.count, 0, "the expired tombstone must be reaped")
    }

    func testPurgeKeepsUnexpiredCustomPropertyTombstone() throws {
        let cat = try store.createCategory(name: "Vehicles")
        let asset = try store.createAsset(name: "Bike", categoryID: cat.id)
        let prop = try store.addCustomProperty(definition: PropertyDefinition(name: "Paint", type: .basic(.text)), toAssetID: asset.id)

        try store.removeCustomProperty(id: prop.id, fromAssetID: asset.id)
        store.purgeHardDeleted(olderThan: TimeInterval(AppPreference.DaysToRetainDeletedItems) * 86_400)

        XCTAssertEqual(asset.customProperties.count, 1, "a fresh tombstone must survive to keep syncing")
        XCTAssertEqual(asset.liveCustomProperties.count, 0)
    }
}

// MARK: - Phase 4: photo download trigger

final class PhotoDownloadTriggerTests: XCTestCase {

    func testLoadThumbOnMissingFileReturnsNilWithoutThrowing() {
        let missingID = UUID()
        let result = PhotoStorage.loadThumb(id: missingID)
        XCTAssertNil(result, "loadThumb on a missing file must return nil, not throw")
    }

    func testLoadFullOnMissingFileReturnsNilWithoutThrowing() {
        let missingID = UUID()
        let result = PhotoStorage.loadFull(id: missingID)
        XCTAssertNil(result, "loadFull on a missing file must return nil, not throw")
    }

    func testLoadThumbReturnsDataWhenFileExists() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        AssetStore.baseDirOverride = tempDir
        defer {
            AssetStore.baseDirOverride = nil
            try? FileManager.default.removeItem(at: tempDir)
        }

        let id = UUID()
        let expected = Data("thumbnail_payload".utf8)
        try PhotoStorage.save(id: id, imageData: Data("full".utf8), thumbnailData: expected)

        let result = PhotoStorage.loadThumb(id: id)
        XCTAssertEqual(result, expected)
    }
}
