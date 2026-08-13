import XCTest
@testable import HandyApp3

/// Pure DTO-level coverage for `SnapshotReconciler` — no `AssetStore`, no disk. Two kinds of
/// tests: algebraic properties (commutative, idempotent, associative, canonical-fixed-point)
/// that must hold for ANY pair of snapshots for the reconciler to converge at all, and targeted
/// scenarios pinning the specific policy decisions (headModifyDate vs. modifiedDate, grow-only
/// combo-list options, absence-never-deletes, cycle breaking, tombstone reaping).
final class SnapshotReconcilerTests: XCTestCase {

    // MARK: - DTO builders

    private func property(
        id: UUID = UUID(), name: String = "Prop", value: StoredValueDTO? = nil,
        sortOrder: Double = 0, modifyDate: Date? = Date(), isDeleted: Bool = false, deletedAt: Date? = nil
    ) -> AssetPropertyDTO {
        AssetPropertyDTO(
            id: id,
            definition: PropertyDefinitionDTO(id: UUID(), name: name,
                                              type: PropertyTypeDTO(kind: .basic, basicType: .text, typeID: nil),
                                              isRequired: false),
            value: value, sortOrder: sortOrder, modifyDate: modifyDate,
            isDeleted: isDeleted, deletedAt: deletedAt
        )
    }

    private func photo(
        id: UUID = UUID(), caption: String = "", addedDate: Date = Date(),
        modifyDate: Date? = Date(), isDeleted: Bool = false, deletedAt: Date? = nil
    ) -> PhotoDTO {
        PhotoDTO(id: id, caption: caption, addedDate: addedDate, fullImage: nil, thumbnail: nil,
                modifyDate: modifyDate, isDeleted: isDeleted, deletedAt: deletedAt)
    }

    private func event(
        id: UUID = UUID(), title: String = "Event", date: Date = Date(),
        modifyDate: Date? = Date(), isDeleted: Bool = false, deletedAt: Date? = nil
    ) -> EventDTO {
        EventDTO(id: id, title: title, date: date, notes: "", recurrence: nil,
                modifyDate: modifyDate, isDeleted: isDeleted, deletedAt: deletedAt)
    }

    private func transaction(
        id: UUID = UUID(), details: String = "Txn", date: Date = Date(),
        modifyDate: Date? = Date(), isDeleted: Bool = false, deletedAt: Date? = nil
    ) -> TransactionDTO {
        TransactionDTO(id: id, details: details, amount: "1", date: date, kind: "expense",
                       payeeContactID: nil, notes: "", recurrence: nil,
                       modifyDate: modifyDate, isDeleted: isDeleted, deletedAt: deletedAt)
    }

    private func category(
        id: UUID = UUID(), name: String = "Category", iconName: String = "tray",
        propertyTemplates: [AssetPropertyDTO] = [], isDeleted: Bool = false, deletedAt: Date? = nil,
        modifyDate: Date? = Date()
    ) -> CategoryDTO {
        CategoryDTO(id: id, name: name, iconName: iconName, propertyTemplates: propertyTemplates,
                   isDeleted: isDeleted, deletedAt: deletedAt, modifyDate: modifyDate)
    }

    private func asset(
        id: UUID = UUID(), name: String = "Asset", categoryID: UUID,
        baseProperties: [AssetPropertyDTO] = [], customProperties: [AssetPropertyDTO] = [],
        photos: [PhotoDTO] = [], events: [EventDTO] = [], transactions: [TransactionDTO] = [],
        parentID: UUID? = nil, isDeleted: Bool = false, deletedAt: Date? = nil,
        createdDate: Date = Date(), modifiedDate: Date = Date(),
        parentageModifyDate: Date? = nil, headModifyDate: Date? = nil, isPurged: Bool? = nil
    ) -> AssetDTO {
        AssetDTO(id: id, name: name, categoryID: categoryID, baseProperties: baseProperties,
                customProperties: customProperties, photos: photos, events: events, transactions: transactions,
                parentID: parentID, isDeleted: isDeleted, deletedAt: deletedAt,
                createdDate: createdDate, modifiedDate: modifiedDate,
                parentageModifyDate: parentageModifyDate ?? createdDate,
                headModifyDate: headModifyDate ?? modifiedDate, isPurged: isPurged)
    }

