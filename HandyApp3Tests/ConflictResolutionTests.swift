import XCTest
@testable import HandyApp3

/// Coverage for per-shard conflict resolution. Real `NSFileVersion` conflicts can't be
/// fabricated in a unit test, so `FakeConflictSource` stands in for `FileVersionConflictSource`
/// — this exercises the actual merge-then-resolve logic (`ShardConflictMerger` +
/// `AssetStore.resolveShardConflicts`), leaving only the `NSFileVersion` plumbing itself
/// unverified here (see the manual checklist for that).
final class ConflictResolutionTests: XCTestCase {

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

    /// In-memory stand-in for `FileVersionConflictSource`: a fixed map of relative path →
    /// conflicting byte blobs, with a spy on which paths got `resolve(at:)` called.
    final class FakeConflictSource: ConflictSource {
        var conflicts: [String: [Data]] = [:]
        private(set) var resolvedPaths: [String] = []

        func conflictedPaths(baseDir: URL) -> [String] { Array(conflicts.keys) }
        // conflicts is keyed by relative path (may include subdirectories); match by suffix.
        func conflictingContents(at url: URL) -> [Data] {
            for (path, blobs) in conflicts where url.path.hasSuffix(path) { return blobs }
            return []
        }
        func resolve(at url: URL) {
            for path in conflicts.keys where url.path.hasSuffix(path) { resolvedPaths.append(path) }
        }
    }

    // MARK: - ShardConflictMerger (pure)

