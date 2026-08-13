import Foundation

/// Pure, DTO-level merge for cross-device convergence. Operates only on Codable DTOs — never
/// live `@Observable` model objects — so it is directly unit- and property-testable without any
/// store or file-system machinery. `AssetStore.applyInPlace(_:)` is what turns a merge result
/// into an in-place update of the live store; this type only computes what the merged content
/// should be.
///
/// The governing invariant, load-bearing everywhere below: **absence never deletes**. A record
/// present on only one side of a merge is kept — a missing `Assets/<uuid>.json` is
/// indistinguishable from one that hasn't downloaded yet (see `StoreFileLayout.ReadResult`).
/// Only an explicit tombstone (`isDeleted`/`deletedAt`) removes a record, and even that only via
/// `reap`, never via ordinary joining.
enum SnapshotReconciler {

    struct Options {
        /// Tombstones with `deletedAt` older than this are dropped from the merged output.
        /// Both sides of a merge compute the same drop from the same content, so purge
        /// converges in one round instead of oscillating between devices that purge at
        /// different times. `.distantPast` (the default) never drops anything.
        var purgeCutoff: Date = .distantPast
    }

    // MARK: - The join primitive

    /// Winner and loser of two candidates for the same record, by a total order: higher `stamp`
    /// wins; on a tie, the lexicographically greater canonical encoding wins. A total order
    /// makes this idempotent, commutative, and associative — the property every join below
    /// relies on for convergence regardless of merge order.
    ///
    /// Stamps are truncated to whole seconds before comparing — the same truncation
    /// `CanonicalCodec`'s `.iso8601` strategy applies on every disk round trip. Without this,
    /// one side's timestamp fresh from live memory (full sub-second precision) and the other's
    /// decoded from disk (whole seconds only) compare inconsistently: a merge one call after a
    /// disk round trip and a merge two calls after can disagree about which side is newer for
    /// the exact same pair of edits, and — worse — an OLDER live timestamp can outrank a
    /// NEWER disk one whenever the live value's fractional second happens to be large, purely
    /// because the disk value lost its fraction. Truncating first makes same-second edits
    /// compare equal and fall through to the deterministic byte tie-break instead, regardless
    /// of which side happens to still be at full precision.
    static func order<T: Encodable>(_ a: T, _ b: T, stamp: (T) -> Date) -> (winner: T, loser: T) {
        let sa = truncatedToSeconds(stamp(a)), sb = truncatedToSeconds(stamp(b))
        if sa != sb { return sa > sb ? (a, b) : (b, a) }
        guard let ba = CanonicalCodec.encode(a), let bb = CanonicalCodec.encode(b) else { return (a, b) }
        return ba.lexicographicallyPrecedes(bb) ? (b, a) : (a, b)
    }

    private static func truncatedToSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    static func pick<T: Encodable>(_ a: T, _ b: T, stamp: (T) -> Date) -> T {
        order(a, b, stamp: stamp).winner
    }

    /// Union of two id-keyed collections. A key present on only one side is kept verbatim; a
    /// key on both sides is resolved by `join`. Swift dictionary iteration order is
    /// unspecified, so callers must canonicalize the result before comparing or encoding it —
    /// `merge(_:_:options:)` does this once at the end rather than after every join.
    static func joinKeyed<T>(_ a: [T], _ b: [T], id: (T) -> UUID, join: (T, T) -> T) -> [T] {
        var byID: [UUID: T] = [:]
        for item in a { byID[id(item)] = item }
        for item in b {
            let k = id(item)
            byID[k] = byID[k].map { join($0, item) } ?? item
        }
        return Array(byID.values)
    }

    // MARK: - Per-record joins

    static func joinAssetProperty(_ a: AssetPropertyDTO, _ b: AssetPropertyDTO) -> AssetPropertyDTO {
        pick(a, b, stamp: { $0.modifyDate ?? .distantPast })
    }

    static func joinPhoto(_ a: PhotoDTO, _ b: PhotoDTO) -> PhotoDTO {
        pick(a, b, stamp: { $0.modifyDate ?? $0.addedDate })
    }

    static func joinEvent(_ a: EventDTO, _ b: EventDTO) -> EventDTO {
        pick(a, b, stamp: { $0.modifyDate ?? .distantPast })
    }

