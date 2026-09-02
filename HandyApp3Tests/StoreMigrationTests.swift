import XCTest
@testable import HandyApp3

/// Exercises `StoreMigrator` (the versioned-step engine + un-gated `normalize`) and
/// `AssetStore.storeRequiresNewerApp` (the downgrade write-gate) — the two pieces that sit
/// around the actual v4→v5 transform, which `MigrationV5Tests.swift` covers on its own.
/// Pure-DTO tests build fixtures by hand, matching `StoreFileLayoutTests`; the gate tests
/// round-trip through `AssetStore`/`StoreFileLayout` since the behavior under test is what
/// `load()`/`save()` do.
final class StoreMigrationTests: XCTestCase {

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

    private func makeSnapshot(schemaVersion: Int) -> StoreSnapshotDTO {
        StoreSnapshotDTO(
            schemaVersion: schemaVersion,
            compositeTypes: [], comboLists: [], categories: [], assets: [], activityLog: [],
            backgroundTheme: BackgroundTheme.mist.rawValue
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

    // MARK: - StoreMigrator.migrate

    // steps run in ascending toVersion order and stamp schemaVersion after each
    func testMigrateAppliesStepsInOrderAndStampsVersion() {
        var order: [Int] = []
        let steps = [
            StoreMigration(toVersion: 4, transform: { _ in order.append(4) }),
            StoreMigration(toVersion: 5, transform: { _ in order.append(5) }),
        ]
        let result = StoreMigrator.migrate(makeSnapshot(schemaVersion: 3), steps: steps)

        XCTAssertEqual(order, [4, 5])
        XCTAssertEqual(result.schemaVersion, 5)
    }

    // a snapshot already at the current version has no gated step applied, and the hook
    // (which would only fire before a real migration) never fires
    func testMigrateSkipsStepsForCurrentSnapshot() {
        var hookFired = false
        let result = StoreMigrator.migrate(
            makeSnapshot(schemaVersion: storeSchemaVersion),
            willApplyVersionedSteps: { _ in hookFired = true }
        )

        XCTAssertEqual(result.schemaVersion, storeSchemaVersion)
        XCTAssertFalse(hookFired)
    }

    // a snapshot newer than this build's storeSchemaVersion is never touched or lowered —
    // protecting it is the downgrade gate's job, not migrate's
    func testMigrateLeavesNewerSnapshotUntouched() {
        var hookFired = false
        let result = StoreMigrator.migrate(
            makeSnapshot(schemaVersion: 99),
            willApplyVersionedSteps: { _ in hookFired = true }
        )

        XCTAssertEqual(result.schemaVersion, 99)
        XCTAssertFalse(hookFired)
    }

    // the un-gated purgedAt back-fill still runs regardless of schemaVersion, preserved
    // verbatim through the refactor from the old monolithic migrate(_:)
    func testNormalizeBackfillsPurgedAtRegardlessOfVersion() {
        let deletedAt = Date(timeIntervalSince1970: 1_000)
        var snap = makeSnapshot(schemaVersion: storeSchemaVersion)
        var cat = makeCategoryDTO()
        cat.isDeleted = true
        cat.deletedAt = deletedAt
        cat.isPurged = true
        cat.purgedAt = nil
        var asset = makeAssetDTO(categoryID: cat.id)
        asset.isDeleted = true
        asset.deletedAt = deletedAt
        asset.isPurged = true
        asset.purgedAt = nil
        snap.categories = [cat]
        snap.assets = [asset]

        let result = StoreMigrator.migrate(snap)

        XCTAssertEqual(result.categories[0].purgedAt, deletedAt)
        XCTAssertEqual(result.assets[0].purgedAt, deletedAt)
    }

    // MARK: - Downgrade write-gate

    // loading a store whose manifest reports a newer schemaVersion than this build sets the
    // gate and makes save() a full no-op — the on-disk manifest must never be re-stamped down
    func testLoadOfNewerSchemaStoreGatesWrites() throws {
        let newerSnap = makeSnapshot(schemaVersion: storeSchemaVersion + 1)
        _ = store.fileLayout.write(newerSnap, baseDir: AssetStore.baseDir)

        let freshStore = AssetStore()
        XCTAssertTrue(freshStore.load())
        XCTAssertTrue(freshStore.storeRequiresNewerApp)

        let beforeLayout = StoreFileLayout()
        let before = try XCTUnwrap(beforeLayout.read(baseDir: AssetStore.baseDir))
        XCTAssertEqual(before.snapshot.schemaVersion, storeSchemaVersion + 1)

        freshStore.markDirty()
        freshStore.save()

        let afterLayout = StoreFileLayout()
        let after = try XCTUnwrap(afterLayout.read(baseDir: AssetStore.baseDir))
        XCTAssertEqual(after.snapshot.schemaVersion, storeSchemaVersion + 1,
                       "an older build must never re-stamp a newer store's manifest down")
        XCTAssertEqual(beforeLayout.storeDigest, afterLayout.storeDigest,
                       "save() must be a full no-op while storeRequiresNewerApp")
    }

    // a store at (or below) this build's schemaVersion loads writable, as before
    func testCurrentSchemaStoreLoadsWritable() throws {
        let snap = makeSnapshot(schemaVersion: storeSchemaVersion)
        _ = store.fileLayout.write(snap, baseDir: AssetStore.baseDir)

        let freshStore = AssetStore()
        XCTAssertTrue(freshStore.load())
        XCTAssertFalse(freshStore.storeRequiresNewerApp)

        let cat = try freshStore.createCategory(name: "Writable Test")
        freshStore.save()

        let reread = try XCTUnwrap(StoreFileLayout().read(baseDir: AssetStore.baseDir))
        XCTAssertTrue(reread.snapshot.categories.contains { $0.id == cat.id })
    }

    // factoryReset is the one legitimate way an old build recovers a stuck, gated store
    func testFactoryResetClearsGate() throws {
        let newerSnap = makeSnapshot(schemaVersion: storeSchemaVersion + 1)
        _ = store.fileLayout.write(newerSnap, baseDir: AssetStore.baseDir)

        let freshStore = AssetStore()
        XCTAssertTrue(freshStore.load())
        XCTAssertTrue(freshStore.storeRequiresNewerApp)

        freshStore.factoryReset()
        XCTAssertFalse(freshStore.storeRequiresNewerApp)

        let cat = try freshStore.createCategory(name: "Post Reset")
        freshStore.save()
        let reread = try XCTUnwrap(StoreFileLayout().read(baseDir: AssetStore.baseDir))
        XCTAssertTrue(reread.snapshot.categories.contains { $0.id == cat.id })
    }
}