    private func comboList(
        id: UUID = UUID(), name: String = "List", systemOptions: [String] = [],
        userOptions: [String] = [], isUserExtensible: Bool = true, modifyDate: Date? = Date()
    ) -> ComboListDTO {
        ComboListDTO(id: id, name: name, systemOptions: systemOptions, userOptions: userOptions,
                    isUserExtensible: isUserExtensible, modifyDate: modifyDate)
    }

    private func compositeType(
        id: UUID = UUID(), name: String = "Type", fields: [PropertyDefinitionDTO] = [],
        modifyDate: Date? = Date()
    ) -> CompositeTypeDTO {
        CompositeTypeDTO(id: id, name: name, fields: fields, labelHint: nil, modifyDate: modifyDate)
    }

    private func snapshot(
        compositeTypes: [CompositeTypeDTO] = [], comboLists: [ComboListDTO] = [],
        categories: [CategoryDTO] = [], assets: [AssetDTO] = [], activityLog: [ActivityLogDTO] = []
    ) -> StoreSnapshotDTO {
        StoreSnapshotDTO(schemaVersion: storeSchemaVersion, compositeTypes: compositeTypes,
                        comboLists: comboLists, categories: categories, assets: assets,
                        activityLog: activityLog, backgroundTheme: BackgroundTheme.mist.rawValue)
    }

    private func bytes(_ s: StoreSnapshotDTO) -> Data? { CanonicalCodec.encode(s.canonicalized()) }

    // MARK: - Algebraic properties (seeded random pairs)