    static func joinTransaction(_ a: TransactionDTO, _ b: TransactionDTO) -> TransactionDTO {
        pick(a, b, stamp: { $0.modifyDate ?? .distantPast })
    }

    /// Whole-record last-writer-wins. `fields` order is a semantic display order (not a merge
    /// key set), so it is never merged element-wise — a field removed on one device is removed
    /// everywhere, which is the accepted tradeoff documented on `CompositeTypeDefinition`.
    static func joinCompositeType(_ a: CompositeTypeDTO, _ b: CompositeTypeDTO) -> CompositeTypeDTO {
        pick(a, b, stamp: { $0.modifyDate ?? .distantPast })
    }

    /// Header (`name`, `isUserExtensible`, `systemOptions`) by last-writer-wins; `userOptions`
    /// as a grow-only union — the winner's array first, then the loser's missing options in the
    /// loser's own order. Never loses a concurrently-added option; the accepted cost is that
    /// `removeUserOption` doesn't propagate — a peer's still-live copy resurrects it on the
    /// next merge. `systemOptions` never diverges between devices (nothing mutates it after
    /// creation), so taking it from the winner is safe.
    static func joinComboList(_ a: ComboListDTO, _ b: ComboListDTO) -> ComboListDTO {
        let (winner, loser) = order(a, b, stamp: { $0.modifyDate ?? .distantPast })
        var merged = winner
        let winnerAll = Set(winner.systemOptions + winner.userOptions)
        merged.userOptions = winner.userOptions + loser.userOptions.filter { !winnerAll.contains($0) }
        return merged
    }

    /// Header (`name`, `iconName`, tombstone) by last-writer-wins; `propertyTemplates` joined
    /// element-wise by each template's own `modifyDate` — preserving the dedupe-by-`definition.id`
    /// discipline `appendMissingProperties` already relies on so a duplicate `definition.id`
    /// never makes a template unreachable to `Asset.value(for:)`. `AssetCategory` has no header
    /// timestamp finer than the whole record, so a rename and an icon change are one unit.
    static func joinCategory(_ a: CategoryDTO, _ b: CategoryDTO) -> CategoryDTO {
        var merged = pick(a, b, stamp: { $0.modifyDate ?? .distantPast })
        merged.propertyTemplates = joinKeyed(a.propertyTemplates, b.propertyTemplates,
                                             id: { $0.id }, join: joinAssetProperty)
        return merged
    }

    /// Composite join across four independent stamps — this is the one join that must never
    /// collapse to a single whole-record `pick`. `Asset.modifiedDate` is a rollup bumped by
    /// every child mutation (a property edit, a photo add, ...), so using it to decide the
    /// asset's own `name`/tombstone would let an unrelated later child edit on one device beat
    /// an earlier delete on another and resurrect it. `headModifyDate` and
    /// `parentageModifyDate` exist specifically to avoid that.
    static func joinAsset(_ a: AssetDTO, _ b: AssetDTO) -> AssetDTO {
        let head = pick(a, b, stamp: { $0.headModifyDate ?? $0.modifiedDate })
        let parentage = pick(a, b, stamp: { $0.parentageModifyDate ?? $0.createdDate })
        var merged = a
        merged.name = head.name
        merged.isDeleted = head.isDeleted
        merged.deletedAt = head.deletedAt
        merged.headModifyDate = head.headModifyDate ?? head.modifiedDate
        merged.parentID = parentage.parentID
        merged.parentageModifyDate = parentage.parentageModifyDate ?? parentage.createdDate
        merged.createdDate = min(a.createdDate, b.createdDate)
        merged.modifiedDate = max(a.modifiedDate, b.modifiedDate)
        // Purge is monotone and OR's across sides — once either device has stripped this
        // asset, the strip must win, or a peer that hasn't purged yet would keep resurrecting
        // the payload every time its still-full copy joins against the stripped one. Written
        // only in the purged case — unconditionally writing `false` here would coerce a `nil`
        // (an un-migrated on-disk record that predates this field) into an explicit `false`,
        // changing the encoded bytes and breaking `merge(a,a) == canonical(a)`.
        if (a.isPurged ?? false) || (b.isPurged ?? false) {
            merged.isPurged = true
            return stripPurged(merged)
        }
        merged.baseProperties = joinKeyed(a.baseProperties, b.baseProperties, id: { $0.id }, join: joinAssetProperty)
        merged.customProperties = joinKeyed(a.customProperties, b.customProperties, id: { $0.id }, join: joinAssetProperty)
        merged.photos = joinKeyed(a.photos, b.photos, id: { $0.id }, join: joinPhoto)
        merged.events = joinKeyed(a.events, b.events, id: { $0.id }, join: joinEvent)
        merged.transactions = joinKeyed(a.transactions, b.transactions, id: { $0.id }, join: joinTransaction)
        return merged
        // categoryID is untouched (stays `a`'s): nothing in this codebase changes an asset's
        // category after creation, so there is nothing to reconcile.
    }