    func testMergesConflictingCategoryRenames() throws {
        let catID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let current = CategoryDTO(id: catID, name: "Old", iconName: "tray", propertyTemplates: [],
                                  isDeleted: false, deletedAt: nil, modifyDate: t0)
        let conflicting = CategoryDTO(id: catID, name: "New", iconName: "tray", propertyTemplates: [],
                                      isDeleted: false, deletedAt: nil, modifyDate: t0.addingTimeInterval(10))
        let encoder = CanonicalCodec.makeEncoder()
        let currentBytes = try encoder.encode([current])
        let conflictBytes = try encoder.encode([conflicting])

        let mergedBytes = try XCTUnwrap(ShardConflictMerger.mergeShardBytes(
            relativePath: "Definitions/categories.json", current: currentBytes, conflicts: [conflictBytes]))
        let merged = try CanonicalCodec.makeDecoder().decode([CategoryDTO].self, from: mergedBytes)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].name, "New", "the later rename must win")
    }

    func testMergesConflictingRenamesOfDifferentCategoriesWithoutLosingEither() throws {
        // The regression this exists for: two devices rename two DIFFERENT categories in the
        // same shard file concurrently. A bare removeOtherVersionsOfItem would throw one away
        // entirely; the merge must keep both.
        let idA = UUID(), idB = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let current = [
            CategoryDTO(id: idA, name: "A renamed", iconName: "tray", propertyTemplates: [], isDeleted: false, deletedAt: nil, modifyDate: t0.addingTimeInterval(10)),
            CategoryDTO(id: idB, name: "B original", iconName: "tray", propertyTemplates: [], isDeleted: false, deletedAt: nil, modifyDate: t0),
        ]
        let conflicting = [
            CategoryDTO(id: idA, name: "A original", iconName: "tray", propertyTemplates: [], isDeleted: false, deletedAt: nil, modifyDate: t0),
            CategoryDTO(id: idB, name: "B renamed", iconName: "tray", propertyTemplates: [], isDeleted: false, deletedAt: nil, modifyDate: t0.addingTimeInterval(10)),
        ]
        let encoder = CanonicalCodec.makeEncoder()
        let mergedBytes = try XCTUnwrap(ShardConflictMerger.mergeShardBytes(
            relativePath: "Definitions/categories.json",
            current: try encoder.encode(current), conflicts: [try encoder.encode(conflicting)]))
        let merged = try CanonicalCodec.makeDecoder().decode([CategoryDTO].self, from: mergedBytes)
        let byID = Dictionary(uniqueKeysWithValues: merged.map { ($0.id, $0) })
        XCTAssertEqual(byID[idA]?.name, "A renamed")
        XCTAssertEqual(byID[idB]?.name, "B renamed")
    }

    func testMergesConflictingAssetVersions() throws {
        let catID = UUID()
        let assetID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        func makeAsset(name: String, headModifyDate: Date) -> AssetDTO {
            AssetDTO(id: assetID, name: name, categoryID: catID, baseProperties: [], customProperties: [],
                    photos: [], events: [], transactions: [], parentID: nil, isDeleted: false, deletedAt: nil,
                    createdDate: t0, modifiedDate: t0, parentageModifyDate: t0, headModifyDate: headModifyDate)
        }
        let current = makeAsset(name: "Old", headModifyDate: t0)
        let conflicting = makeAsset(name: "New", headModifyDate: t0.addingTimeInterval(10))
        let encoder = CanonicalCodec.makeEncoder()
        let mergedBytes = try XCTUnwrap(ShardConflictMerger.mergeShardBytes(
            relativePath: "Assets/\(assetID.uuidString).json",
            current: try encoder.encode(current), conflicts: [try encoder.encode(conflicting)]))
        let merged = try CanonicalCodec.makeDecoder().decode(AssetDTO.self, from: mergedBytes)
        XCTAssertEqual(merged.name, "New")
    }

    func testConflictingAssetVersionsFoldToPurgedWhenEitherSideIsPurged() throws {
        // A per-shard NSFileVersion conflict on Assets/<uuid>.json folds through `joinAsset`
        // directly, never `SnapshotReconciler.reap` — this is what makes it inherit the same
        // "purge always wins" rule without any extra plumbing in `ShardConflictMerger`.
        let catID = UUID()
        let assetID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let purgedVersion = AssetDTO(id: assetID, name: "Car", categoryID: catID, baseProperties: [], customProperties: [],
                                     photos: [], events: [], transactions: [], parentID: nil, isDeleted: true, deletedAt: t0,
                                     createdDate: t0, modifiedDate: t0, parentageModifyDate: t0, headModifyDate: t0,
                                     isPurged: true)
        let stillFullVersion = AssetDTO(id: assetID, name: "Car", categoryID: catID,
                                        baseProperties: [], customProperties: [],
                                        photos: [PhotoDTO(id: UUID(), caption: "", addedDate: t0, fullImage: nil, thumbnail: nil,
                                                          modifyDate: t0, isDeleted: false, deletedAt: nil)],
                                        events: [], transactions: [], parentID: nil, isDeleted: true, deletedAt: t0,
                                        createdDate: t0, modifiedDate: t0, parentageModifyDate: t0,
                                        headModifyDate: t0.addingTimeInterval(10))
        let encoder = CanonicalCodec.makeEncoder()
        let mergedBytes = try XCTUnwrap(ShardConflictMerger.mergeShardBytes(
            relativePath: "Assets/\(assetID.uuidString).json",
            current: try encoder.encode(stillFullVersion), conflicts: [try encoder.encode(purgedVersion)]))
        let merged = try CanonicalCodec.makeDecoder().decode(AssetDTO.self, from: mergedBytes)
        XCTAssertEqual(merged.isPurged, true)
        XCTAssertTrue(merged.photos.isEmpty, "purge must win even though the other version has a later headModifyDate")
    }

    func testConflictingCategoryVersionsFoldToPurgedWhenEitherSideIsPurged() throws {
        // `Definitions/categories.json` conflicts fold through `joinCategory` directly — this
        // is what makes it inherit the same "purge always wins" rule without any extra
        // plumbing in `ShardConflictMerger`.
        let catID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let purgedVersion = CategoryDTO(id: catID, name: "", iconName: "", propertyTemplates: [],
                                        isDeleted: true, deletedAt: t0, modifyDate: t0, isPurged: true)
        let stillFullVersion = CategoryDTO(id: catID, name: "Appliances", iconName: "washer",
                                           propertyTemplates: [], isDeleted: true, deletedAt: t0,
                                           modifyDate: t0.addingTimeInterval(10))
        let encoder = CanonicalCodec.makeEncoder()
        let mergedBytes = try XCTUnwrap(ShardConflictMerger.mergeShardBytes(
            relativePath: "Definitions/categories.json",
            current: try encoder.encode([stillFullVersion]), conflicts: [try encoder.encode([purgedVersion])]))
        let merged = try CanonicalCodec.makeDecoder().decode([CategoryDTO].self, from: mergedBytes)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].isPurged, true)
        XCTAssertEqual(merged[0].name, "", "purge must win even though the other version has a later modifyDate")
    }

    func testUnknownShardPathReturnsNil() {
        XCTAssertNil(ShardConflictMerger.mergeShardBytes(relativePath: "nonsense.json", current: Data(), conflicts: [Data()]))
    }

    // MARK: - resolveShardConflicts end to end (fake source, real disk)

    func testResolveShardConflictsWritesMergedContentAndMarksResolved() throws {
        let cat = try store.createCategory(name: "Original")
        store.save()

        let renamedElsewhere = CategoryDTO(id: cat.id, name: "Renamed On Peer", iconName: cat.iconName,
                                           propertyTemplates: [], isDeleted: false, deletedAt: nil,
                                           modifyDate: Date().addingTimeInterval(100))
        let conflictBytes = try CanonicalCodec.makeEncoder().encode([renamedElsewhere])

        let fake = FakeConflictSource()
        fake.conflicts["Definitions/categories.json"] = [conflictBytes]
        store.resolveShardConflicts(baseDir: tempDir, source: fake)

        XCTAssertEqual(fake.resolvedPaths, ["Definitions/categories.json"])
        let onDisk = try Data(contentsOf: tempDir.appendingPathComponent("Definitions/categories.json"))
        let decoded = try CanonicalCodec.makeDecoder().decode([CategoryDTO].self, from: onDisk)
        XCTAssertEqual(decoded.first?.name, "Renamed On Peer", "the merged (newer) name must be written back to disk")
    }

    func testResolveShardConflictsNeverResolvesWhenMergeFails() throws {
        let fake = FakeConflictSource()
        fake.conflicts["nonexistent.json"] = [Data("garbage".utf8)]
        store.resolveShardConflicts(baseDir: tempDir, source: fake)
        XCTAssertTrue(fake.resolvedPaths.isEmpty, "a path that can't even be read locally must not be marked resolved")
    }
}
