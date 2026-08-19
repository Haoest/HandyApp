import XCTest
@testable import HandyApp3

/// Tier 1b: two `AssetStore` instances relaying snapshots directly in-process via
/// `buildSnapshot()` → `SnapshotReconciler.merge` → `applyInPlace` — no file I/O, no
/// `StoreFileLayout` involved at all. Proves the full merge+apply round trip converges,
/// preserves object identity, and doesn't clobber a live mutation made after a snapshot was
/// captured. Cannot cover anything below the snapshot boundary — sharding, the digest cache,
/// echo suppression, the orphan sweep, `NSFileVersion`, `NSFileCoordinator`,
/// `savesSuspended`/`isComplete` lifecycle, or photo files. `SyncRelayTests` (Tier 2) covers
/// those over real per-device directories.
final class TwoDeviceRelayTests: XCTestCase {

    var storeA: AssetStore!
    var storeB: AssetStore!
    private var tempDirA: URL!
    private var tempDirB: URL!

    override func setUp() {
        super.setUp()
        // AssetStore.baseDirOverride is static, so the two stores can't each have their own
        // override active at once — harmless here since this harness never calls save()/load(),
        // only buildSnapshot()/applyInPlace(), but each gets its own temp dir at construction
        // time so that assumption is explicit rather than accidental.
        tempDirA = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        AssetStore.baseDirOverride = tempDirA
        storeA = AssetStore()
        storeA.savesSuspended = true

        tempDirB = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        AssetStore.baseDirOverride = tempDirB
        storeB = AssetStore()
        storeB.savesSuspended = true

        AssetStore.baseDirOverride = tempDirA
    }

    override func tearDown() {
        super.tearDown()
        AssetStore.baseDirOverride = nil
        try? FileManager.default.removeItem(at: tempDirA)
        try? FileManager.default.removeItem(at: tempDirB)
    }

    private func relay(from source: AssetStore, into target: AssetStore) {
        let merged = SnapshotReconciler.merge(target.buildSnapshot(), source.buildSnapshot())
        target.applyInPlace(merged)
    }

    /// Relays both directions repeatedly until both sides encode identically. Convergence
    /// should take at most two rounds; more than a handful is a real bug, not a fluke.
    private func settle(_ a: AssetStore, _ b: AssetStore, maxRounds: Int = 5) {
        for _ in 0..<maxRounds {
            relay(from: a, into: b)
            relay(from: b, into: a)
            if converged(a, b) { return }
        }
        XCTFail("did not converge within \(maxRounds) rounds")
    }

    private func converged(_ a: AssetStore, _ b: AssetStore) -> Bool {
        CanonicalCodec.encode(a.buildSnapshot().canonicalized()) == CanonicalCodec.encode(b.buildSnapshot().canonicalized())
    }

    // MARK: - Convergence

    func testConcurrentEditsToDifferentAssetsBothSurvive() throws {
        let cat = try storeA.createCategory(name: "Vehicle")
        let assetX = try storeA.createAsset(name: "X", categoryID: cat.id)
        let assetY = try storeA.createAsset(name: "Y", categoryID: cat.id)
        relay(from: storeA, into: storeB)

        // Every stamp the reconciler compares is truncated to whole seconds — matching what a
        // disk round trip already does — so two edits landing in the same wall-clock second
        // are a genuine, unresolvable-by-recency tie. Sleeping across a second boundary is
        // what makes "the edit wins" a deterministic, testable outcome here.
        Thread.sleep(forTimeInterval: 1.1)
        try storeA.updateAsset(id: assetX.id, name: "X renamed")
        try storeB.updateAsset(id: assetY.id, name: "Y renamed")
        settle(storeA, storeB)

        XCTAssertEqual(storeA.assets[assetX.id]?.name, "X renamed")
        XCTAssertEqual(storeA.assets[assetY.id]?.name, "Y renamed")
        XCTAssertEqual(storeB.assets[assetX.id]?.name, "X renamed")
        XCTAssertEqual(storeB.assets[assetY.id]?.name, "Y renamed")
    }

    /// The direct regression test for whole-record LWW on `modifiedDate`: a rename (governed by
    /// `headModifyDate`) on one device must survive an unrelated later child-collection edit
    /// (which only bumps `modifiedDate`, a rollup) on the other.
    func testRenameAndUnrelatedEventAddBothSurvive() throws {
        let cat = try storeA.createCategory(name: "Vehicle")
        let asset = try storeA.createAsset(name: "Car", categoryID: cat.id)
        relay(from: storeA, into: storeB)

        Thread.sleep(forTimeInterval: 1.1)
        try storeA.updateAsset(id: asset.id, name: "Renamed")
        _ = try storeB.addEvent(title: "Oil change", date: Date(), toAssetID: asset.id)
        settle(storeA, storeB)

        let merged = try XCTUnwrap(storeA.assets[asset.id])
        XCTAssertEqual(merged.name, "Renamed")
        XCTAssertEqual(merged.events.count, 1)
    }