    /// Strips an asset DTO down to the minimal tombstone `AssetStore.purgeInPlace` produces —
    /// `baseProperties`/`customProperties`/`photos`/`events`/`transactions` emptied, `parentID`
    /// cleared. `id`/`name`/`categoryID`/timestamps/tombstone survive untouched. A fixed point:
    /// applying it to already-stripped input changes nothing, which is what makes a stale
    /// peer's still-full copy of a purged asset get re-stripped on every merge instead of
    /// resurrecting the payload.
    static func stripPurged(_ dto: AssetDTO) -> AssetDTO {
        var stripped = dto
        stripped.baseProperties = []
        stripped.customProperties = []
        stripped.photos = []
        stripped.events = []
        stripped.transactions = []
        stripped.parentID = nil
        return stripped
    }

    /// Union by id. Entries are immutable, so no field-level join is needed — order is
    /// irrelevant here too, `canonicalized()` imposes the final order.
    private static func joinActivityLog(_ a: [ActivityLogDTO], _ b: [ActivityLogDTO]) -> [ActivityLogDTO] {
        var seen = Set<UUID>()
        var result: [ActivityLogDTO] = []
        for entry in a + b where !seen.contains(entry.id) {
            seen.insert(entry.id)
            result.append(entry)
        }
        return result
    }

    // MARK: - Snapshot-level merge

    static func merge(_ a: StoreSnapshotDTO, _ b: StoreSnapshotDTO, options: Options = Options()) -> StoreSnapshotDTO {
        var merged = StoreSnapshotDTO(
            schemaVersion: max(a.schemaVersion, b.schemaVersion),
            compositeTypes: joinKeyed(a.compositeTypes, b.compositeTypes, id: { $0.id }, join: joinCompositeType),
            comboLists: joinKeyed(a.comboLists, b.comboLists, id: { $0.id }, join: joinComboList),
            categories: joinKeyed(a.categories, b.categories, id: { $0.id }, join: joinCategory),
            assets: joinKeyed(a.assets, b.assets, id: { $0.id }, join: joinAsset),
            activityLog: joinActivityLog(a.activityLog, b.activityLog),
            // Never a merge input — per-device cosmetic preference, moved out of the synced
            // manifest entirely in Step 9. Kept here only so the field still round-trips for
            // any snapshot built before that move.
            backgroundTheme: a.backgroundTheme
        )
        merged.assets = normalizeHierarchy(merged.assets)
        merged = reap(merged, cutoff: options.purgeCutoff)
        return merged.canonicalized()
    }

    // MARK: - Hierarchy normalization

