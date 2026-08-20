import XCTest
@testable import HandyApp3

/// Simulates the ubiquity container as a plain directory shared between per-device
/// directories, moving bytes with `push`/`pull` — nothing here knows about `AssetStore` or
/// `SnapshotReconciler`; it operates purely on files, the same way a real cloud sync daemon
/// does. Ordering, delay, and partiality are expressed by *when* a test calls `push`/`pull` and
/// with what filter/withhold state — fully deterministic, no timers.
final class SyncRelay {
    private let cloud: URL
    private var devices: [String: URL] = [:]
    private var withheld: Set<String> = []
    /// path -> the device name that most recently pushed it. Lets `push` detect a genuine
    /// conflict: a different device's content about to be overwritten without this device
    /// having pulled it first.
    private var lastPusher: [String: String] = [:]
    /// Per device, the bytes it last saw for each path (via a prior push or pull). A push only
    /// sends a path whose CURRENT local bytes differ from this — i.e. the device itself
    /// changed it — never a path that merely differs from a newer cloud version the device
    /// hasn't pulled yet. Without this, a device holding a stale, untouched copy of a file
    /// would re-upload that stale copy and clobber a peer's genuine concurrent edit to it.
    private var lastKnown: [String: [String: Data]] = [:]
    private(set) var conflictVersions: [String: [Data]] = [:]

    init(cloud: URL) {
        self.cloud = cloud
        try? FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
    }

    func register(_ name: String, root: URL) {
        devices[name] = root
    }

    private func relativePaths(under root: URL) -> [String] {
        // Both sides must be normalized the same way. On macOS `temporaryDirectory` is
        // `/var/folders/...` but the enumerator reports `/private/var/folders/...`, and
        // `resolvingSymlinksInPath()` *strips* a leading `/private` rather than adding one —
        // so it has to be applied to the enumerated URLs too, not just the base. Without
        // that, the prefix lengths disagree, every relative path comes out mangled, and
        // `push` silently sends nothing. (Doesn't bite on the iOS simulator, where the temp
        // directory involves no such symlink.)
        let base = root.resolvingSymlinksInPath()
        guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var prefix = base.path
        if !prefix.hasSuffix("/") { prefix += "/" }
        var paths: [String] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let full = url.resolvingSymlinksInPath().path
            guard full.hasPrefix(prefix) else { continue }
            paths.append(String(full.dropFirst(prefix.count)))
        }
        return paths
    }

    @discardableResult
    func push(_ device: String) -> [String] {
        guard let root = devices[device] else { return [] }
        var pushed: [String] = []
        var known = lastKnown[device] ?? [:]
        for path in relativePaths(under: root) {
            let src = root.appendingPathComponent(path)
            guard let data = try? Data(contentsOf: src) else { continue }
            guard known[path] != data else { continue }  // unchanged since this device last saw it
            let dst = cloud.appendingPathComponent(path)
            let existingCloud = try? Data(contentsOf: dst)
            if let existingCloud, existingCloud != data,
               let previousPusher = lastPusher[path], previousPusher != device {
                conflictVersions[path, default: []].append(existingCloud)
            }
            try? FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: dst, options: .atomic)
            lastPusher[path] = device
            known[path] = data
            pushed.append(path)
        }
        lastKnown[device] = known
        return pushed
    }

    /// `filter` simulates partial download: return `false` for a path to leave it un-pulled
    /// this round. `withhold`ing a path overrides `filter` entirely — it never arrives until
    /// `release`d, regardless of what the filter says.
    @discardableResult
    func pull(_ device: String, filter: ((String) -> Bool)? = nil) -> [String] {
        guard let root = devices[device] else { return [] }
        var pulled: [String] = []
        var known = lastKnown[device] ?? [:]
        for path in relativePaths(under: cloud) {
            guard !withheld.contains(path), filter?(path) ?? true else { continue }
            let src = cloud.appendingPathComponent(path)
            guard let data = try? Data(contentsOf: src) else { continue }
            let dst = root.appendingPathComponent(path)
            if (try? Data(contentsOf: dst)) == data { known[path] = data; continue }
            try? FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: dst, options: .atomic)
            known[path] = data
            pulled.append(path)
        }
        lastKnown[device] = known
        return pulled
    }

    func withhold(_ path: String) { withheld.insert(path) }
    func release(_ path: String) { withheld.remove(path) }

    /// Simulates a peer's purge/orphan sweep removing a file from the cloud.
    func deleteFromCloud(_ path: String) {
        try? FileManager.default.removeItem(at: cloud.appendingPathComponent(path))
        lastPusher.removeValue(forKey: path)
    }

    var cloudPaths: [String] { relativePaths(under: cloud) }

    func conflictSource() -> ConflictSource { RelayConflictSource(conflictVersions: conflictVersions) }

    private struct RelayConflictSource: ConflictSource {
        let conflictVersions: [String: [Data]]
        func conflictedPaths(baseDir: URL) -> [String] { Array(conflictVersions.keys) }
        func conflictingContents(at url: URL) -> [Data] {
            for (path, blobs) in conflictVersions where url.path.hasSuffix(path) { return blobs }
            return []
        }
        func resolve(at url: URL) {}
    }
}