    func testDeleteWinsOverEarlierUnrelatedEdit() throws {
        let cat = try storeA.createCategory(name: "Vehicle")
        let asset = try storeA.createAsset(name: "Car", categoryID: cat.id)
        relay(from: storeA, into: storeB)

        _ = try storeB.addEvent(title: "Service", date: Date(), toAssetID: asset.id)
        // addEvent never touches headModifyDate, so this sleep isn't about the event at all —
        // it's what separates the asset's CREATION-time headModifyDate from its DELETE-time
        // one by a full truncated second, so the delete deterministically outranks it.
        Thread.sleep(forTimeInterval: 1.1)
        try storeA.softDeleteAsset(id: asset.id)
        settle(storeA, storeB)

        XCTAssertTrue(storeA.assets[asset.id]?.isDeleted ?? false)
        XCTAssertTrue(storeB.assets[asset.id]?.isDeleted ?? false)
    }

    func testTombstonePropagatesAcrossDevices() throws {
        let cat = try storeA.createCategory(name: "Vehicle")
        let asset = try storeA.createAsset(name: "Car", categoryID: cat.id)
        relay(from: storeA, into: storeB)

        Thread.sleep(forTimeInterval: 1.1)
        try storeA.softDeleteAsset(id: asset.id)
        settle(storeA, storeB)

        XCTAssertTrue(storeB.assets[asset.id]?.isDeleted ?? false, "a delete on A must propagate to B")
    }

    func testCycleFormingReparentIsNormalizedIdenticallyOnBothSides() throws {
        let cat = try storeA.createCategory(name: "Vehicle")
        let x = try storeA.createAsset(name: "X", categoryID: cat.id)
        let y = try storeA.createAsset(name: "Y", categoryID: cat.id)
        relay(from: storeA, into: storeB)

        // A moves X under Y; B (concurrently, unaware) moves Y under X — neither side is
        // cyclic alone, but merging the two parent pointers closes a loop.
        try storeA.addChild(assetID: x.id, toParentID: y.id)
        try storeB.addChild(assetID: y.id, toParentID: x.id)
        settle(storeA, storeB)

        XCTAssertEqual(storeA.assets[x.id]?.parentID, storeB.assets[x.id]?.parentID, "both devices must break the cycle the same way")
        XCTAssertEqual(storeA.assets[y.id]?.parentID, storeB.assets[y.id]?.parentID)
        // And it really is broken: walking parentID from either asset terminates.
        for id in [x.id, y.id] {
            var seen = Set<UUID>()
            var cursor: UUID? = id
            while let cur = cursor {
                XCTAssertFalse(seen.contains(cur), "cycle detected")
                seen.insert(cur)
                cursor = storeA.assets[cur]?.parentID
            }
        }
    }

    // MARK: - Identity preservation and live-mutation survival

    func testObjectIdentityIsPreservedAcrossRelay() throws {
        let cat = try storeA.createCategory(name: "Vehicle")
        let asset = try storeA.createAsset(name: "Car", categoryID: cat.id)
        relay(from: storeA, into: storeB)
        let capturedInB = storeB.assets[asset.id]

        try storeA.updateAsset(id: asset.id, name: "Renamed")
        relay(from: storeA, into: storeB)

        XCTAssertTrue(storeB.assets[asset.id] === capturedInB, "applyInPlace must mutate the existing object, not replace it")
    }

    /// The direct regression test for the wholesale-replace defect `applySnapshot` had before
    /// `applyInPlace` existed: a live in-memory mutation made AFTER a snapshot was captured
    /// must survive being folded into an incoming merge built from that now-stale snapshot.
    func testLiveMutationAfterSnapshotSurvivesIncomingMerge() throws {
        let cat = try storeA.createCategory(name: "Vehicle")
        let asset = try storeA.createAsset(name: "Car", categoryID: cat.id)
        relay(from: storeA, into: storeB)

        let staleSnapshot = storeB.buildSnapshot()
        try storeB.updateAsset(id: asset.id, name: "Edited after snapshot")

        let merged = SnapshotReconciler.merge(storeB.buildSnapshot(), staleSnapshot)
        storeB.applyInPlace(merged)

        XCTAssertEqual(storeB.assets[asset.id]?.name, "Edited after snapshot")
    }

    // MARK: - Idempotence at the store level