    /// Repairs the two ways a merge (never a single device acting alone) can break the asset
    /// hierarchy: a dangling `parentID` (references an id not present in the merged set — the
    /// parent side lost, or was concurrently reaped) and a cycle (each side's hierarchy was
    /// acyclic on its own, but a re-parent on one side crossing a re-parent on the other can
    /// close a loop). Applied last in `merge`, so the OUTPUT is a fixed point: re-running this
    /// on an already-normalized snapshot changes nothing, which keeps
    /// `merge(merge(a,b),a) == merge(a,b)` true even for a cycle-forming pair.
    ///
    /// A cycle is broken at its member with the greatest `(parentageModifyDate, id)` — the
    /// newest re-parent is the one that closed the loop, so it's the one that yields. Not
    /// resolved by checking `isDeleted` on the parent, unlike the import merge's
    /// `mergeHierarchy`: doing that here would fight `softDeleteAsset`'s subtree invariant;
    /// `AssetStore.applyInPlace` handles the live/deleted boundary the same way `mergeSnapshot`
    /// already does, via `detachAcrossDeletionBoundary`.
    static func normalizeHierarchy(_ assets: [AssetDTO]) -> [AssetDTO] {
        var byID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })

        for id in byID.keys {
            guard var asset = byID[id] else { continue }
            if let pid = asset.parentID, pid == id || byID[pid] == nil {
                asset.parentID = nil
                byID[id] = asset
            }
        }

        var brokenIDs: Set<UUID> = []
        for startID in byID.keys {
            var visited: [UUID] = []
            var cursor: UUID? = startID
            while let currentID = cursor, !brokenIDs.contains(currentID) {
                if let idx = visited.firstIndex(of: currentID) {
                    let cycle = visited[idx...].compactMap { byID[$0] }
                    if let toBreak = cycle.max(by: {
                        let sa = truncatedToSeconds($0.parentageModifyDate ?? $0.createdDate)
                        let sb = truncatedToSeconds($1.parentageModifyDate ?? $1.createdDate)
                        return sa == sb ? $0.id.uuidString < $1.id.uuidString : sa < sb
                    }) {
                        var broken = toBreak
                        broken.parentID = nil
                        byID[toBreak.id] = broken
                        brokenIDs.insert(toBreak.id)
                    }
                    break
                }
                visited.append(currentID)
                cursor = byID[currentID]?.parentID
                if visited.count > byID.count { break }  // safety valve; shouldn't be reachable
            }
        }
        return assets.map { byID[$0.id] ?? $0 }
    }

    // MARK: - Tombstone reaping

    private static func isExpired(_ isDeleted: Bool, _ deletedAt: Date?, before cutoff: Date) -> Bool {
        isDeleted && (deletedAt ?? .distantFuture) < cutoff
    }

    /// Strips assets whose tombstone has aged past `cutoff` down to a minimal record (see
    /// `stripPurged`) rather than removing them — the record must survive so the strip is
    /// visible to a peer that still holds the full asset, or the next merge would union the
    /// payload straight back in. Also drops categories no longer referenced by any non-purged
    /// asset, inline photos/events/transactions/custom properties/templates aged past cutoff on
    /// non-purged assets, and activity log entries whose owning asset is purged (or absent) and
    /// whose own timestamp predates cutoff. Mirrors `AssetStore.purgeHardDeleted`'s rules
    /// exactly, so a merge and a local purge converge to the same result. `deletedAt == nil` is
    /// never expired.
    static func reap(_ snap: StoreSnapshotDTO, cutoff: Date) -> StoreSnapshotDTO {
        var result = snap

        for i in result.assets.indices {
            if isExpired(result.assets[i].isDeleted, result.assets[i].deletedAt, before: cutoff) {
                result.assets[i].isPurged = true
            }
            guard result.assets[i].isPurged != true else {
                result.assets[i] = stripPurged(result.assets[i])
                continue
            }
            result.assets[i].photos.removeAll { isExpired($0.isDeleted ?? false, $0.deletedAt, before: cutoff) }
            result.assets[i].events.removeAll { isExpired($0.isDeleted ?? false, $0.deletedAt, before: cutoff) }
            result.assets[i].transactions.removeAll { isExpired($0.isDeleted ?? false, $0.deletedAt, before: cutoff) }
            result.assets[i].customProperties.removeAll { isExpired($0.isDeleted ?? false, $0.deletedAt, before: cutoff) }
        }

        let nonPurgedCategoryIDs = Set(result.assets.filter { $0.isPurged != true }.map(\.categoryID))
        result.categories = result.categories.filter { cat in
            nonPurgedCategoryIDs.contains(cat.id) || !isExpired(cat.isDeleted, cat.deletedAt, before: cutoff)
        }
        for i in result.categories.indices {
            result.categories[i].propertyTemplates.removeAll {
                isExpired($0.isDeleted ?? false, $0.deletedAt, before: cutoff)
            }
        }

        let allAssetIDs = Set(result.assets.map(\.id))
        let purgedAssetIDs = Set(result.assets.filter { $0.isPurged == true }.map(\.id))
        result.activityLog = result.activityLog.filter { entry in
            let referenced = entry.owningAssetID ?? (entry.kind == LoggedRecordKind.asset.rawValue ? entry.recordID : nil)
            guard let referenced else { return true }
            let ownerGone = !allAssetIDs.contains(referenced) || purgedAssetIDs.contains(referenced)
            guard ownerGone else { return true }
            return entry.timestamp >= cutoff
        }

        return result
    }
}