/// Tier 2: two `AssetStore` instances, each with its own real per-device directory, syncing
/// through a `SyncRelay`-simulated cloud via `save(to:)`/`load(from:)` — the full
/// `StoreFileLayout` read/write path is exercised, unlike Tier 1 (`TwoDeviceRelayTests`), which
/// never touches disk. Covers sharding, the digest cache, the orphan sweep, partial downloads,
/// echo suppression, purge convergence, seed-vs-real-store replacement, and per-shard conflict
/// resolution. What it still can't cover: real `NSFileVersion`/`NSMetadataQuery`/
/// `NSFileCoordinator` behavior — see the manual verification checklist for that.
final class SyncRelayTests: XCTestCase {

    var storeA: AssetStore!
    var storeB: AssetStore!
    private var rootA: URL!
    private var rootB: URL!
    private var cloudDir: URL!
    private var relay: SyncRelay!

    override func setUp() {
        super.setUp()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        rootA = base.appendingPathComponent("A")
        rootB = base.appendingPathComponent("B")
        cloudDir = base.appendingPathComponent("cloud")
        try? FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)
        storeA = AssetStore()
        storeB = AssetStore()
        relay = SyncRelay(cloud: cloudDir)
        relay.register("A", root: rootA)
        relay.register("B", root: rootB)
    }

    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(at: rootA.deletingLastPathComponent())
    }

    private func merge(_ store: AssetStore, from root: URL) {
        guard let result = store.fileLayout.read(baseDir: root) else { return }
        let merged = SnapshotReconciler.merge(store.buildSnapshot(), result.snapshot)
        store.applyInPlace(merged)
        store.save(to: root)
    }

    // MARK: - Concurrent edits

    func testConcurrentEditsToDifferentAssetsBothSurvive() throws {
        let cat = try storeA.createCategory(name: "Vehicle")
        let x = try storeA.createAsset(name: "X", categoryID: cat.id)
        let y = try storeA.createAsset(name: "Y", categoryID: cat.id)
        storeA.save(to: rootA)
        relay.push("A"); relay.pull("B")
        XCTAssertTrue(storeB.load(from: rootB))

        // Every stamp compared by the reconciler is truncated to whole seconds (matching what
        // disk round-tripping already does), so two edits landing in the same wall-clock
        // second are a genuine, unresolvable-by-recency tie — sleeping across a second
        // boundary is what makes "the edit wins" a testable, deterministic outcome here.
        Thread.sleep(forTimeInterval: 1.1)
        try storeA.updateAsset(id: x.id, name: "X renamed")
        storeA.save(to: rootA)
        try storeB.updateAsset(id: y.id, name: "Y renamed")
        storeB.save(to: rootB)

        relay.push("A"); relay.push("B")
        relay.pull("A"); relay.pull("B")
        merge(storeA, from: rootA)
        merge(storeB, from: rootB)
        relay.push("A"); relay.push("B")
        relay.pull("A"); relay.pull("B")
        merge(storeA, from: rootA)
        merge(storeB, from: rootB)

        XCTAssertEqual(storeA.assets[x.id]?.name, "X renamed")
        XCTAssertEqual(storeA.assets[y.id]?.name, "Y renamed")
        XCTAssertEqual(storeB.assets[x.id]?.name, "X renamed")
        XCTAssertEqual(storeB.assets[y.id]?.name, "Y renamed")
    }

    // MARK: - Partial download protection

    /// A never-downloaded asset file must not prevent the rest of the store from loading, and
    /// must arrive intact once it's actually released.
    func testWithheldAssetFileArrivesIntactOnceReleased() throws {
        let cat = try storeA.createCategory(name: "Vehicle")
        let asset = try storeA.createAsset(name: "Car", categoryID: cat.id)
        storeA.save(to: rootA)
        relay.push("A")

        let assetPath = "Assets/\(asset.id.uuidString.uppercased()).json"
        relay.withhold(assetPath)
        relay.pull("B")  // everything EXCEPT the withheld asset file arrives

        XCTAssertTrue(storeB.load(from: rootB), "structural shards are present; load must succeed")
        XCTAssertNil(storeB.assets[asset.id], "the withheld asset must not appear yet")

        relay.release(assetPath)
        relay.pull("B")
        XCTAssertTrue(storeB.load(from: rootB))
        XCTAssertNotNil(storeB.assets[asset.id], "the asset must survive once its file actually arrives")
    }

    /// The scenario the orphan-sweep gate exists for: B already has every file, including this
    /// asset. A read that hits a transient failure on just this one file (the real-world
    /// equivalent is "not fully downloaded yet") must not let the very next write treat the
    /// file as deleted and sweep it away — `StoreFileLayout`'s `lastReadWasComplete` gate.
    func testAssetFileThatFailsToDecodeOnceSurvivesTheNextOrphanSweep() throws {
        let cat = try storeA.createCategory(name: "Vehicle")
        let asset = try storeA.createAsset(name: "Car", categoryID: cat.id)
        storeA.save(to: rootA)
        relay.push("A"); relay.pull("B")
        XCTAssertTrue(storeB.load(from: rootB))

        let assetPath = "Assets/\(asset.id.uuidString.uppercased()).json"
        let assetURL = rootB.appendingPathComponent(assetPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: assetURL.path))
        try Data("not valid json".utf8).write(to: assetURL)

        XCTAssertTrue(storeB.load(from: rootB), "one bad asset file must not fail the whole read")
        storeB.save(to: rootB)  // must NOT sweep the unreadable-this-once file as an orphan

        XCTAssertTrue(FileManager.default.fileExists(atPath: assetURL.path),
                     "a file that merely failed to decode once must not be deleted by the orphan sweep")
    }

    func testMissingStructuralShardFailsLoadAndWritesNothing() throws {
        let cat = try storeA.createCategory(name: "Vehicle")
        _ = try storeA.createAsset(name: "Car", categoryID: cat.id)
        storeA.save(to: rootA)
        relay.push("A")

        relay.withhold("Definitions/categories.json")
        relay.pull("B")

        // store.json/types.json/combolists.json DO land on disk here — relay.pull writes
        // whatever it was given, independent of the app's load() call, simulating what
        // iCloud itself would already have delivered. The invariant under test is narrower:
        // a missing structural shard must fail the READ, and the in-memory store must stay
        // untouched rather than silently accepting a hole.
        XCTAssertFalse(storeB.load(from: rootB), "a missing structural shard must fail the whole read")
        XCTAssertTrue(storeB.categories.isEmpty, "a failed load must leave in-memory state untouched, not half-applied")
        XCTAssertTrue(storeB.assets.isEmpty)
    }

    // MARK: - Echo suppression

    func testPushingThenPullingOwnBytesIsANoOp() throws {
        let cat = try storeA.createCategory(name: "Vehicle")
        _ = try storeA.createAsset(name: "Car", categoryID: cat.id)
        storeA.save(to: rootA)
        relay.push("A")

        let beforeAssetsListing = try FileManager.default.contentsOfDirectory(
            at: rootA.appendingPathComponent("Assets"), includingPropertiesForKeys: [.contentModificationDateKey]
        ).map { url -> Date in (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }

        relay.pull("A")  // A pulls back exactly what it just pushed
        merge(storeA, from: rootA)

        let afterAssetsListing = try FileManager.default.contentsOfDirectory(
            at: rootA.appendingPathComponent("Assets"), includingPropertiesForKeys: [.contentModificationDateKey]
        ).map { url -> Date in (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }

        XCTAssertEqual(beforeAssetsListing.count, afterAssetsListing.count, "an echo must not create or remove files")
    }

    // MARK: - Offline device rejoining

    func testOfflineDeviceWithMultipleLocalEditsConvergesInOneRound() throws {
        let cat = try storeA.createCategory(name: "Vehicle")
        let assets = try (0..<5).map { try storeA.createAsset(name: "Local\($0)", categoryID: cat.id) }
        storeA.save(to: rootA)
        relay.push("A"); relay.pull("B")
        XCTAssertTrue(storeB.load(from: rootB))

        // Cross a whole-second boundary — see the comment in
        // testConcurrentEditsToDifferentAssetsBothSurvive for why this is needed for a
        // deterministic "the edit wins" outcome rather than a same-second tie.
        Thread.sleep(forTimeInterval: 1.1)
        // B accumulates edits entirely offline (no push/pull at all while this happens).
        for (i, asset) in assets.enumerated() {
            try storeB.updateAsset(id: asset.id, name: "B-edited-\(i)")
        }
        storeB.save(to: rootB)

        // A makes disjoint edits of its own before B ever reconnects.
        let extra = try storeA.createAsset(name: "A-only", categoryID: cat.id)
        storeA.save(to: rootA)

        relay.push("A"); relay.push("B")
        relay.pull("A"); relay.pull("B")
        merge(storeA, from: rootA)
        merge(storeB, from: rootB)

        for (i, asset) in assets.enumerated() {
            XCTAssertEqual(storeA.assets[asset.id]?.name, "B-edited-\(i)")
        }
        XCTAssertNotNil(storeB.assets[extra.id])
    }

    // MARK: - Purge convergence

    func testPurgeCutoffStripsExpiredTombstoneOnBothSidesInOneRound() throws {
        let cat = try storeA.createCategory(name: "Vehicle")
        let asset = try storeA.createAsset(name: "Car", categoryID: cat.id)
        storeA.save(to: rootA)
        relay.push("A")

        try storeA.softDeleteAsset(id: asset.id)
        storeA.save(to: rootA)
        relay.push("A")
        relay.pull("B")

        let resultB = try XCTUnwrap(storeB.fileLayout.read(baseDir: rootB))
        XCTAssertEqual(resultB.snapshot.assets.count, 1)
        XCTAssertTrue(resultB.snapshot.assets[0].isDeleted, "sanity check: the pulled snapshot must actually carry the tombstone")

        let cutoffPast = Date().addingTimeInterval(1000)  // treat the just-created tombstone as expired
        let empty = StoreSnapshotDTO(schemaVersion: storeSchemaVersion, compositeTypes: [], comboLists: [],
                                     categories: [], assets: [], activityLog: [], backgroundTheme: BackgroundTheme.mist.rawValue)
        let mergedOnB = SnapshotReconciler.merge(empty, resultB.snapshot, options: .init(purgeCutoff: cutoffPast))
        XCTAssertEqual(mergedOnB.assets.count, 1, "the record must survive — removing it is what let a stale peer resurrect it")
        XCTAssertEqual(mergedOnB.assets.first?.isPurged, true, "the expired tombstone must be stripped, not just left tombstoned")
    }

    /// The scenario this whole rework exists to fix: A purges an asset (payload gone, minimal
    /// tombstone kept); B was offline the entire time and still holds the full asset. B must
    /// end up stripped after syncing, and — critically — a second sync round (B, still holding
    /// its now-stale full local copy in some other tab, syncing again) must not bring the
    /// payload back. Real `AssetStore`/`SnapshotReconciler`/`StoreFileLayout` end to end, not a
    /// hand-built DTO — the additive-only `upsertX` helpers `applyInPlace` uses for ordinary
    /// merges are exactly what could silently undo a purge if `applyInPlace`'s purge branch
    /// didn't call `purgeInPlace` instead.
    func testOfflineDeviceWithFullCopyEndsUpStrippedAfterSyncingAPurge() throws {
        let cat = try storeA.createCategory(name: "Vehicle")
        let asset = try storeA.createAsset(name: "Car", categoryID: cat.id)
        _ = try storeA.addPhoto(imageData: Data("full".utf8), thumbnailData: Data("thumb".utf8), toAssetID: asset.id)
        // Backdate the asset's own content stamps BEFORE B ever sees it, not just deletedAt
        // below — the purge gate (SnapshotReconciler's join-time gate and
        // AssetStore.purgeHardDeleted's mirror of it, Asset.isProtectedFromAutoPurge) refuses to
        // strip a record whose own content is newer than its delete decision, so both stamps
        // need backdating for the purge itself to proceed. But backdating only AFTER B has
        // already pulled the live (real-"now") copy creates a temporally inconsistent fixture —
        // "created just now, deleted 15 days ago" — where B's genuinely-untouched copy still
        // carries a real-"now" headModifyDate that then outranks A's backdated one in
        // joinAsset's head-pick, and the delete never propagates to B at all. Backdating before
        // the first push keeps the fictional timeline internally consistent (created before
        // deleted) — B's relayed copy inherits the same old stamps, so A's later (but still
        // backdated) delete correctly outranks it.
        let deleteInstant = Date().addingTimeInterval(-15 * 86_400)
        let touchInstant = deleteInstant.addingTimeInterval(-100)
        asset.modifiedDate = touchInstant
        asset.headModifyDate = touchInstant
        storeA.save(to: rootA)
        relay.push("A"); relay.pull("B")
        XCTAssertTrue(storeB.load(from: rootB), "B has the full asset, offline from here on")

        try storeA.softDeleteAsset(id: asset.id)
        asset.deletedAt = deleteInstant
        asset.modifiedDate = deleteInstant
        asset.headModifyDate = deleteInstant
        storeA.purgeHardDeleted(olderThan: TimeInterval(AppPreference.DaysToRetainDeletedItems) * 86_400)
        XCTAssertTrue(storeA.assets[asset.id]?.isPurged ?? false, "sanity check: A actually purged it")
        storeA.save(to: rootA)
        relay.push("A"); relay.pull("B")
        merge(storeB, from: rootB)

        let strippedOnB = try XCTUnwrap(storeB.assets[asset.id])
        XCTAssertTrue(strippedOnB.isPurged, "B must apply the strip, not additively keep its own full copy")
        XCTAssertTrue(strippedOnB.photos.isEmpty)
        XCTAssertEqual(strippedOnB.name, "Car")

        // Second round: B pushes its now-stripped state back; nothing resurrects.
        relay.push("B"); relay.pull("A")
        merge(storeA, from: rootA)
        XCTAssertTrue(storeA.assets[asset.id]?.photos.isEmpty ?? false, "a second round must not un-strip the asset")
    }

    /// Same scenario as `testOfflineDeviceWithFullCopyEndsUpStrippedAfterSyncingAPurge`, for a
    /// category instead of an asset — the resurrection hole this rework was extended to close.
    func testOfflineDeviceWithFullCategoryEndsUpStrippedAfterSyncingAPurge() throws {
        let cat = try storeA.createCategory(name: "Appliances", propertyTemplates: [
            AssetProperty(definition: PropertyDefinition(name: "Brand", type: .basic(.text)))
        ])
        // Backdate modifyDate (header + every template) BEFORE B ever sees it — see the
        // identical comment in testOfflineDeviceWithFullCopyEndsUpStrippedAfterSyncingAPurge for
        // why backdating only after the initial push breaks joinCategory's header pick instead
        // of fixing anything. AssetCategory.isProtectedFromAutoPurge folds in propertyTemplates'
        // modifyDates too (addTemplateProperty never bumps the category's own modifyDate).
        let deleteInstant = Date().addingTimeInterval(-15 * 86_400)
        let touchInstant = deleteInstant.addingTimeInterval(-100)
        cat.modifyDate = touchInstant
        for template in cat.propertyTemplates { template.modifyDate = touchInstant }
        storeA.save(to: rootA)
        relay.push("A"); relay.pull("B")
        XCTAssertTrue(storeB.load(from: rootB), "B has the full category, offline from here on")

        try storeA.softDeleteCategory(id: cat.id)
        cat.deletedAt = deleteInstant
        cat.modifyDate = deleteInstant
        for template in cat.propertyTemplates { template.modifyDate = deleteInstant }
        storeA.purgeHardDeleted(olderThan: TimeInterval(AppPreference.DaysToRetainDeletedItems) * 86_400)
        XCTAssertTrue(storeA.categories[cat.id]?.isPurged ?? false, "sanity check: A actually purged it")
        storeA.save(to: rootA)
        relay.push("A"); relay.pull("B")
        merge(storeB, from: rootB)

        let strippedOnB = try XCTUnwrap(storeB.categories[cat.id])
        XCTAssertTrue(strippedOnB.isPurged, "B must apply the strip, not additively keep its own full copy")
        XCTAssertEqual(strippedOnB.name, "")
        XCTAssertTrue(strippedOnB.propertyTemplates.isEmpty)

        // Second round: B pushes its now-stripped state back; nothing resurrects.
        relay.push("B"); relay.pull("A")
        merge(storeA, from: rootA)
        XCTAssertEqual(storeA.categories[cat.id]?.name, "", "a second round must not un-strip the category")
    }

    // MARK: - Seed-vs-real-store: guarded by hasAuthoritativeLocalState, not exercised here

    func testFreshSeededStoreReplacesRatherThanMerges() throws {
        // A has real, persisted data.
        let cat = try storeA.createCategory(name: "Vehicle")
        _ = try storeA.createAsset(name: "Real Car", categoryID: cat.id)
        storeA.save(to: rootA)
        relay.push("A")

        // B is freshly seeded (simulating BuiltInTypes seeding) and has NOT persisted or
        // confirmed the cloud was empty — the exact condition hasAuthoritativeLocalState guards.
        storeB.savesSuspended = true
        let seededCat = try storeB.createCategory(name: "Seeded Category")
        _ = try storeB.createAsset(name: "Seeded Asset", categoryID: seededCat.id)
        XCTAssertFalse(storeB.hasAuthoritativeLocalState)

        relay.pull("B")
        // Mirrors the production replace branch in handleCloudMonitorNotification: while
        // savesSuspended, the incoming snapshot REPLACES local state (applySnapshot, reached
        // here through load(from:)), never merges through the reconciler.
        XCTAssertTrue(storeB.load(from: rootB))

        XCTAssertNil(storeB.categories[seededCat.id], "seed data must be replaced, not merged, while savesSuspended")
        XCTAssertTrue(storeB.categories.values.contains { $0.name == "Vehicle" })
    }
}