    /// Deterministic pseudo-random generator so failures are reproducible without depending on
    /// system randomness.
    private struct LCG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = 6364136223846793005 &* state &+ 1442695040888963407
            return state
        }
        mutating func nextDouble() -> Double { Double(next() % 1000) }
        mutating func nextBool() -> Bool { next() % 2 == 0 }
    }

    /// Builds a base snapshot plus two independently-mutated divergent copies sharing the same
    /// record ids — simulating two devices that started from the same state and each made a
    /// handful of changes before syncing.
    private func makeDivergentPair(seed: UInt64) -> (StoreSnapshotDTO, StoreSnapshotDTO) {
        var rng = LCG(state: seed)
        let catID = UUID()
        let assetIDs = (0..<5).map { _ in UUID() }
        let propIDs = (0..<3).map { _ in UUID() }
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        func mutatedCopy(_ tag: Double) -> StoreSnapshotDTO {
            let cat = category(id: catID, name: "Cat\(Int(rng.nextDouble()))", modifyDate: base.addingTimeInterval(tag + rng.nextDouble()))
            var assets: [AssetDTO] = []
            for (i, aid) in assetIDs.enumerated() {
                let props = propIDs.map {
                    property(id: $0, name: "P\(i)", value: .number(rng.nextDouble()),
                            modifyDate: base.addingTimeInterval(tag + rng.nextDouble()))
                }
                let parent = i > 0 && rng.nextBool() ? assetIDs[i - 1] : nil
                assets.append(asset(
                    id: aid, name: "A\(i)-\(Int(rng.nextDouble()))", categoryID: catID,
                    baseProperties: props, parentID: parent,
                    isDeleted: rng.nextBool() && i == 4,
                    createdDate: base, modifiedDate: base.addingTimeInterval(tag + rng.nextDouble()),
                    parentageModifyDate: base.addingTimeInterval(tag + rng.nextDouble()),
                    headModifyDate: base.addingTimeInterval(tag + rng.nextDouble())
                ))
                if assets[i].isDeleted { assets[i].deletedAt = base.addingTimeInterval(tag) }
            }
            return snapshot(categories: [cat], assets: assets)
        }
        return (mutatedCopy(0), mutatedCopy(100))
    }

    func testMergeIsCommutative() {
        for seed: UInt64 in [1, 2, 3, 42, 999] {
            let (a, b) = makeDivergentPair(seed: seed)
            let ab = SnapshotReconciler.merge(a, b)
            let ba = SnapshotReconciler.merge(b, a)
            XCTAssertEqual(bytes(ab), bytes(ba), "seed \(seed): merge(a,b) must equal merge(b,a)")
        }
    }

    func testMergeIsIdempotent() {
        for seed: UInt64 in [1, 2, 3, 42, 999] {
            let (a, b) = makeDivergentPair(seed: seed)
            let merged = SnapshotReconciler.merge(a, b)
            let again = SnapshotReconciler.merge(merged, b)
            XCTAssertEqual(bytes(merged), bytes(again), "seed \(seed): merge(merge(a,b),b) must equal merge(a,b)")

            let selfMerge = SnapshotReconciler.merge(a, a)
            XCTAssertEqual(bytes(selfMerge), bytes(a.canonicalized()), "seed \(seed): merge(a,a) must equal canonical(a)")
        }
    }

    func testMergeIsAssociative() {
        for seed: UInt64 in [1, 2, 3, 42, 999] {
            var rng = LCG(state: seed &+ 500)
            let (a, b) = makeDivergentPair(seed: seed)
            let (_, c) = makeDivergentPair(seed: seed &+ UInt64(rng.next() % 1000))
            let left = SnapshotReconciler.merge(SnapshotReconciler.merge(a, b), c)
            let right = SnapshotReconciler.merge(a, SnapshotReconciler.merge(b, c))
            XCTAssertEqual(bytes(left), bytes(right), "seed \(seed): merge must be associative")
        }
    }

    func testCanonicalizationIsIdempotent() {
        for seed: UInt64 in [1, 2, 3] {
            let (a, _) = makeDivergentPair(seed: seed)
            let once = a.canonicalized()
            let twice = once.canonicalized()
            XCTAssertEqual(CanonicalCodec.encode(once), CanonicalCodec.encode(twice))
        }
    }

    // MARK: - Head vs. rollup: the delete/rename regression

    /// Direct regression test for the defect whole-record LWW on `modifiedDate` would cause:
    /// device A soft-deletes an asset; device B (unaware, editing something unrelated) bumps
    /// the same asset's `modifiedDate` (a rollup) later than A's delete. The delete must still
    /// win, because `headModifyDate` — not `modifiedDate` — governs the tombstone.
    func testLaterChildEditDoesNotResurrectAnEarlierDelete() {
        let catID = UUID()
        let assetID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        let deleted = asset(id: assetID, name: "X", categoryID: catID,
                            isDeleted: true, deletedAt: t0.addingTimeInterval(10),
                            createdDate: t0, modifiedDate: t0.addingTimeInterval(10),
                            headModifyDate: t0.addingTimeInterval(10))
        // B's edit lands LATER in wall-clock time but never touches the head fields — modifiedDate
        // is newer than A's delete, headModifyDate is not.
        let edited = asset(id: assetID, name: "X", categoryID: catID,
                           isDeleted: false,
                           createdDate: t0, modifiedDate: t0.addingTimeInterval(50),
                           headModifyDate: t0)

        let merged = SnapshotReconciler.joinAsset(deleted, edited)
        XCTAssertTrue(merged.isDeleted, "an unrelated later child/head-adjacent edit must not resurrect an earlier delete")
    }

    /// The inverse: a later rename must win over an earlier, unrelated delete.
    func testLaterRenameWinsOverEarlierDelete() {
        let catID = UUID()
        let assetID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        let deleted = asset(id: assetID, name: "Old", categoryID: catID,
                            isDeleted: true, deletedAt: t0,
                            createdDate: t0, modifiedDate: t0, headModifyDate: t0)
        let renamed = asset(id: assetID, name: "New", categoryID: catID,
                            isDeleted: false,
                            createdDate: t0, modifiedDate: t0.addingTimeInterval(20),
                            headModifyDate: t0.addingTimeInterval(20))

        let merged = SnapshotReconciler.joinAsset(deleted, renamed)
        XCTAssertFalse(merged.isDeleted)
        XCTAssertEqual(merged.name, "New")
    }

    // MARK: - Absence never deletes

    func testRecordPresentOnOneSideOnlyIsKept() {
        let catID = UUID()
        let onlyInA = asset(id: UUID(), name: "OnlyA", categoryID: catID)
        let a = snapshot(categories: [category(id: catID)], assets: [onlyInA])
        let b = snapshot(categories: [category(id: catID)], assets: [])

        let merged = SnapshotReconciler.merge(a, b)
        XCTAssertEqual(merged.assets.count, 1)
        XCTAssertEqual(merged.assets.first?.id, onlyInA.id)
    }

    // MARK: - Combo list: grow-only union

    func testComboListUserOptionsUnionNeverLosesAConcurrentAdd() {
        let listID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let a = comboList(id: listID, name: "List", systemOptions: ["Sys"], userOptions: ["FromA"], modifyDate: t0)
        let b = comboList(id: listID, name: "List", systemOptions: ["Sys"], userOptions: ["FromB"], modifyDate: t0.addingTimeInterval(5))

        let merged = SnapshotReconciler.joinComboList(a, b)
        XCTAssertEqual(Set(merged.userOptions), Set(["FromA", "FromB"]))
        XCTAssertEqual(merged.name, "List")
    }

    func testComboListHeaderFollowsLastWriterWins() {
        let listID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let a = comboList(id: listID, name: "Old Name", modifyDate: t0)
        let b = comboList(id: listID, name: "New Name", modifyDate: t0.addingTimeInterval(10))

        let merged = SnapshotReconciler.joinComboList(a, b)
        XCTAssertEqual(merged.name, "New Name")
    }

    // MARK: - Category template tombstone survives merge (no resurrection from a peer)

    func testRemovedCategoryTemplateStaysRemovedWhenPeerStillHasItLive() {
        let catID = UUID()
        let propID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        // Device A removed the template (tombstoned it) after device B's snapshot was taken.
        let removedTemplate = property(id: propID, name: "Field", modifyDate: t0.addingTimeInterval(10),
                                       isDeleted: true, deletedAt: t0.addingTimeInterval(10))
        let liveTemplate = property(id: propID, name: "Field", modifyDate: t0)

        let a = category(id: catID, propertyTemplates: [removedTemplate], modifyDate: t0.addingTimeInterval(10))
        let b = category(id: catID, propertyTemplates: [liveTemplate], modifyDate: t0)

        let merged = SnapshotReconciler.joinCategory(a, b)
        XCTAssertEqual(merged.propertyTemplates.count, 1)
        XCTAssertEqual(merged.propertyTemplates[0].isDeleted, true, "the newer tombstone must win over the older live copy")
    }

    // MARK: - Hierarchy: cycle breaking

    func testMergeBreaksACycleFormedByCrossingReparents() {
        let catID = UUID()
        let idX = UUID()
        let idY = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        // Device A moved X under Y. Device B (concurrently) moved Y under X. Neither side is
        // cyclic on its own; merging the two parent pointers closes a loop.
        let aSnap = snapshot(categories: [category(id: catID)], assets: [
            asset(id: idX, categoryID: catID, parentID: idY, createdDate: t0, parentageModifyDate: t0.addingTimeInterval(10)),
            asset(id: idY, categoryID: catID, parentID: nil, createdDate: t0, parentageModifyDate: t0),
        ])
        let bSnap = snapshot(categories: [category(id: catID)], assets: [
            asset(id: idX, categoryID: catID, parentID: nil, createdDate: t0, parentageModifyDate: t0),
            asset(id: idY, categoryID: catID, parentID: idX, createdDate: t0, parentageModifyDate: t0.addingTimeInterval(20)),
        ])

        let merged = SnapshotReconciler.merge(aSnap, bSnap)
        // Whichever side's parent pointer "won" the per-asset join, the result must not
        // contain a cycle — walking parentID from any asset must terminate.
        let byID = Dictionary(uniqueKeysWithValues: merged.assets.map { ($0.id, $0) })
        for start in merged.assets {
            var seen = Set<UUID>()
            var cursor: UUID? = start.id
            var hops = 0
            while let id = cursor {
                XCTAssertFalse(seen.contains(id), "cycle detected starting from \(start.id)")
                seen.insert(id)
                cursor = byID[id]?.parentID
                hops += 1
                XCTAssertLessThan(hops, merged.assets.count + 1, "walk did not terminate")
            }
        }
    }

    func testNormalizeHierarchyIsAFixedPoint() {
        let catID = UUID()
        let idX = UUID(), idY = UUID(), idZ = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let cyclic = [
            asset(id: idX, categoryID: catID, parentID: idY, createdDate: t0, parentageModifyDate: t0.addingTimeInterval(1)),
            asset(id: idY, categoryID: catID, parentID: idZ, createdDate: t0, parentageModifyDate: t0.addingTimeInterval(2)),
            asset(id: idZ, categoryID: catID, parentID: idX, createdDate: t0, parentageModifyDate: t0.addingTimeInterval(3)),
        ]
        let once = SnapshotReconciler.normalizeHierarchy(cyclic)
        let twice = SnapshotReconciler.normalizeHierarchy(once)
        let s1 = snapshot(assets: once).canonicalized()
        let s2 = snapshot(assets: twice).canonicalized()
        XCTAssertEqual(CanonicalCodec.encode(s1), CanonicalCodec.encode(s2))
    }

    func testDanglingParentReferenceIsCleared() {
        let catID = UUID()
        let missingParent = UUID()
        let a = asset(id: UUID(), categoryID: catID, parentID: missingParent)
        let normalized = SnapshotReconciler.normalizeHierarchy([a])
        XCTAssertNil(normalized[0].parentID)
    }

    // MARK: - Tombstone reaping

    func testReapStripsAssetTombstonesOlderThanCutoffInsteadOfRemovingThem() {
        let catID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let cutoff = t0.addingTimeInterval(100)
        let expired = asset(id: UUID(), categoryID: catID, isDeleted: true, deletedAt: t0)
        let fresh = asset(id: UUID(), categoryID: catID, isDeleted: true, deletedAt: t0.addingTimeInterval(200))
        let snap = snapshot(categories: [category(id: catID)], assets: [expired, fresh])

        let reaped = SnapshotReconciler.reap(snap, cutoff: cutoff)
        XCTAssertEqual(Set(reaped.assets.map(\.id)), Set([expired.id, fresh.id]),
                       "reap must never remove an asset record — that's what let a peer resurrect it")
        XCTAssertEqual(reaped.assets.first { $0.id == expired.id }?.isPurged, true)
        XCTAssertNotEqual(reaped.assets.first { $0.id == fresh.id }?.isPurged, true)
    }

    func testReapNeverExpiresATombstoneWithNoDeletedAt() {
        let catID = UUID()
        var neverExpiring = asset(id: UUID(), categoryID: catID, isDeleted: true)
        neverExpiring.deletedAt = nil
        let snap = snapshot(categories: [category(id: catID)], assets: [neverExpiring])
        let reaped = SnapshotReconciler.reap(snap, cutoff: .distantFuture)
        XCTAssertEqual(reaped.assets.count, 1)
        XCTAssertNotEqual(reaped.assets.first?.isPurged, true)
    }

    func testReapPurgesParentButLeavesChildTombstonePointingAtTheSurvivingParentRecord() {
        // Both records survive reap now, so a child's parentID pointing at a purged parent is
        // no longer dangling — it resolves to the parent's (now-minimal) husk. Detaching a
        // LIVE child from a purged parent is `applyInPlace`'s live/deleted-boundary repair's
        // job, not reap's — this case has both sides still tombstoned, so nothing detaches.
        let catID = UUID()
        let parentID = UUID()
        let childID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let cutoff = t0.addingTimeInterval(100)
        let parent = asset(id: parentID, categoryID: catID, isDeleted: true, deletedAt: t0, createdDate: t0)
        let child = asset(id: childID, categoryID: catID, parentID: parentID,
                          isDeleted: true, deletedAt: t0.addingTimeInterval(200), createdDate: t0)
        let snap = snapshot(categories: [category(id: catID)], assets: [parent, child])

        let reaped = SnapshotReconciler.reap(snap, cutoff: cutoff)
        XCTAssertEqual(Set(reaped.assets.map(\.id)), Set([parentID, childID]))
        let reapedParent = reaped.assets.first { $0.id == parentID }
        XCTAssertEqual(reapedParent?.isPurged, true)
        XCTAssertNil(reapedParent?.parentID)
        let reapedChild = reaped.assets.first { $0.id == childID }
        XCTAssertNotEqual(reapedChild?.isPurged, true, "the child's own tombstone hasn't expired yet")
        XCTAssertEqual(reapedChild?.parentID, parentID)
    }

    func testReapKeepsCategoryStillReferencedByASurvivingAssetRegardlessOfAge() {
        let catID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let oldDeletedCategory = category(id: catID, isDeleted: true, deletedAt: t0)
        let survivingAsset = asset(id: UUID(), categoryID: catID, isDeleted: false)
        let snap = snapshot(categories: [oldDeletedCategory], assets: [survivingAsset])

        let reaped = SnapshotReconciler.reap(snap, cutoff: .distantFuture)
        XCTAssertEqual(reaped.categories.count, 1, "a category still referenced by a live asset must never be reaped")
    }

    func testReapDropsAgedCategoryReferencedOnlyByANowPurgedAsset() {
        // A purged asset no longer counts as a "surviving" reference — mirrors
        // `AssetStore.purgeHardDeleted`'s `referencedCategoryIDs` change. Both the category's
        // and the asset's own tombstones must be past cutoff for this to isolate the guard:
        // an unexpired category would survive on its own age regardless of references.
        let catID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let cutoff = t0.addingTimeInterval(100)
        let agedCategory = category(id: catID, isDeleted: true, deletedAt: t0)
        let purgedAsset = asset(id: UUID(), categoryID: catID, isDeleted: true, deletedAt: t0)
        let snap = snapshot(categories: [agedCategory], assets: [purgedAsset])

        let reaped = SnapshotReconciler.reap(snap, cutoff: cutoff)
        XCTAssertEqual(reaped.categories.count, 0,
                       "an aged category referenced only by a now-purged asset must not be kept alive")
    }

    // MARK: - Purge (isPurged)

    func testStripPurgedIsAFixedPoint() {
        let catID = UUID()
        let full = asset(id: UUID(), categoryID: catID,
                         baseProperties: [property()], customProperties: [property()],
                         photos: [photo()], events: [event()], transactions: [transaction()],
                         parentID: UUID(), isDeleted: true, deletedAt: Date())
        let strippedOnce = SnapshotReconciler.stripPurged(full)
        let strippedTwice = SnapshotReconciler.stripPurged(strippedOnce)
        XCTAssertEqual(bytes(snapshot(assets: [strippedOnce])), bytes(snapshot(assets: [strippedTwice])),
                       "stripping an already-stripped asset must change nothing")
        XCTAssertTrue(strippedOnce.baseProperties.isEmpty)
        XCTAssertTrue(strippedOnce.customProperties.isEmpty)
        XCTAssertTrue(strippedOnce.photos.isEmpty)
        XCTAssertTrue(strippedOnce.events.isEmpty)
        XCTAssertTrue(strippedOnce.transactions.isEmpty)
        XCTAssertNil(strippedOnce.parentID)
        XCTAssertEqual(strippedOnce.id, full.id)
        XCTAssertEqual(strippedOnce.name, full.name)
        XCTAssertEqual(strippedOnce.categoryID, full.categoryID)
    }

    func testJoinAssetPurgeIsMonotoneAndCommutative() {
        let catID = UUID()
        let id = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let purged = asset(id: id, categoryID: catID, isDeleted: true, deletedAt: t0,
                           headModifyDate: t0, isPurged: true)
        // The stale peer's copy is still full and even carries a LATER headModifyDate — purge
        // must win regardless of which side's timestamp is newer, since it's OR'd, not LWW'd.
        let stillFull = asset(id: id, categoryID: catID, baseProperties: [property()], photos: [photo()],
                              isDeleted: true, deletedAt: t0, headModifyDate: t0.addingTimeInterval(1000))

        let ab = SnapshotReconciler.joinAsset(purged, stillFull)
        let ba = SnapshotReconciler.joinAsset(stillFull, purged)
        for merged in [ab, ba] {
            XCTAssertEqual(merged.isPurged, true)
            XCTAssertTrue(merged.baseProperties.isEmpty)
            XCTAssertTrue(merged.photos.isEmpty)
        }
    }

    func testMergeWithStalePeersFullCopyDoesNotResurrectAPurgedAsset() {
        // This is the scenario the whole rework exists to fix: device A purges an asset,
        // device B is offline and still holds the full record. A stale peer's still-full copy
        // unioning back in must not bring the payload back.
        let catID = UUID()
        let id = UUID()
        let purgedSnap = snapshot(categories: [category(id: catID)],
                                  assets: [asset(id: id, categoryID: catID, isDeleted: true, isPurged: true)])
        let stalePeerSnap = snapshot(categories: [category(id: catID)],
                                     assets: [asset(id: id, categoryID: catID,
                                                    baseProperties: [property()], photos: [photo()],
                                                    events: [event()], isDeleted: true)])

        let merged = SnapshotReconciler.merge(purgedSnap, stalePeerSnap)
        let mergedAsset = merged.assets.first { $0.id == id }
        XCTAssertEqual(mergedAsset?.isPurged, true)
        XCTAssertEqual(mergedAsset?.baseProperties.count, 0)
        XCTAssertEqual(mergedAsset?.photos.count, 0)
        XCTAssertEqual(mergedAsset?.events.count, 0)

        // A second round trip (the stale peer applies the merge result and syncs again) must
        // not un-strip it either — idempotence is what makes this converge instead of flap.
        let mergedAgain = SnapshotReconciler.merge(merged, stalePeerSnap)
        XCTAssertEqual(mergedAgain.assets.first { $0.id == id }?.baseProperties.count, 0)
    }

    // MARK: - Composite type: whole-record LWW, fields never merged element-wise

    func testCompositeTypeFieldsAreWholeRecordNotElementMerged() {
        let typeID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let fieldA = PropertyDefinitionDTO(id: UUID(), name: "Width",
                                           type: PropertyTypeDTO(kind: .basic, basicType: .number, typeID: nil), isRequired: true)
        let fieldB = PropertyDefinitionDTO(id: UUID(), name: "Height",
                                           type: PropertyTypeDTO(kind: .basic, basicType: .number, typeID: nil), isRequired: true)
        let a = compositeType(id: typeID, fields: [fieldA], modifyDate: t0)
        let b = compositeType(id: typeID, fields: [fieldB], modifyDate: t0.addingTimeInterval(10))

        let merged = SnapshotReconciler.joinCompositeType(a, b)
        XCTAssertEqual(merged.fields.map(\.name), ["Height"], "the winner's whole field set replaces the loser's, never a union")
    }
}