    func testSecondRelayRoundWritesNothingNew() throws {
        let cat = try storeA.createCategory(name: "Vehicle")
        _ = try storeA.createAsset(name: "Car", categoryID: cat.id)
        settle(storeA, storeB)

        let beforeA = CanonicalCodec.encode(storeA.buildSnapshot().canonicalized())
        relay(from: storeB, into: storeA)
        let afterA = CanonicalCodec.encode(storeA.buildSnapshot().canonicalized())
        XCTAssertEqual(beforeA, afterA, "relaying an already-converged snapshot must be a no-op")
    }

    // MARK: - Template propagation convergence

    /// The direct regression test for `propagateTemplates`'s deterministic `AssetProperty.id`:
    /// each device appends the same new field to the same asset independently — a realistic
    /// race if the user runs the action on two devices before they next sync — and the merge
    /// must resolve to exactly one property, not a live/shadowed duplicate pair.
    func testIndependentPropagationOnBothDevicesConvergesToOneProperty() throws {
        let cat = try storeA.createCategory(name: "Vehicle")
        let asset = try storeA.createAsset(name: "Car", categoryID: cat.id)
        let vinDef = PropertyDefinition(name: "VIN", type: .basic(.text), isRequired: false)
        try storeA.addTemplateProperty(AssetProperty(definition: vinDef), toCategoryID: cat.id)
        relay(from: storeA, into: storeB)   // both sides now hold the new template

        let summaryA = try storeA.propagateTemplates(forCategoryID: cat.id)
        let summaryB = try storeB.propagateTemplates(forCategoryID: cat.id)
        XCTAssertEqual(summaryA.added, 1)
        XCTAssertEqual(summaryB.added, 1, "device B must actually do the work, or this test proves nothing")

        settle(storeA, storeB)

        for store in [storeA!, storeB!] {
            let merged = try XCTUnwrap(store.assets[asset.id])
            XCTAssertEqual(merged.baseProperties.filter { $0.definition.id == vinDef.id }.count, 1)
        }
    }

    /// Same race for the removal side: both devices independently tombstone the same base
    /// property. The merge must not end up with two records for one definition id either way.
    func testIndependentRemovalOnBothDevicesConvergesToOneTombstone() throws {
        let cat = try storeA.createCategory(name: "Vehicle", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text))),
            AssetProperty(definition: PropertyDefinition(name: "VIN", type: .basic(.text), isRequired: false))
        ])
        let vinDefID = cat.propertyTemplates[1].definition.id
        let vinTemplateID = cat.propertyTemplates[1].id
        let asset = try storeA.createAsset(name: "Car", categoryID: cat.id)
        relay(from: storeA, into: storeB)

        try storeA.removeTemplateProperty(id: vinTemplateID, fromCategoryID: cat.id)
        relay(from: storeA, into: storeB)   // both sides now see the template tombstoned

        try storeA.propagateTemplates(forCategoryID: cat.id)
        try storeB.propagateTemplates(forCategoryID: cat.id)
        settle(storeA, storeB)

        for store in [storeA!, storeB!] {
            let merged = try XCTUnwrap(store.assets[asset.id])
            let matches = merged.baseProperties.filter { $0.definition.id == vinDefID }
            XCTAssertEqual(matches.count, 1)
            XCTAssertTrue(matches[0].isDeleted)
        }
    }

    /// Documents the accepted trade-off of per-property whole-record LWW (`joinAssetProperty`
    /// in `SnapshotReconciler`): a later edit to ANY field of a property — even just its
    /// definition, via propagation — wins the whole record, so an earlier-but-still-live value
    /// edit on the losing side survives here only because it's the side that's later.
    func testLaterValueEditBeatsEarlierPropagatedRename() throws {
        let cat = try storeA.createCategory(name: "Vehicle", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Make", type: .basic(.text)))
        ])
        let makeDefID = cat.propertyTemplates[0].definition.id
        let asset = try storeA.createAsset(name: "Car", categoryID: cat.id)
        relay(from: storeA, into: storeB)

        try storeA.updateTemplateProperty(id: cat.propertyTemplates[0].id, inCategoryID: cat.id, name: "Manufacturer")
        try storeA.propagateTemplates(forCategoryID: cat.id)

        Thread.sleep(forTimeInterval: 1.1)
        try storeB.setPropertyValue(.text("Toyota"), forDefinitionID: makeDefID, onAssetID: asset.id)
        settle(storeA, storeB)

        let merged = try XCTUnwrap(storeA.assets[asset.id])
        let prop = try XCTUnwrap(merged.baseProperties.first { $0.definition.id == makeDefID })
        XCTAssertEqual(prop.value, .text("Toyota"), "the later whole-record edit wins")
        XCTAssertEqual(prop.definition.name, "Make", "...including its definition, which reverts the earlier rename")
    }
}
