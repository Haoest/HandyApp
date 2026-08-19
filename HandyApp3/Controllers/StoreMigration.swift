import Foundation

/// One versioned transform applied to a snapshot below `storeSchemaVersion`. Pure: no
/// `Date()`, no I/O — the same content in must always produce the same bytes out, or two
/// devices migrating the same install independently would diverge and re-upload forever.
struct StoreMigration {
    let toVersion: Int
    let transform: (inout StoreSnapshotDTO) -> Void
}

/// Applies `AssetStore`'s old monolithic `migrate(_:)` as an ordered list of steps instead, so
/// each one is independently testable and the function doesn't grow into a pile of nested
/// `if`s. All three of `AssetStore+Persistence.swift`'s call sites (`applyLoadedResult`,
/// `importJSON`, `handleCloudMonitorNotification`) route through `migrate` here, so a stale
/// snapshot is brought current wherever it enters the store — including a peer's snapshot
/// arriving mid-session via cloud sync, before `SnapshotReconciler.merge` ever sees it.
enum StoreMigrator {

    /// Ordered ascending by `toVersion`. Every step MUST be idempotent — a store whose
    /// `store.json` manifest is missing (see `StoreFileLayout.readLocked`'s "no manifest but
    /// tree present" fallback, which reads such a store as already current) skips every gated
    /// step below, so a step that isn't safe to re-run could silently corrupt a store that gets
    /// mis-read as current on some later launch.
    static let migrations: [StoreMigration] = [
        StoreMigration(toVersion: 5, transform: migrateV5RekeyBuiltInIdentity),
    ]

    /// Un-gated, content-derived normalization — runs on every call regardless of
    /// `schemaVersion`, and never bumps it. Moved verbatim from the old `AssetStore.migrate`.
    ///
    /// v1 → v2 added modifyDate/isDeleted/deletedAt to Event/Transaction/Photo; the fields are
    /// optional with a decode-time fallback (see `event`/`transaction`/`photo(from:)` in
    /// AssetStore+Persistence.swift), so no transform is needed here.
    /// v2 → v3 added isDeleted/deletedAt to AssetPropertyDTO (custom properties); same
    /// optional-with-fallback treatment, no transform needed.
    /// v3 → v4 added modifyDate to CategoryDTO/ComboListDTO/CompositeTypeDTO and
    /// headModifyDate to AssetDTO — same optional-with-fallback treatment, no transform needed.
    ///
    /// Back-fills `purgedAt` for any record purged before the field existed. Not schema-gated
    /// (bumping the version would churn bytes across a mixed-version fleet via
    /// `max(a.schemaVersion, b.schemaVersion)`): this simply always runs, and is a no-op once
    /// every record has its own `purgedAt`. `deletedAt`, not `Date()` — the back-fill must be
    /// content-derived and produce the same result on every device that reads this record, not
    /// a fresh wall-clock stamp that would make the bytes differ (and re-upload) on every
    /// device's next load.
    static func normalize(_ s: inout StoreSnapshotDTO) {
        for i in s.assets.indices where s.assets[i].isPurged == true && s.assets[i].purgedAt == nil {
            s.assets[i].purgedAt = s.assets[i].deletedAt
        }
        for i in s.categories.indices where s.categories[i].isPurged == true && s.categories[i].purgedAt == nil {
            s.categories[i].purgedAt = s.categories[i].deletedAt
        }
    }

    /// Applies `normalize`, then every step whose `toVersion` exceeds `snapshot.schemaVersion`,
    /// ascending, stamping `schemaVersion` after each. A snapshot already at or above
    /// `storeSchemaVersion` (a newer build's store, or an already-migrated one) passes through
    /// with only `normalize` applied — its version is never changed or lowered here. That's
    /// deliberate: protecting a newer store from being overwritten is `AssetStore
    /// .storeRequiresNewerApp`'s job, not this function's.
    ///
    /// `willApplyVersionedSteps`, if given, fires exactly once with the pre-transform snapshot,
    /// right before the first gated step runs — the hook `applyLoadedResult` uses to write a
    /// local backup before this device's on-disk data changes shape.
    static func migrate(
        _ snapshot: StoreSnapshotDTO,
        steps: [StoreMigration] = migrations,
        willApplyVersionedSteps: ((StoreSnapshotDTO) -> Void)? = nil
    ) -> StoreSnapshotDTO {
        var s = snapshot
        normalize(&s)

        let pending = steps.filter { $0.toVersion > s.schemaVersion }.sorted { $0.toVersion < $1.toVersion }
        guard !pending.isEmpty else { return s }

        willApplyVersionedSteps?(s)
        for step in pending {
            step.transform(&s)
            s.schemaVersion = step.toVersion
        }
        return s
    }
}
