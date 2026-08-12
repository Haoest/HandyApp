import XCTest
@testable import HandyApp3

/// Exercises `StoreFileLayout` directly — the multi-file read/write engine behind
/// `AssetStore.save()`/`load()` — for the invariants the split rests on: idempotent writes,
/// suppressing the orphan sweep after a partial read, legacy migration, structural shards
/// failing the whole read rather than a partial one, and deterministic encoding.
/// Tests that exercise the full round trip through `AssetStore`'s public API (legacy migration
/// via `load()`, a composite property crossing the asset/definitions file boundary) construct
/// data through `AssetStore` instead of hand-built DTOs, matching the other persistence suites.
final class StoreFileLayoutTests: XCTestCase {

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

    // MARK: - DTO builders

    private func makeSnapshot(
        compositeTypes: [CompositeTypeDTO] = [],
        comboLists: [ComboListDTO] = [],
        categories: [CategoryDTO] = [],
        assets: [AssetDTO] = [],
        activityLog: [ActivityLogDTO] = [],
        backgroundTheme: String = BackgroundTheme.mist.rawValue
    ) -> StoreSnapshotDTO {
        StoreSnapshotDTO(
            schemaVersion: storeSchemaVersion,
            compositeTypes: compositeTypes,
            comboLists: comboLists,
            categories: categories,
            assets: assets,
            activityLog: activityLog,
            backgroundTheme: backgroundTheme
        )
    }

    private func makeCategoryDTO(id: UUID = UUID(), name: String = "Category") -> CategoryDTO {
        CategoryDTO(id: id, name: name, iconName: "square.grid.2x2",
                    propertyTemplates: [], isDeleted: false, deletedAt: nil)
    }

    private func makeAssetDTO(id: UUID = UUID(), name: String = "Asset", categoryID: UUID) -> AssetDTO {
        let now = Date()
        return AssetDTO(
            id: id, name: name, categoryID: categoryID,
            baseProperties: [], customProperties: [],
            photos: [], events: [], transactions: [],
            parentID: nil, isDeleted: false, deletedAt: nil,
            createdDate: now, modifiedDate: now, parentageModifyDate: now
        )
    }

    // MARK: - 1. Idempotent write

    func testIdempotentWriteTouchesNothingOnRepeat() throws {
        let catID = UUID()
        let assetID = UUID()
        let snap = makeSnapshot(categories: [makeCategoryDTO(id: catID)],
                                assets: [makeAssetDTO(id: assetID, categoryID: catID)])

        let first = store.fileLayout.write(snap, baseDir: AssetStore.baseDir)
        XCTAssertFalse(first.writtenPaths.isEmpty, "the first write of new content must write something")

        let second = store.fileLayout.write(snap, baseDir: AssetStore.baseDir)
        XCTAssertTrue(second.writtenPaths.isEmpty, "re-writing identical content must touch no files")
        XCTAssertTrue(second.deletedPaths.isEmpty)

        // A fresh instance (simulating a new launch) must seed its digest cache from what it
        // reads, not only from what it itself wrote — otherwise every launch rewrites
        // everything once, defeating the point of the split under sync.
        let freshLayout = StoreFileLayout()
        XCTAssertNotNil(freshLayout.read(baseDir: AssetStore.baseDir))
        let third = freshLayout.write(snap, baseDir: AssetStore.baseDir)
        XCTAssertTrue(third.writtenPaths.isEmpty, "a fresh instance that just read this exact content must not rewrite it")
    }

    // MARK: - 2. Orphan-sweep suppression on partial read

