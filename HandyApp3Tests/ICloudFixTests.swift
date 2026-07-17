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

    func testImportDeletesUnreferencedPhotoFiles() throws {
        // Write orphan files that no snapshot references.
        let orphanID = UUID()
        PhotoStorage.save(id: orphanID,
                          imageData: Data("orphan_full".utf8),
                          thumbnailData: Data("orphan_thumb".utf8))

        let cat = try store.createCategory(name: "Fleet")
        let export = try XCTUnwrap(store.exportJSON())
        try store.importJSON(data: export)

        XCTAssertFalse(FileManager.default.fileExists(atPath: PhotoStorage.fullURL(id: orphanID).path),
                       "importJSON must delete photo files not referenced by the incoming snapshot")
        XCTAssertFalse(FileManager.default.fileExists(atPath: PhotoStorage.thumbURL(id: orphanID).path))
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
        let diskData = try Data(contentsOf: AssetStore.storeURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snap = try decoder.decode(StoreSnapshotDTO.self, from: diskData)
        XCTAssertGreaterThan(snap.categories.count, 0,
                             "persisted snapshot after factoryReset must contain seeded categories")
    }

    func testFactoryResetDoesNotDeleteStoreFile() throws {
        // Perform an initial save so the file exists before reset.
        store.save()
        XCTAssertTrue(FileManager.default.fileExists(atPath: AssetStore.storeURL.path))

        store.factoryReset()

        XCTAssertTrue(FileManager.default.fileExists(atPath: AssetStore.storeURL.path),
                      "factoryReset must overwrite store.json, not delete it — deletions are ignored by other devices")
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
        PhotoStorage.save(id: id, imageData: Data("full".utf8), thumbnailData: expected)

        let result = PhotoStorage.loadThumb(id: id)
        XCTAssertEqual(result, expected)
    }
}
