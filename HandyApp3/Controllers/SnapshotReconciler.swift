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
        /// Set when `snap`'s asset shards may not have finished downloading (see
        /// `StoreFileLayout.ReadResult.isComplete`). Category purging in `reap` decides "no
        /// surviving asset references this category" from `snap.assets` — on an incomplete
        /// read that's not a fact, it's an artifact of files not being here yet. Purging is
        /// monotone and can't be undone once written, so unlike ordinary reaping (which
        /// self-heals if wrong, since a missing record is just re-added), an incomplete read
        /// must skip category purging entirely rather than risk it. Asset purging is unaffected
        /// — it depends only on the asset's own tombstone, never on what else is present.
        var assetsMayBeIncomplete: Bool = false
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

    // MARK: - Purge gating

    private static func assetContentStamp(_ dto: AssetDTO) -> Date {
        max(dto.modifiedDate, dto.headModifyDate ?? dto.modifiedDate)
    }

    private static func categoryContentStamp(_ dto: CategoryDTO) -> Date {
        let templateMax = dto.propertyTemplates.compactMap { $0.modifyDate }.max() ?? .distantPast
        return max(dto.modifyDate ?? .distantPast, templateMax)
    }

    /// Whether a purge decided at `deletedAt` (and, if later, actually carried out at
    /// `purgedAt`) is entitled to destroy content stamped `contentStamp`. Refuses when the
    /// content is strictly newer than that decision — an offline device that edited a record
    /// after it was soft-deleted elsewhere, but before the automatic retention sweep purged the
    /// tombstone roughly `DaysToRetainDeletedItems` later, must not have that edit silently
    /// destroyed the moment the two devices sync; the record simply stays a live tombstone (in
    /// Trash) instead of being stripped. Truncated to whole seconds for the same reason `order`
    /// is (see its doc comment).
    ///
    /// `purgedAtFallback` is what a *nil* `purgedAt` defaults to in the `max`, and it matters
    /// because "nil" means two different things at the two call sites:
    /// - `joinAsset`/`joinCategory` call this only once a side already carries
    ///   `isPurged == true`, where a nil `purgedAt` specifically means a pre-migration legacy
    ///   record (see `AssetDTO.purgedAt`'s doc comment) — those must stay permanently
    ///   unrefusable, matching the original always-strips behavior for data older than this
    ///   field. Pass `.distantFuture`, which always dominates the `max`.
    /// - `reap`'s transition test evaluates a record that is *not yet* purged, where a nil
    ///   `purgedAt` just means no purge has been attempted yet — it must be ignored, leaving
    ///   `deletedAt` alone as the threshold, rather than treated as an infinite block. Pass
    ///   `.distantPast`. (An existing *non-nil* `purgedAt` — left by an earlier refused
    ///   attempt, local or synced — still floors the threshold either way, so this evaluation
    ///   can never undermine a bar already established.) `AssetStore.purgeHardDeleted`'s local
    ///   sweep and the `Asset`/`AssetCategory.isProtectedFromAutoPurge` models mirror this same
    ///   `.distantPast` case, so all four call sites always agree about which records are
    ///   protected.
    private static func purgeIsEntitled(
        contentStamp: Date, deletedAt: Date?, purgedAt: Date?, purgedAtFallback: Date
    ) -> Bool {
        let content = truncatedToSeconds(contentStamp)
        let threshold = truncatedToSeconds(max(deletedAt ?? .distantPast, purgedAt ?? purgedAtFallback))
        return content <= threshold
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
        let aPurged = a.isPurged == true, bPurged = b.isPurged == true
        // purgedAt always folds via max, regardless of what the entitlement check below decides
        // — the field must keep accumulating every purge attempt's stamp even across a refused
        // round, or a later, larger stamp folded in on a subsequent merge could never raise the
        // bar past an earlier refusal. See `purgeIsEntitled`'s doc comment.
        merged.purgedAt = [a.purgedAt, b.purgedAt].compactMap { $0 }.max()
        if aPurged || bPurged {
            // Purge is monotone with one bounded exception, mirroring `joinAsset` exactly (see
            // its doc comment for the full rationale): a strip is refused when the not-yet-
            // purged side's own content (header rename or template edit) is strictly newer than
            // the purge decision. Refusal only applies when exactly one side is purged — if
            // both are, there's no live content left on either side to protect, so the strip
            // always proceeds. "The live side" is well-defined whichever side is `a`/`b`, so
            // this stays commutative.
            let bothPurged = aPurged && bPurged
            let live = aPurged ? b : a
            let refuses = !bothPurged && !purgeIsEntitled(
                contentStamp: categoryContentStamp(live), deletedAt: merged.deletedAt,
                purgedAt: merged.purgedAt, purgedAtFallback: .distantFuture)
            if !refuses {
                merged.isPurged = true
                // A category purge always follows a soft delete (`hardDeleteCategory` soft-
                // deletes first if needed), but force the tombstone here too — belt-and-braces
                // against `isPurged == true, isDeleted == false` ever reaching a view that
                // filters only on `isDeleted` (see the `!isPurged` filter additions this same
                // change adds to the handful of sites that were missing it).
                merged.isDeleted = true
                merged.deletedAt = merged.deletedAt ?? merged.purgedAt
                return stripPurgedCategory(merged)
            }
            // Refused: the tombstone (from the `pick` above) still propagates — the category
            // lands in Trash with its templates unioned below, same as an ordinary soft delete.
            merged.isPurged = false
            // `purgeCategoryInPlace` blanks name/iconName WITHOUT bumping `modifyDate` (see its
            // doc comment), so if the purged side happened to win the header `pick` above —
            // likely, since its `modifyDate` reflects the original soft-delete, which by
            // definition predates `live`'s protecting edit — `merged.name`/`iconName` would
            // otherwise be the purged side's blanked ("") header even though we're keeping this
            // category's content. Restore them from `live` explicitly; mirrors the identical fix
            // `AssetStore+Persistence.swift`'s import-path un-purge already applies for the same
            // reason. `modifyDate` is deliberately left as `pick` resolved it — only these two
            // fields are the ones a purge can corrupt without a compensating stamp.
            merged.name = live.name
            merged.iconName = live.iconName
        }
        merged.propertyTemplates = joinKeyed(a.propertyTemplates, b.propertyTemplates,
                                             id: { $0.id }, join: joinAssetProperty)
        return merged
    }

    /// Strips a category DTO down to the minimal tombstone `AssetStore.purgeCategoryInPlace`
    /// produces — `name`/`iconName` blanked, `propertyTemplates` emptied. `id`/timestamps/
    /// tombstone survive untouched. A fixed point: applying it to already-stripped input
    /// changes nothing, which is what makes a stale peer's still-full copy of a purged category
    /// get re-stripped on every merge instead of resurrecting the templates.
    static func stripPurgedCategory(_ dto: CategoryDTO) -> CategoryDTO {
        var stripped = dto
        stripped.name = ""
        stripped.iconName = ""
        stripped.propertyTemplates = []
        return stripped
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

        let aPurged = a.isPurged == true, bPurged = b.isPurged == true
        // purgedAt always folds via max, regardless of what the entitlement check below decides
        // — the field must keep accumulating every purge attempt's stamp even across a refused
        // round, or a later, larger stamp folded in on a subsequent merge could never raise the
        // bar past an earlier refusal. See `purgeIsEntitled`'s doc comment.
        merged.purgedAt = [a.purgedAt, b.purgedAt].compactMap { $0 }.max()
        if aPurged || bPurged {
            // Purge is monotone with one bounded exception: a strip is refused when the
            // not-yet-purged side's own content (`baseProperties`/`customProperties`/`photos`/
            // `events`/`transactions`, via `modifiedDate`) is strictly newer than the purge
            // decision — an offline device that edited this asset after it was soft-deleted
            // elsewhere, but before the automatic retention sweep purged the tombstone roughly
            // `DaysToRetainDeletedItems` later, must not have that edit silently destroyed the
            // moment the two devices sync. Refusal only applies when exactly one side is purged
            // — if both are, there's no live content left on either side to protect, so the
            // strip always proceeds. "The live side" is well-defined whichever side is `a`/`b`,
            // so this stays commutative; see the doc comment above `purgeIsEntitled` for the
            // full associativity argument (`purgedAt`'s unconditional max-fold is what makes a
            // later, larger stamp always able to override an earlier refusal, regardless of the
            // order records are folded together in).
            let bothPurged = aPurged && bPurged
            let live = aPurged ? b : a
            let refuses = !bothPurged && !purgeIsEntitled(
                contentStamp: assetContentStamp(live), deletedAt: merged.deletedAt,
                purgedAt: merged.purgedAt, purgedAtFallback: .distantFuture)
            if !refuses {
                merged.isPurged = true
                // A record can only be purged after being soft-deleted, but force the tombstone
                // here too — belt-and-braces against `isPurged == true, isDeleted == false` ever
                // reaching a view that filters only on `isDeleted` (the handful of sites this
                // same change adds a `!isPurged` filter to, as a second line of defense).
                merged.isDeleted = true
                merged.deletedAt = merged.deletedAt ?? merged.purgedAt
                return stripPurged(merged)
            }
            // Refused: the tombstone (from the head pick above) still propagates — the asset
            // lands in Trash with its content unioned below, same as an ordinary soft delete.
            // `purgeInPlace` never touches `name`, unlike the category equivalent, so there is
            // no blanked-header risk here to compensate for.
            merged.isPurged = false
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
        merged = reap(merged, cutoff: options.purgeCutoff, assetsMayBeIncomplete: options.assetsMayBeIncomplete)
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

    /// Strips assets and categories whose tombstone has aged past `cutoff` down to a minimal
    /// record (see `stripPurged`/`stripPurgedCategory`) rather than removing them — the record
    /// must survive so the strip is visible to a peer that still holds the full asset/category,
    /// or the next merge would union the payload straight back in. A category kept alive only
    /// by a now-purged asset is eligible for purging in the same pass, since a purged asset no
    /// longer counts as a reference; categories still referenced by any non-purged asset are
    /// retained regardless of age. Category purging is skipped entirely when
    /// `assetsMayBeIncomplete` is set, since "no surviving asset references this" isn't a fact
    /// derivable from a partial `snap.assets` (see `Options.assetsMayBeIncomplete`) — asset
    /// purging is unaffected, as it depends only on the asset's own tombstone. Also reaps inline
    /// photos/events/transactions/custom properties/templates aged past cutoff on non-purged
    /// assets/categories, and activity log entries whose owning asset is purged (or absent) and
    /// whose own timestamp predates cutoff. Mirrors `AssetStore.purgeHardDeleted`'s rules
    /// exactly, so a merge and a local purge converge to the same result. `deletedAt == nil` is
    /// never expired.
    static func reap(_ snap: StoreSnapshotDTO, cutoff: Date, assetsMayBeIncomplete: Bool = false) -> StoreSnapshotDTO {
        var result = snap

        for i in result.assets.indices {
            // Gated the same way `joinAsset` gates a purge (see `purgeIsEntitled`'s doc
            // comment): an aged tombstone whose content is still newer than the delete decision
            // (or an already-recorded purge attempt, whichever is later — `result.assets[i]`
            // here is post-`joinKeyed`, so `purgedAt` may already carry a fold from `joinAsset`
            // having run over this same pair) stays a live tombstone rather than being stripped.
            if isExpired(result.assets[i].isDeleted, result.assets[i].deletedAt, before: cutoff),
               purgeIsEntitled(contentStamp: assetContentStamp(result.assets[i]),
                               deletedAt: result.assets[i].deletedAt, purgedAt: result.assets[i].purgedAt,
                               purgedAtFallback: .distantPast) {
                result.assets[i].isPurged = true
                // deletedAt, not Date(): must stay content-derived so every device reaping the
                // same aged tombstone produces byte-identical output. Only when nothing already
                // recorded a purge attempt — an existing stamp (from `joinAsset`, always ≥
                // deletedAt) is never regressed.
                if result.assets[i].purgedAt == nil { result.assets[i].purgedAt = result.assets[i].deletedAt }
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

        if !assetsMayBeIncomplete {
            let nonPurgedCategoryIDs = Set(result.assets.filter { $0.isPurged != true }.map(\.categoryID))
            for i in result.categories.indices {
                // Same gate as the asset loop above — see its comment and `purgeIsEntitled`.
                if isExpired(result.categories[i].isDeleted, result.categories[i].deletedAt, before: cutoff)
                    && !nonPurgedCategoryIDs.contains(result.categories[i].id)
                    && purgeIsEntitled(contentStamp: categoryContentStamp(result.categories[i]),
                                       deletedAt: result.categories[i].deletedAt, purgedAt: result.categories[i].purgedAt,
                                       purgedAtFallback: .distantPast) {
                    result.categories[i].isPurged = true
                    if result.categories[i].purgedAt == nil {
                        result.categories[i].purgedAt = result.categories[i].deletedAt
                    }
                }
            }
        }
        for i in result.categories.indices {
            guard result.categories[i].isPurged != true else {
                result.categories[i] = stripPurgedCategory(result.categories[i])
                continue
            }
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