    func testOrphanSweepSuppressedAfterPartialRead() throws {
        let catID = UUID()
        let goodID = UUID()
        let badID = UUID()
        let snap = makeSnapshot(
            categories: [makeCategoryDTO(id: catID)],
            assets: [makeAssetDTO(id: goodID, categoryID: catID), makeAssetDTO(id: badID, categoryID: catID)]
        )
        store.fileLayout.write(snap, baseDir: AssetStore.baseDir)

        let badURL = AssetStore.baseDir.appendingPathComponent("Assets/\(badID.uuidString).json")
        try Data("not json".utf8).write(to: badURL)

        let freshLayout = StoreFileLayout()
        let result = try XCTUnwrap(freshLayout.read(baseDir: AssetStore.baseDir))
        XCTAssertFalse(result.isComplete, "a corrupt asset file must be flagged, not silently dropped")
        XCTAssertTrue(result.snapshot.assets.contains { $0.id == goodID }, "the other asset must still load")
        XCTAssertFalse(result.snapshot.assets.contains { $0.id == badID })

        // Writing back what a real applySnapshot would now hold (the corrupt asset never
        // decoded, so it's simply absent) must not sweep the file it couldn't verify — that
        // would turn a transient read failure into a permanent deletion.
        let snapWithoutBad = makeSnapshot(categories: [makeCategoryDTO(id: catID)],
                                          assets: [makeAssetDTO(id: goodID, categoryID: catID)])
        freshLayout.write(snapWithoutBad, baseDir: AssetStore.baseDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: badURL.path),
                     "orphan sweep must be suppressed after an incomplete read")
    }

    // MARK: - 3. Legacy migration

    func testLegacyMigrationProducesNewLayoutAndBackup() throws {
        let catID = UUID()
        let assetID = UUID()
        let legacy = makeSnapshot(categories: [makeCategoryDTO(id: catID)],
                                  assets: [makeAssetDTO(id: assetID, categoryID: catID)])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let legacyData = try encoder.encode(legacy)
        try legacyData.write(to: AssetStore.storeURL, options: .atomic)

        let result = try XCTUnwrap(store.fileLayout.read(baseDir: AssetStore.baseDir))
        XCTAssertTrue(result.wasMigratedFromLegacy)
        XCTAssertTrue(result.snapshot.assets.contains { $0.id == assetID })

        let backupURL = AssetStore.baseDir.appendingPathComponent(StoreFileLayout.legacyBackupFilename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path),
                     "a backup of the legacy file must be taken before migration")

        // The read alone doesn't overwrite store.json — that's the caller's (load()'s)
        // subsequent write, matching AssetStore+Persistence.swift's actual sequencing.
        store.fileLayout.write(legacy, baseDir: AssetStore.baseDir)
        let manifestData = try Data(contentsOf: AssetStore.storeURL)
        let manifest = try JSONDecoder().decode(StoreManifestDTO.self, from: manifestData)
        XCTAssertEqual(manifest.layoutVersion, storeLayoutVersion)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: AssetStore.baseDir.appendingPathComponent("Assets/\(assetID.uuidString).json").path))
    }

    // MARK: - 4. Missing definitions is a hard failure

    func testMissingDefinitionsShardFailsReadEntirely() throws {
        let catID = UUID()
        let assetID = UUID()
        let snap = makeSnapshot(categories: [makeCategoryDTO(id: catID)],
                                assets: [makeAssetDTO(id: assetID, categoryID: catID)])
        store.fileLayout.write(snap, baseDir: AssetStore.baseDir)

        try FileManager.default.removeItem(
            at: AssetStore.baseDir.appendingPathComponent("Definitions/types.json"))

        let freshLayout = StoreFileLayout()
        XCTAssertNil(freshLayout.read(baseDir: AssetStore.baseDir),
                    "a missing structural shard must fail the whole read rather than return an amputated snapshot")
    }

    // MARK: - 5. Orphan deletion happy path

    func testOrphanDeletionRemovesFileNoLongerInSnapshot() throws {
        let catID = UUID()
        let keepID = UUID()
        let removeID = UUID()
        let full = makeSnapshot(
            categories: [makeCategoryDTO(id: catID)],
            assets: [makeAssetDTO(id: keepID, categoryID: catID), makeAssetDTO(id: removeID, categoryID: catID)]
        )
        store.fileLayout.write(full, baseDir: AssetStore.baseDir)
        XCTAssertNotNil(store.fileLayout.read(baseDir: AssetStore.baseDir))

        let withoutRemoved = makeSnapshot(categories: [makeCategoryDTO(id: catID)],
                                          assets: [makeAssetDTO(id: keepID, categoryID: catID)])
        let report = store.fileLayout.write(withoutRemoved, baseDir: AssetStore.baseDir)

        XCTAssertTrue(report.deletedPaths.contains("Assets/\(removeID.uuidString).json"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: AssetStore.baseDir.appendingPathComponent("Assets/\(removeID.uuidString).json").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: AssetStore.baseDir.appendingPathComponent("Assets/\(keepID.uuidString).json").path))
    }

    // MARK: - 6. Selective write

    func testSelectiveWriteTouchesOnlyTheChangedAsset() throws {
        let catID = UUID()
        let idA = UUID()
        let idB = UUID()
        let snap1 = makeSnapshot(
            categories: [makeCategoryDTO(id: catID)],
            assets: [makeAssetDTO(id: idA, name: "A", categoryID: catID),
                     makeAssetDTO(id: idB, name: "B", categoryID: catID)]
        )
        store.fileLayout.write(snap1, baseDir: AssetStore.baseDir)

        let snap2 = makeSnapshot(
            categories: [makeCategoryDTO(id: catID)],
            assets: [makeAssetDTO(id: idA, name: "A renamed", categoryID: catID),
                     makeAssetDTO(id: idB, name: "B", categoryID: catID)]
        )
        let report = store.fileLayout.write(snap2, baseDir: AssetStore.baseDir)

        XCTAssertEqual(report.writtenPaths, ["Assets/\(idA.uuidString).json"])
        XCTAssertTrue(report.deletedPaths.isEmpty)
    }

    // MARK: - 7. Manifest-missing recovery

    func testMissingManifestRecoversFromTreeWithoutDeletingAssets() throws {
        let catID = UUID()
        let assetID = UUID()
        let snap = makeSnapshot(categories: [makeCategoryDTO(id: catID)],
                                assets: [makeAssetDTO(id: assetID, categoryID: catID)])
        store.fileLayout.write(snap, baseDir: AssetStore.baseDir)

        try FileManager.default.removeItem(at: AssetStore.storeURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: AssetStore.storeURL.path))

        let freshLayout = StoreFileLayout()
        let result = try XCTUnwrap(freshLayout.read(baseDir: AssetStore.baseDir),
                                   "a missing manifest with a populated tree must still count as an existing store")
        XCTAssertTrue(result.snapshot.assets.contains { $0.id == assetID })

        let report = freshLayout.write(result.snapshot, baseDir: AssetStore.baseDir)
        XCTAssertTrue(report.deletedPaths.isEmpty, "recovering a missing manifest must not delete any asset files")
        XCTAssertTrue(FileManager.default.fileExists(atPath: AssetStore.storeURL.path),
                     "the manifest must be regenerated")
    }

    // MARK: - 8. Cross-shard reference survival

    func testCompositePropertySurvivesSaveAndLoadAcrossShards() throws {
        let sizeType = store.createCompositeType(
            name: "2D Size",
            fields: [
                PropertyDefinition(name: "Width", type: .basic(.number), isRequired: true),
                PropertyDefinition(name: "Length", type: .basic(.number), isRequired: true),
            ]
        )
        let cat = try store.createCategory(name: "Rugs")
        let asset = try store.createAsset(name: "Living room rug", categoryID: cat.id)
        let def = PropertyDefinition(name: "Size", type: .composite(sizeType), isRequired: false)
        try store.addCustomProperty(
            definition: def,
            value: .composite(["Width": .number(8), "Length": .number(10)]),
            toAssetID: asset.id
        )
        store.save()

        let reloaded = AssetStore()
        XCTAssertTrue(reloaded.load())

        let reloadedAsset = try XCTUnwrap(reloaded.assets[asset.id])
        let prop = try XCTUnwrap(reloadedAsset.customProperties.first { $0.definition.name == "Size" })
        guard case .composite(let ct) = prop.definition.type else {
            XCTFail("expected a composite property type")
            return
        }
        XCTAssertEqual(ct.id, sizeType.id, "the property's composite type must be the same object identity as the shared definition, resolved across the asset/definitions file boundary")
        XCTAssertEqual(ct.fields.map(\.name).sorted(), ["Length", "Width"])
        XCTAssertEqual(prop.value, .composite(["Width": .number(8), "Length": .number(10)]))
    }

    // MARK: - 9. Determinism

    func testWritingSameSnapshotToTwoDirsProducesByteIdenticalFiles() throws {
        let catID = UUID()
        let assetID = UUID()
        let snap = makeSnapshot(categories: [makeCategoryDTO(id: catID)],
                                assets: [makeAssetDTO(id: assetID, categoryID: catID)])

        let dirB = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dirB) }

        StoreFileLayout().write(snap, baseDir: tempDir)
        StoreFileLayout().write(snap, baseDir: dirB)

        for path in ["Definitions/types.json", "Definitions/combolists.json", "Definitions/categories.json",
                     "Assets/\(assetID.uuidString).json", "Activity/log.json", "store.json"] {
            let bytesA = try Data(contentsOf: tempDir.appendingPathComponent(path))
            let bytesB = try Data(contentsOf: dirB.appendingPathComponent(path))
            XCTAssertEqual(bytesA, bytesB, "\(path) must encode identically across independent writes of the same snapshot")
        }
    }
}
