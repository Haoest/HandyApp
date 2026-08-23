import XCTest
@testable import HandyApp3

/// Coverage for `BuiltInTypes.assetSeeds` / `AssetStore.seedBuiltInAssets` /
/// `seedSampleAutomobile`: the two starter assets ("My Home", "Testarossa 85") now seed at
/// deterministic ids, and the seeder is presence-keyed (any state, including a purged husk)
/// rather than liveness-keyed — see `seedBuiltInAssets`'s doc comment for why. This is what
/// stops `factoryReset()` followed by `importJSON` from producing a duplicate-named asset.
final class SeedAssetIdentityTests: XCTestCase {

    var store: AssetStore!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        AssetStore.baseDirOverride = tempDir
        store = AssetStore()
        store.seedBuiltInComboLists()
        store.seedBuiltInCategories()
        store.seedBuiltInTypes()
    }

    override func tearDown() {
        super.tearDown()
        AssetStore.baseDirOverride = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSeedsLandOnDeterministicIDs() throws {
        store.seedBuiltInAssets()

        for seed in BuiltInTypes.assetSeeds {
            let asset = try XCTUnwrap(store.assets[seed.id], "\(seed.assetName) must be seeded at its deterministic id")
            XCTAssertEqual(asset.name, seed.assetName)
        }
    }

    func testSeedSampleAutomobileFillsRecordAtCanonicalID() throws {
        store.seedBuiltInAssets()
        store.seedSampleAutomobile()

        let car = try XCTUnwrap(store.assets[BuiltInTypes.sampleAutomobileID])
        XCTAssertEqual(car.baseProperties.first(where: { $0.definition.name == "Make" })?.value, .text("Ferrari"))
    }

    func testSeedingTwiceCreatesNothingMore() {
        store.seedBuiltInAssets()
        let countAfterFirst = store.assets.count

        store.seedBuiltInAssets()

        XCTAssertEqual(store.assets.count, countAfterFirst, "calling seedBuiltInAssets again must not create duplicates")
    }

    func testPurgedSeedHuskIsNotRecreated() throws {
        store.seedBuiltInAssets()
        let seed = try XCTUnwrap(BuiltInTypes.assetSeeds.first(where: { $0.assetName == "My Home" }))
        try store.hardDeleteAsset(id: seed.id)
        XCTAssertTrue(try XCTUnwrap(store.assets[seed.id]).isPurged)

        store.seedBuiltInAssets()

        XCTAssertEqual(
            store.assets.values.filter { $0.name == "My Home" }.count, 1,
            "a purged husk at the canonical id must block re-seeding, not just be ignored"
        )
        XCTAssertTrue(try XCTUnwrap(store.assets[seed.id]).isPurged, "the husk itself must remain purged, not be revived by the seeder")
    }

    func testSoftDeletedSeedIsNotResurrectedOrDuplicated() throws {
        store.seedBuiltInAssets()
        let seed = try XCTUnwrap(BuiltInTypes.assetSeeds.first(where: { $0.assetName == "My Home" }))
        try store.softDeleteAsset(id: seed.id)

        store.seedBuiltInAssets()

        XCTAssertEqual(store.assets.values.filter { $0.name == "My Home" }.count, 1)
        XCTAssertTrue(try XCTUnwrap(store.assets[seed.id]).isDeleted, "seeding again must not un-delete a deliberately trashed seed")
    }

    func testLegacyRandomIDAssetBlocksSecondSeed() throws {
        let cat = try XCTUnwrap(store.categories.values.first(where: { $0.name == SystemCategory.residentialHousing.rawValue }))
        // Simulate a pre-deterministic-id install: same name/category, random id.
        _ = try store.createAsset(name: "My Home", categoryID: cat.id)

        store.seedBuiltInAssets()

        XCTAssertEqual(store.assets.values.filter { $0.name == "My Home" }.count, 1,
                       "a legacy random-id asset with the same name must block a second, canonical-id copy")
        XCTAssertNil(store.assets[BuiltInTypes.assetSeeds.first(where: { $0.assetName == "My Home" })!.id],
                     "no asset should be created at the canonical id when a legacy stray already represents this seed")
    }
}
