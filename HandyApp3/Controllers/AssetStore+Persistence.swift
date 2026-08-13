import Foundation
import os

private let persistenceLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "HandyApp3", category: "Persistence"
)

// MARK: - Photo file storage

enum PhotoStorage {
    /// `root` defaults to the real store directory; Tier 2 multi-device tests pass a private
    /// per-device temp directory instead. Every call site keeps compiling unchanged.
    static func fullURL(id: UUID, root: URL = AssetStore.baseDir) -> URL {
        root.appendingPathComponent("Photos/\(id)_full.jpg")
    }
    static func thumbURL(id: UUID, root: URL = AssetStore.baseDir) -> URL {
        root.appendingPathComponent("Photos/\(id)_thumb.jpg")
    }

    static func save(id: UUID, imageData: Data, thumbnailData: Data, root: URL = AssetStore.baseDir) {
        try? imageData.write(to: fullURL(id: id, root: root), options: .atomic)
        try? thumbnailData.write(to: thumbURL(id: id, root: root), options: .atomic)
    }

    private static func read(_ url: URL) -> Data? {
        if let data = try? Data(contentsOf: url) { return data }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        return nil
    }

    static func loadFull(id: UUID, root: URL = AssetStore.baseDir) -> Data? { read(fullURL(id: id, root: root)) }
    static func loadThumb(id: UUID, root: URL = AssetStore.baseDir) -> Data? { read(thumbURL(id: id, root: root)) }

    static func delete(id: UUID, root: URL = AssetStore.baseDir) {
        try? FileManager.default.removeItem(at: fullURL(id: id, root: root))
        try? FileManager.default.removeItem(at: thumbURL(id: id, root: root))
    }
}

// MARK: - Import errors

/// Thrown by `importJSON` for well-formed JSON that isn't an exported snapshot — most commonly
/// the app's own on-disk manifest (`store.json`), which decodes cleanly but isn't an export.
enum ImportError: LocalizedError {
    case notAnExport

    var errorDescription: String? {
        "This file isn't an exported backup — it looks like the app's own internal store file, not something created by Export. Use Tools > Export Data to create a file that can be imported."
    }
}

// MARK: - AssetStore persistence

extension AssetStore {

    // MARK: - URL resolution

    /// Master switch for iCloud document sync of the store. While false, all store files
    /// live in local Documents and no ubiquity-container access happens. iCloud Backup of
    /// the local Documents directory is unaffected.
    ///
    /// Flipped true as the final step of the sync-correctness pass: canonicalization
    /// (StoreFileLayout/Persistence.swift), schema v4 timestamps, SnapshotReconciler,
    /// applyInPlace, the hasAuthoritativeLocalState seed guard, per-shard NSFileVersion
    /// conflict resolution, download priming, and NSFileCoordinator are all in place and
    /// covered by SnapshotReconcilerTests/ApplyInPlaceTests/TwoDeviceRelayTests/
    /// ConflictResolutionTests/SyncRelayTests. Real ubiquity-container/NSMetadataQuery/
    /// NSFileVersion/NSFileCoordinator behavior still needs the manual pass in
    /// docs/icloud-sync-verification.md on real devices before this ships.
    static let iCloudSyncEnabled = true

    /// Tests only: points the store at a private temp directory.
    static var baseDirOverride: URL?

    static var baseDir: URL {
        if let override = baseDirOverride {
            createStoreSubdirectories(in: override)
            return override
        }
        return resolvedBaseDir
    }

    /// Creates every subdirectory the multi-file layout needs (`StoreFileLayout` also creates
    /// `Definitions`/`Assets`/`Activity` lazily on write, but doing it here too means they exist
    /// even before the first save — e.g. for a `read()` on a directory nothing has written to yet).
    private static func createStoreSubdirectories(in dir: URL) {
        let fm = FileManager.default
        for sub in ["Photos", "Definitions", "Assets", "Activity"] {
            try? fm.createDirectory(at: dir.appendingPathComponent(sub, isDirectory: true),
                                    withIntermediateDirectories: true)
        }
    }

    /// Base directory for all store files. When `iCloudSyncEnabled` is true and the
    /// ubiquity container is available, uses the iCloud Documents directory (migrating
    /// any existing local store on first run). Otherwise uses local Documents.
    /// Resolved once per launch — `url(forUbiquityContainerIdentifier:)` can block.
    /// Creates the store subdirectories as a side effect.
    private static let resolvedBaseDir: URL = {
        let fm = FileManager.default
        let localDocs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir: URL
        if iCloudSyncEnabled, let container = fm.url(forUbiquityContainerIdentifier: nil) {
            let cloudDocs = container.appendingPathComponent("Documents", isDirectory: true)
            migrateLocalStoreIfNeeded(from: localDocs, to: cloudDocs)
            dir = cloudDocs
        } else {
            dir = localDocs
        }
        createStoreSubdirectories(in: dir)
        return dir
    }()

    /// One-time move of pre-iCloud data into the ubiquity container. Without this, the first
    /// launch after enabling iCloud would find an empty container, reseed sample data, and the
    /// user's real store would appear wiped. Copies (rather than moves) so the local files
    /// remain as a frozen fallback if the app is ever built without iCloud entitlements again.
    /// Never overwrites cloud data: if the container already has a store (downloaded or still
    /// a placeholder), another device got there first and its copy wins.
    ///
    /// Copies the whole subtree — `Definitions/`, `Assets/`, `Activity/`, `Photos/`, plus a
    /// legacy `store.json` if one is still present — not just the single manifest file. Leaving
    /// this as a single-file copy would make the first sync-enabled launch look like data loss.
    private static func migrateLocalStoreIfNeeded(from localDocs: URL, to cloudDocs: URL) {
        let fm = FileManager.default
        let localStore = localDocs.appendingPathComponent("store.json")
        let cloudStore = cloudDocs.appendingPathComponent("store.json")
        let hasLocalContent = fm.fileExists(atPath: localStore.path)
            || fm.fileExists(atPath: localDocs.appendingPathComponent("Assets").path)
        // A not-yet-downloaded ubiquitous item still reports true for fileExists under its
        // real name on modern iOS — a `.name.icloud` dot-placeholder is a different, unrelated
        // convention (shown after an already-downloaded file is evicted locally to save
        // space), not a general "not yet synced from cloud" signal. So checking the real path
        // is both correct and sufficient for "does the cloud already have something here,"
        // downloaded or not. The manifest also covers the multi-file layout (its manifest is
        // named store.json too); Definitions/Assets are checked as well only to tolerate the
        // rare local state where a manifest write failed but data shards already succeeded.
        let hasCloudContent = fm.fileExists(atPath: cloudStore.path)
            || fm.fileExists(atPath: cloudDocs.appendingPathComponent("Definitions").path)
            || fm.fileExists(atPath: cloudDocs.appendingPathComponent("Assets").path)
        guard hasLocalContent, !hasCloudContent else { return }

        try? fm.createDirectory(at: cloudDocs, withIntermediateDirectories: true)
        for entry in ["store.json", StoreFileLayout.legacyBackupFilename] {
            let src = localDocs.appendingPathComponent(entry)
            guard fm.fileExists(atPath: src.path) else { continue }
            try? fm.copyItem(at: src, to: cloudDocs.appendingPathComponent(entry))
        }
        for sub in ["Photos", "Definitions", "Assets", "Activity"] {
            let localSub = localDocs.appendingPathComponent(sub, isDirectory: true)
            let cloudSub = cloudDocs.appendingPathComponent(sub, isDirectory: true)
            try? fm.createDirectory(at: cloudSub, withIntermediateDirectories: true)
            if let files = try? fm.contentsOfDirectory(at: localSub, includingPropertiesForKeys: nil) {
                for file in files {
                    try? fm.copyItem(at: file, to: cloudSub.appendingPathComponent(file.lastPathComponent))
                }
            }
        }
    }

    static var storeURL: URL { baseDir.appendingPathComponent("store.json") }

    // MARK: - Public API

    /// Loads persisted state from disk. File I/O runs on a background thread internally;
    /// safe to call from the main thread. Returns false if no store exists or a structural
    /// shard (composite types, combo lists, or categories) can't be read — see
    /// `StoreFileLayout`'s failure policy for why those two cases are treated the same.
    @discardableResult
    func load() -> Bool {
        var result: StoreFileLayout.ReadResult?
        DispatchQueue.global(qos: .userInitiated).sync {
            Self.primeCloudDownloads(timeout: 10)
            result = fileLayout.read(baseDir: Self.baseDir)
        }
        return applyLoadedResult(result, root: Self.baseDir)
    }

    /// Core load against any directory, run synchronously on the calling thread — no
    /// background dispatch, no `waitForCloudStore`. `load()` is the production entry point;
    /// this is the seam Tier 2 multi-device tests (`SyncRelay`) use to drive a store against
    /// its own private temp directory instead of `AssetStore.baseDir`.
    @discardableResult
    func load(from root: URL) -> Bool {
        applyLoadedResult(fileLayout.read(baseDir: root), root: root)
    }

    private func applyLoadedResult(_ result: StoreFileLayout.ReadResult?, root: URL) -> Bool {
        guard let result else { return false }
        lastPersistedData = fileLayout.storeDigest
        applySnapshot(migrate(result.snapshot))
        if result.wasMigratedFromLegacy {
            persistenceLogger.notice("load: migrated a legacy single-file store to the multi-file layout")
            // Must be durable before anything else runs: the in-memory state now reflects the
            // new layout, and store.legacy-v3.json is the only remaining copy of the old one.
            DispatchQueue.global(qos: .userInitiated).sync { self.save(to: root) }
        }
        return true
    }

    /// If iCloud sync is enabled and the ubiquity container is active, triggers download of
    /// every `.json`/`.jpg` file under `baseDir` and blocks up to `timeout` seconds for the
    /// *structural* set — the manifest and every `Definitions/*.json` file, what `read` hard-
    /// fails without per `StoreFileLayout`'s failure policy — to finish downloading.
    /// `Assets/*.json` and `Photos/*` are left to arrive opportunistically afterward;
    /// `ReadResult.isComplete` already tolerates them arriving late.
    ///
    /// Checks `URLResourceValues.ubiquitousItemDownloadingStatus`, not `fileExists` — a
    /// not-yet-downloaded ubiquitous item still reports true for `fileExists` under its real
    /// name on modern iOS, so `fileExists` alone can never detect "still downloading."
    private static func primeCloudDownloads(timeout: TimeInterval) {
        let fm = FileManager.default
        guard iCloudSyncEnabled,
              baseDirOverride == nil,
              fm.url(forUbiquityContainerIdentifier: nil) != nil else { return }
        let dir = baseDir
        let structuralURLs = [
            "store.json",
            "Definitions/types.json",
            "Definitions/combolists.json",
            "Definitions/categories.json",
        ].map { dir.appendingPathComponent($0) }

        if let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator where ["json", "jpg"].contains(url.pathExtension) {
                try? fm.startDownloadingUbiquitousItem(at: url)
            }
        }
        for url in structuralURLs {
            try? fm.startDownloadingUbiquitousItem(at: url)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !structuralURLs.allSatisfy(isDownloaded) {
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    /// True if the item is fully downloaded, or if it can't be inspected at all — the latter
    /// almost always means it doesn't exist yet (e.g. nothing has synced down to this device),
    /// which is nothing to wait for rather than something stuck downloading.
    private static func isDownloaded(_ url: URL) -> Bool {
        guard let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus else { return true }
        return status == .current || status == .downloaded
    }

    func factoryReset() {
        savesSuspended = false
        let photosDir = Self.baseDir.appendingPathComponent("Photos", isDirectory: true)
        if let files = try? FileManager.default.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: nil) {
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
        try? FileManager.default.removeItem(
            at: Self.baseDir.appendingPathComponent(StoreFileLayout.legacyBackupFilename))
        // Do NOT removeItem on storeURL — overwriting via save() propagates as content
        // (a "tombstone by overwrite") so other devices apply it, rather than ignoring a deletion.
        // Stale Assets/*.json files from before the reset are cleared by the orphan sweep inside
        // the save() below — the same mechanism that makes an ordinary hard delete stick.
        _applyLoaded(compositeTypes: [:], comboLists: [:], categories: [:], assets: [:], activityLog: [])
        backgroundTheme = .mist
        seedBuiltInComboLists()
        seedBuiltInCategories()
        seedBuiltInTypes()
        seedBuiltInAssets()
        seedSampleAutomobile()
        DispatchQueue.global(qos: .userInitiated).sync { self.save() }
    }

    func exportJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(buildSnapshot(includePhotoData: true))
    }

    /// Decodes the given exported JSON and additively merges it into the live store.
    /// Local data wins: nothing already present is overwritten, re-parented, or removed —
    /// only records the local store is missing are added. Incoming soft-deleted
    /// categories/assets are skipped, except a soft-deleted category still needed by a
    /// surviving incoming asset, which is copied in (as deleted) so the asset keeps its
    /// real name and icon instead of falling back to a "Recovered" placeholder.
    ///
    /// One deliberate exception to "local wins": when a live incoming record matches a
    /// locally soft-deleted one by id, the local record is restored from the trash. An
    /// import that says a record is alive is treated as intent to bring it back.
    func importJSON(data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let incoming: StoreSnapshotDTO
        do {
            incoming = try decoder.decode(StoreSnapshotDTO.self, from: data)
        } catch {
            // A manifest (store.json under the new layout) is valid JSON that decodes
            // successfully as StoreManifestDTO but not as a full snapshot — give a clearer
            // error than the raw decode failure rather than leaving the user to guess why
            // their own store.json won't import.
            if (try? decoder.decode(StoreManifestDTO.self, from: data)) != nil {
                throw ImportError.notAnExport
            }
            throw error
        }

        let photoIDsToMaterialize = mergeSnapshot(migrate(incoming))

        // Write embedded photo bytes for merged photos. Never overwrite an existing local
        // file — local bytes always win, matching the additive-only rule.
        for assetDTO in incoming.assets {
            for photoDTO in assetDTO.photos where photoIDsToMaterialize.contains(photoDTO.id) {
                if let full = photoDTO.fullImage {
                    let url = PhotoStorage.fullURL(id: photoDTO.id)
                    if !FileManager.default.fileExists(atPath: url.path) {
                        try? full.write(to: url, options: .atomic)
                    }
                }
                if let thumb = photoDTO.thumbnail {
                    let url = PhotoStorage.thumbURL(id: photoDTO.id)
                    if !FileManager.default.fileExists(atPath: url.path) {
                        try? thumb.write(to: url, options: .atomic)
                    }
                }
            }
        }

        // Synchronous: the import must be durably on disk before this returns, or a
        // relaunch / cloud-monitor refresh can resurrect the pre-import store.
        DispatchQueue.global(qos: .userInitiated).sync { self.save() }
    }

    /// Encodes the current store state and writes only the shards that changed.
    /// Must be called on a background thread.
    func save() {
        guard !savesSuspended else { return }
        save(to: Self.baseDir)
        resolveConflicts()
    }

    /// Core save against any directory — no `savesSuspended` guard, no `NSFileVersion`
    /// conflict resolution (that's specific to the real ubiquity container, hardwired to
    /// `Self.storeURL`). `save()` is the production entry point; this is the seam Tier 2
    /// multi-device tests (`SyncRelay`) use to drive a store against its own private temp
    /// directory instead of `AssetStore.baseDir`.
    func save(to root: URL) {
        // StoreFileLayout.writeLocked creates Definitions/Assets/Activity itself but not
        // Photos — AssetStore.baseDir's resolution path creates it as a side effect
        // (createStoreSubdirectories), which a caller-supplied root bypasses entirely.
        try? FileManager.default.createDirectory(
            at: root.appendingPathComponent("Photos", isDirectory: true), withIntermediateDirectories: true)
        let snap = buildSnapshot()
        let report = fileLayout.write(snap, baseDir: root)
        lastPersistedData = fileLayout.storeDigest
        lastSyncDate = Date()
        if !report.allDataShardsSucceeded {
            persistenceLogger.error("save: one or more shards failed to write — store.json was left pointing at the previous, still-consistent tree")
        }
    }

    /// Resolves conflicts across every shard — manifest, `Definitions/*.json`, and
    /// `Assets/*.json` — via `resolveShardConflicts(baseDir:source:)` (`ConflictResolution.swift`).
    private func resolveConflicts() {
        guard Self.baseDirOverride == nil else { return }
        resolveShardConflicts(baseDir: Self.baseDir, source: FileVersionConflictSource())
    }

    /// Starts watching the iCloud ubiquity container for remote changes pushed by other devices.
    /// Call once from the app's `.task` modifier after launch. No-op when `iCloudSyncEnabled` is false.
    func startCloudMonitor() {
        guard Self.iCloudSyncEnabled else { return }
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "%K LIKE '*.json'", NSMetadataItemFSNameKey)
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]

        let handleEvent: (Notification) -> Void = { [weak self] notification in
            self?.handleCloudMonitorNotification(notification, query: query)
        }
        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate, object: query, queue: .main, using: handleEvent
        )
        // Phase 1 step 5 / Phase 5a: resolve savesSuspended when gather completes.
        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main, using: handleEvent
        )
        query.start()
        cloudQuery = query
    }

    private func handleCloudMonitorNotification(_ notification: Notification, query: NSMetadataQuery) {
        let isGather = notification.name == .NSMetadataQueryDidFinishGathering
        query.disableUpdates()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.fileLayout.read(baseDir: Self.baseDir)
            DispatchQueue.main.async {
                defer { query.enableUpdates() }
                if isGather && query.resultCount == 0 {
                    // Gather finished with no store in cloud — seeds are safe to persist.
                    if self.savesSuspended {
                        self.savesSuspended = false
                        self.markDirty()
                    }
                    return
                }
                // Upload-progress events echo our own saves back at us. Applying an echo (or
                // any state we already persisted) would clobber in-memory mutations made since
                // that write — only foreign content may apply. storeDigest is a digest of every
                // shard's digest (see StoreFileLayout), so this is the same echo check the
                // single-file version did, just keyed on the whole tree instead of one file.
                guard let result, self.fileLayout.storeDigest != self.lastPersistedData else { return }
                self.lastPersistedData = self.fileLayout.storeDigest
                let disk = self.migrate(result.snapshot)

                guard self.hasAuthoritativeLocalState else {
                    // We've only ever seeded, never persisted or confirmed the cloud was
                    // empty. Merging here would union our randomly-id'd seed data (categories,
                    // sample assets — see BuiltInTypes) into the peer's real store instead of
                    // being cleanly replaced by it, permanently duplicating it on every device.
                    self.applySnapshot(disk)
                    self.savesSuspended = false
                    self.lastSyncDate = Date()
                    self.resolveConflicts()
                    return
                }

                let cutoff = Date().addingTimeInterval(-TimeInterval(AppPreference.DaysToRetainDeletedItems) * 86_400)
                let merged = SnapshotReconciler.merge(self.buildSnapshot(), disk, options: .init(purgeCutoff: cutoff))
                self.applyInPlace(merged)
                self.savesSuspended = false
                self.lastSyncDate = Date()
                self.resolveConflicts()
                // The merge may have pulled in content the peer doesn't have yet, or dropped a
                // tombstone that expired locally but not there — write back so it reaches
                // them. Content-diffed per shard, so an already-converged state costs nothing.
                self.markDirty()
            }
        }
    }

    // MARK: - Migration

    private func migrate(_ s: StoreSnapshotDTO) -> StoreSnapshotDTO {
        // v1 → v2 added modifyDate/isDeleted/deletedAt to Event/Transaction/Photo; the fields
        // are optional with a decode-time fallback (see event/transaction/photo(from:)), so no
        // transform is needed here.
        // v2 → v3 added isDeleted/deletedAt to AssetPropertyDTO (custom properties); same
        // optional-with-fallback treatment in assetProperty(from:), no transform needed.
        // v3 → v4 added modifyDate to CategoryDTO/ComboListDTO/CompositeTypeDTO and
        // headModifyDate to AssetDTO — same optional-with-fallback treatment inline in
        // applySnapshot/mergeSnapshot, no transform needed.
        // Future: if s.schemaVersion < 5 { var s = s; /* transform */; return s }
        return s
    }

    // MARK: - Snapshot → live objects (main thread)

    private func applySnapshot(_ snap: StoreSnapshotDTO) {
        // 1. CompositeTypeDefinition shells — fields filled in step 3
        var ctMap: [UUID: CompositeTypeDefinition] = [:]
        for dto in snap.compositeTypes {
            let ct = CompositeTypeDefinition(id: dto.id, name: dto.name, labelHint: dto.labelHint,
                                             modifyDate: dto.modifyDate ?? .distantPast)
            ctMap[dto.id] = ct
        }

        // 2. ComboListDefinition map
        var clMap: [UUID: ComboListDefinition] = [:]
        for dto in snap.comboLists {
            clMap[dto.id] = ComboListDefinition(
                id: dto.id, name: dto.name,
                systemOptions: dto.systemOptions, userOptions: dto.userOptions,
                isUserExtensible: dto.isUserExtensible, modifyDate: dto.modifyDate ?? .distantPast
            )
        }

        // 3. Fill composite type fields (may cross-reference other composites in ctMap)
        for dto in snap.compositeTypes {
            guard let ct = ctMap[dto.id] else { continue }
            ct.fields = dto.fields.compactMap { propertyDefinition(from: $0, ctMap: ctMap, clMap: clMap) }
        }

        // 4. Categories
        var catMap: [UUID: AssetCategory] = [:]
        for dto in snap.categories {
            let templates = dto.propertyTemplates.compactMap {
                assetProperty(from: $0, ctMap: ctMap, clMap: clMap, fallbackModifyDate: .distantPast)
            }
            let cat = AssetCategory(id: dto.id, name: dto.name, iconName: dto.iconName, propertyTemplates: templates,
                                    modifyDate: dto.modifyDate ?? .distantPast)
            cat.isDeleted = dto.isDeleted
            cat.deletedAt = dto.deletedAt
            catMap[dto.id] = cat
        }

        // 5. Assets — no hierarchy links yet; photo imageData/thumbnailData start nil (lazy load)
        // A dangling categoryID (category hard-deleted while its assets lived on) must never
        // cost the user an asset: resurrect a placeholder category instead of dropping. A
        // purged asset's placeholder is the one exception — nothing displays a purged
        // tombstone, so its placeholder is reused across every purged asset referencing the
        // same missing category but never committed to `catMap`/`categories`, unlike the
        // live-asset case which upserts the placeholder so the asset is never lost.
        var assetMap: [UUID: Asset] = [:]
        var purgedPlaceholders: [UUID: AssetCategory] = [:]
        func recoverCategory(_ categoryID: UUID, isPurged: Bool) -> AssetCategory {
            if let existing = catMap[categoryID] { return existing }
            if isPurged {
                if let existing = purgedPlaceholders[categoryID] { return existing }
                let placeholder = AssetCategory(id: categoryID, name: "Recovered",
                                                iconName: "questionmark.folder", propertyTemplates: [])
                purgedPlaceholders[categoryID] = placeholder
                return placeholder
            }
            let placeholder = AssetCategory(id: categoryID, name: "Recovered",
                                            iconName: "questionmark.folder", propertyTemplates: [])
            catMap[categoryID] = placeholder
            return placeholder
        }
        for dto in snap.assets {
            let isPurged = dto.isPurged ?? false
            let cat = recoverCategory(dto.categoryID, isPurged: isPurged)
            let asset = Asset(
                id: dto.id, name: dto.name, category: cat,
                baseProperties: dto.baseProperties.compactMap {
                    assetProperty(from: $0, ctMap: ctMap, clMap: clMap, fallbackModifyDate: dto.modifiedDate)
                },
                customProperties: dto.customProperties.compactMap {
                    assetProperty(from: $0, ctMap: ctMap, clMap: clMap, fallbackModifyDate: dto.modifiedDate)
                },
                parentID: dto.parentID, createdDate: dto.createdDate, modifiedDate: dto.modifiedDate,
                parentageModifyDate: dto.parentageModifyDate ?? dto.createdDate,
                headModifyDate: dto.headModifyDate ?? dto.modifiedDate
            )
            asset.isDeleted = dto.isDeleted
            asset.deletedAt = dto.deletedAt
            asset.isPurged = isPurged
            asset.photos = dto.photos.map { photo(from: $0) }
            asset.events = dto.events.map { event(from: $0, fallbackModifyDate: dto.modifiedDate) }
            asset.transactions = dto.transactions.map { transaction(from: $0, fallbackModifyDate: dto.modifiedDate) }
            assetMap[asset.id] = asset
        }

        // 6. Wire parent→child hierarchy — rehydration, not a move: keep the stored timestamps.
        for dto in snap.assets {
            guard let asset = assetMap[dto.id],
                  let parentID = dto.parentID,
                  let parent = assetMap[parentID] else { continue }
            parent._addChild(asset, stampParentage: false)
        }

        // 7. Activity log
        let log: [ActivityLogEntry] = snap.activityLog.compactMap { dto in
            guard let kind = LoggedRecordKind(rawValue: dto.kind) else { return nil }
            return ActivityLogEntry(recordID: dto.recordID, kind: kind,
                                    owningAssetID: dto.owningAssetID, id: dto.id, timestamp: dto.timestamp)
        }

        // 8. Commit to store
        _applyLoaded(compositeTypes: ctMap, comboLists: clMap, categories: catMap, assets: assetMap, activityLog: log)

        // One-time migration: backgroundTheme moved from the synced manifest to UserDefaults
        // (schema v4+). If this device has never set its own value, adopt whatever this
        // store's manifest carried rather than silently resetting to the default theme.
        if UserDefaults.standard.string(forKey: Self.backgroundThemeDefaultsKey) == nil,
           let theme = BackgroundTheme(rawValue: snap.backgroundTheme) {
            backgroundTheme = theme
        }
    }

    // MARK: - Snapshot merge (additive import)

    /// Additively merges an incoming snapshot into the live store. Local always wins:
    /// nothing already present is overwritten, re-parented, or removed. Returns the ids
    /// of photos whose files the caller should materialize on disk (new or repaired).
    ///
    /// Must run synchronously on the main thread — it mutates live `@Observable` objects
    /// before committing them via `_applyLoaded`.
    private func mergeSnapshot(_ snap: StoreSnapshotDTO) -> Set<UUID> {
        // 1. Composite type shells (local ∪ incoming) — fields filled in step 3.
        var ctMap = compositeTypes
        var newCompositeIDs: Set<UUID> = []
        for dto in snap.compositeTypes where ctMap[dto.id] == nil {
            ctMap[dto.id] = CompositeTypeDefinition(id: dto.id, name: dto.name, labelHint: dto.labelHint,
                                                     modifyDate: dto.modifyDate ?? .distantPast)
            newCompositeIDs.insert(dto.id)
        }

        // 2. Combo lists (local ∪ incoming). On collision, union incoming userOptions —
        // systemOptions is private(set) on ComboListDefinition and not writable here anyway.
        var clMap = comboListDefinitions
        for dto in snap.comboLists {
            if let existing = clMap[dto.id] {
                let missing = dto.userOptions.filter { !existing.allOptions.contains($0) }
                if !missing.isEmpty { existing.userOptions.append(contentsOf: missing) }
            } else {
                clMap[dto.id] = ComboListDefinition(
                    id: dto.id, name: dto.name,
                    systemOptions: dto.systemOptions, userOptions: dto.userOptions,
                    isUserExtensible: dto.isUserExtensible, modifyDate: dto.modifyDate ?? .distantPast
                )
            }
        }

        // 3. Fill fields on newly created composite types only. Merging a field into an
        // existing local composite type would break `validate`'s required-field check for
        // every existing value of that type.
        for dto in snap.compositeTypes where newCompositeIDs.contains(dto.id) {
            ctMap[dto.id]?.fields = dto.fields.compactMap { propertyDefinition(from: $0, ctMap: ctMap, clMap: clMap) }
        }

        // 4. Categories (local ∪ incoming). Incoming soft-deleted categories are skipped
        // here; a surviving asset that still needs one is recovered in step 5.
        var catMap = categories
        let incomingCategoriesByID = Dictionary(snap.categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for dto in snap.categories where !dto.isDeleted {
            if let existing = catMap[dto.id] {
                // A live incoming record resurrects a locally-trashed one — the one place
                // the merge deliberately overwrites local state rather than only adding.
                if existing.isDeleted {
                    existing.isDeleted = false
                    existing.deletedAt = nil
                }
                mergeTemplates(into: existing, from: dto, ctMap: ctMap, clMap: clMap)
            } else {
                let templates = dto.propertyTemplates.compactMap {
                    assetProperty(from: $0, ctMap: ctMap, clMap: clMap, fallbackModifyDate: .distantPast)
                }
                catMap[dto.id] = AssetCategory(id: dto.id, name: dto.name, iconName: dto.iconName,
                                               propertyTemplates: templates, modifyDate: dto.modifyDate ?? .distantPast)
            }
        }

        // 5. Assets (local ∪ incoming). Incoming soft-deleted assets are skipped.
        var assetMap = assets
        var newAssets: [(Asset, AssetDTO)] = []
        var undeletedAssets: [Asset] = []
        var photoIDsToMaterialize: Set<UUID> = []
        var recoveredPlaceholders: [UUID: AssetCategory] = [:]

        for dto in snap.assets where !dto.isDeleted {
            if let local = assetMap[dto.id] {
                var changed = mergeAsset(local, from: dto, ctMap: ctMap, clMap: clMap)
                // A live incoming record resurrects a locally-trashed one — the one place
                // the merge deliberately overwrites local state rather than only adding.
                if local.isDeleted {
                    local.isDeleted = false
                    local.deletedAt = nil
                    // Only the resurrection touches a head field (the tombstone) — an
                    // appended property/event/photo is not a head change and must not bump
                    // this, or a later cloud sync could misread it as a recent rename.
                    local.headModifyDate = Date()
                    undeletedAssets.append(local)
                    changed += 1
                }
                if changed > 0 { local.modifiedDate = Date() }
                for p in dto.photos where !(p.isDeleted ?? false) { photoIDsToMaterialize.insert(p.id) }
                continue
            }

            let cat = resolveMergeCategory(
                dto.categoryID, catMap: &catMap, incomingCategoriesByID: incomingCategoriesByID,
                recoveredPlaceholders: &recoveredPlaceholders, ctMap: ctMap, clMap: clMap
            )
            let asset = Asset(
                id: dto.id, name: dto.name, category: cat,
                baseProperties: dto.baseProperties.compactMap {
                    assetProperty(from: $0, ctMap: ctMap, clMap: clMap, fallbackModifyDate: dto.modifiedDate)
                },
                customProperties: dto.customProperties.compactMap {
                    assetProperty(from: $0, ctMap: ctMap, clMap: clMap, fallbackModifyDate: dto.modifiedDate)
                },
                parentID: dto.parentID, createdDate: dto.createdDate, modifiedDate: dto.modifiedDate,
                parentageModifyDate: dto.parentageModifyDate ?? dto.createdDate,
                headModifyDate: dto.headModifyDate ?? dto.modifiedDate
            )
            asset.photos = dto.photos.map { photo(from: $0) }
            asset.events = dto.events.map { event(from: $0, fallbackModifyDate: dto.modifiedDate) }
            asset.transactions = dto.transactions.map { transaction(from: $0, fallbackModifyDate: dto.modifiedDate) }
            assetMap[asset.id] = asset
            newAssets.append((asset, dto))
            for p in dto.photos where !(p.isDeleted ?? false) { photoIDsToMaterialize.insert(p.id) }
        }

        // 6. Wire parent→child hierarchy for newly added assets only. Existing local
        // assets are never re-parented — their incoming parentID is ignored outright.
        // Runs after step 5 so a resurrected asset already reads as live here.
        mergeHierarchy(newAssets: newAssets, assetMap: assetMap)
        detachAcrossDeletionBoundary(undeletedAssets)

        // 7. Activity log — append incoming entries not already present, dropping any
        // whose referenced asset didn't survive the merge, then restore chronological order.
        var log = activityLog
        var mergedLogIDs = Set(log.map(\.id))
        for dto in snap.activityLog {
            guard !mergedLogIDs.contains(dto.id), let kind = LoggedRecordKind(rawValue: dto.kind) else { continue }
            let referenced = dto.owningAssetID ?? (kind == .asset ? dto.recordID : nil)
            if let aid = referenced, assetMap[aid] == nil { continue }
            log.append(ActivityLogEntry(recordID: dto.recordID, kind: kind,
                                        owningAssetID: dto.owningAssetID, id: dto.id, timestamp: dto.timestamp))
            mergedLogIDs.insert(dto.id)
        }
        log.sort { $0.timestamp < $1.timestamp }

        // 8. Commit. backgroundTheme is UserDefaults-backed, not part of this commit at all.
        _applyLoaded(compositeTypes: ctMap, comboLists: clMap, categories: catMap, assets: assetMap, activityLog: log)
        notificationScheduler?.requestResync(assets: allAssets)

        return photoIDsToMaterialize
    }

    /// Resolves the category for a newly merged asset, preserving the guarantee that an
    /// asset is never dropped for a missing category. Preference order: an already-merged
    /// live category; a placeholder already created for this dangling id; the incoming
    /// snapshot's own (soft-deleted) copy of the category, recovered with `isDeleted`
    /// preserved so the asset keeps its real name/icon; finally a generic "Recovered" shell.
    private func resolveMergeCategory(
        _ categoryID: UUID,
        catMap: inout [UUID: AssetCategory],
        incomingCategoriesByID: [UUID: CategoryDTO],
        recoveredPlaceholders: inout [UUID: AssetCategory],
        ctMap: [UUID: CompositeTypeDefinition],
        clMap: [UUID: ComboListDefinition]
    ) -> AssetCategory {
        if let existing = catMap[categoryID] { return existing }
        if let placeholder = recoveredPlaceholders[categoryID] { return placeholder }
        if let catDTO = incomingCategoriesByID[categoryID], catDTO.isDeleted {
            let templates = catDTO.propertyTemplates.compactMap {
                assetProperty(from: $0, ctMap: ctMap, clMap: clMap, fallbackModifyDate: .distantPast)
            }
            let cat = AssetCategory(id: catDTO.id, name: catDTO.name, iconName: catDTO.iconName, propertyTemplates: templates,
                                    modifyDate: catDTO.modifyDate ?? .distantPast)
            cat.isDeleted = true
            cat.deletedAt = catDTO.deletedAt
            catMap[categoryID] = cat
            return cat
        }
        let placeholder = AssetCategory(id: categoryID, name: "Recovered",
                                        iconName: "questionmark.folder", propertyTemplates: [])
        recoveredPlaceholders[categoryID] = placeholder
        catMap[categoryID] = placeholder
        return placeholder
    }

    /// Appends incoming property templates the category is missing. A template is
    /// considered present if either its own id or its embedded definition id already
    /// appears in `cat.propertyTemplates` — `definition.id` is what `Asset.value(for:)`
    /// and friends key on, so a duplicate would make the second property unreachable.
    private func mergeTemplates(
        into cat: AssetCategory,
        from dto: CategoryDTO,
        ctMap: [UUID: CompositeTypeDefinition],
        clMap: [UUID: ComboListDefinition]
    ) {
        var seenPropIDs = Set(cat.propertyTemplates.map(\.id))
        var seenDefIDs = Set(cat.propertyTemplates.map(\.definition.id))
        appendMissingProperties(
            dto.propertyTemplates, into: &cat.propertyTemplates,
            seenPropIDs: &seenPropIDs, seenDefIDs: &seenDefIDs, ctMap: ctMap, clMap: clMap,
            fallbackModifyDate: .distantPast
        )
    }

    /// Additively merges one incoming asset into its matched local asset: appends missing
    /// base/custom properties (deduped by id ∪ definition.id across both collections, since
    /// `setPropertyValue` searches base then custom), events, transactions, and photo
    /// metadata. Never touches name, dates, category, or existing property values.
    /// Returns the number of records appended.
    @discardableResult
    private func mergeAsset(
        _ local: Asset,
        from dto: AssetDTO,
        ctMap: [UUID: CompositeTypeDefinition],
        clMap: [UUID: ComboListDefinition]
    ) -> Int {
        var added = 0
        // Seen-sets are built from the raw arrays, tombstoned or not, so a locally deleted
        // custom property blocks the peer's still-live copy from being re-added by
        // appendMissingProperties below — this is what makes the delete stick across a merge.
        var seenPropIDs = Set(local.baseProperties.map(\.id) + local.customProperties.map(\.id))
        var seenDefIDs = Set(local.baseProperties.map(\.definition.id) + local.customProperties.map(\.definition.id))

        // Base properties are stamped from the asset's own category template, so a foreign
        // categoryID (only reachable via a hand-edited file) means these definitions belong
        // to a different template. Skip just them — custom properties, events, transactions
        // and photos are category-independent and still merge normally.
        if local.category.id == dto.categoryID {
            added += appendMissingProperties(
                dto.baseProperties, into: &local.baseProperties,
                seenPropIDs: &seenPropIDs, seenDefIDs: &seenDefIDs, ctMap: ctMap, clMap: clMap,
                fallbackModifyDate: dto.modifiedDate
            )
        }
        added += appendMissingProperties(
            dto.customProperties, into: &local.customProperties,
            seenPropIDs: &seenPropIDs, seenDefIDs: &seenDefIDs, ctMap: ctMap, clMap: clMap,
            fallbackModifyDate: dto.modifiedDate
        )

        // Records already present locally are left untouched, tombstone or not: an incoming
        // tombstone for a record still live here does NOT propagate the delete. Deliberate,
        // not a gap — this is the additive/local-wins import path (`importJSON`), which must
        // never delete something the user has since recreated. Last-writer-wins on
        // modifyDate/headModifyDate is `SnapshotReconciler`'s job, used by the separate cloud
        // sync path (`applyInPlace`), not this one.
        let seenEventIDs = Set(local.events.map(\.id))
        for edto in dto.events where !seenEventIDs.contains(edto.id) {
            local.events.append(event(from: edto, fallbackModifyDate: dto.modifiedDate))
            added += 1
        }

        let seenTxnIDs = Set(local.transactions.map(\.id))
        for tdto in dto.transactions where !seenTxnIDs.contains(tdto.id) {
            local.transactions.append(transaction(from: tdto, fallbackModifyDate: dto.modifiedDate))
            added += 1
        }

        let seenPhotoIDs = Set(local.photos.map(\.id))
        for pdto in dto.photos where !seenPhotoIDs.contains(pdto.id) {
            local.photos.append(photo(from: pdto))
            added += 1
        }

        return added
    }

    /// Appends DTOs from `dtos` into `target` that aren't already excluded by id or
    /// definition id, assigning each a `sortOrder` strictly after the target's current
    /// maximum so merged rows never tie with (and always sort after) existing ones.
    /// Updates the seen-sets as it goes so duplicates *within* `dtos` itself only land once.
    /// `sortOrder` is positional and gets renormalized; `modifyDate` is a factual record of
    /// when the other device edited the field and is carried over untouched.
    @discardableResult
    private func appendMissingProperties(
        _ dtos: [AssetPropertyDTO],
        into target: inout [AssetProperty],
        seenPropIDs: inout Set<UUID>,
        seenDefIDs: inout Set<UUID>,
        ctMap: [UUID: CompositeTypeDefinition],
        clMap: [UUID: ComboListDefinition],
        fallbackModifyDate: Date
    ) -> Int {
        var next = (target.map(\.sortOrder).max() ?? -AssetProperty.sortOrderIncrement) + AssetProperty.sortOrderIncrement
        var added = 0
        for pdto in dtos.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            guard !seenPropIDs.contains(pdto.id), !seenDefIDs.contains(pdto.definition.id),
                  let prop = assetProperty(from: pdto, ctMap: ctMap, clMap: clMap,
                                           fallbackModifyDate: fallbackModifyDate) else { continue }
            prop.sortOrder = next
            next += AssetProperty.sortOrderIncrement
            target.append(prop)
            seenPropIDs.insert(prop.id)
            seenDefIDs.insert(prop.definition.id)
            added += 1
        }
        return added
    }

    /// Re-establishes the invariant `softDeleteAsset` maintains — a soft-deleted subtree is
    /// never linked to a live asset in either direction — for the assets this merge
    /// resurrected. `softDeleteAsset` marks a whole subtree, but an incoming file can revive
    /// only part of it, and either leftover breaks the UI: a still-deleted child of a live
    /// parent is filtered out of the asset tree yet isn't `isRoot`, so `DeletedAssetsView`
    /// won't list it either; a revived child of a still-deleted parent isn't `isRoot`, so it
    /// never appears in `rootAssets`. Detaching makes each side a root of its own.
    ///
    /// Must run after every undelete in the merge, not inline with them — detaching a child
    /// that a later iteration was about to revive would orphan it needlessly.
    private func detachAcrossDeletionBoundary(_ undeleted: [Asset]) {
        for asset in undeleted {
            if let parent = asset.parent, parent.isDeleted {
                parent._removeChild(asset)
            }
            for child in Array(asset.children) where child.isDeleted {
                asset._removeChild(child)
            }
        }
    }

    /// Wires parent→child links for newly merged assets only. Existing local assets are
    /// never touched. A new asset falls back to being a root (`parentID = nil`, not left
    /// dangling) when its incoming parent is missing, itself, soft-deleted, or would form
    /// a cycle — a cycle is not just bad data, `Asset.descendants` and
    /// `AssetDetailView.anchorIndex` are unbounded walks that would hang on one.
    private func mergeHierarchy(newAssets: [(Asset, AssetDTO)], assetMap: [UUID: Asset]) {
        let newAssetIDs = Set(newAssets.map { $0.0.id })
        var pendingParent: [UUID: UUID] = [:]
        for (asset, dto) in newAssets {
            if let pid = dto.parentID, newAssetIDs.contains(pid) {
                pendingParent[asset.id] = pid
            }
        }

        func wouldCycle(child: UUID, startingAt parent: UUID) -> Bool {
            var visited: Set<UUID> = [child]
            var cursor: UUID? = parent
            var steps = 0
            while let current = cursor {
                if visited.contains(current) { return true }
                visited.insert(current)
                steps += 1
                if steps > assetMap.count { return true }
                cursor = assetMap[current]?.parent?.id ?? pendingParent[current]
            }
            return false
        }

        for (asset, dto) in newAssets {
            guard let parentID = dto.parentID, parentID != asset.id,
                  let parent = assetMap[parentID],
                  !parent.isDeleted,
                  !wouldCycle(child: asset.id, startingAt: parentID)
            else {
                asset.parentID = nil
                continue
            }
            // Wiring a record that already carried this link elsewhere — keep its own timestamp.
            parent._addChild(asset, stampParentage: false)
        }
    }

    // MARK: - Live objects → snapshot

    /// Internal (not private): the Tier 1 in-process multi-device test harness relays
    /// snapshots directly between two `AssetStore` instances via `buildSnapshot()` →
    /// `SnapshotReconciler.merge` → `applyInPlace`, with no file I/O involved at all.
    func buildSnapshot(includePhotoData: Bool = false) -> StoreSnapshotDTO {
        StoreSnapshotDTO(
            schemaVersion: storeSchemaVersion,
            compositeTypes: compositeTypes.values.map { ct in
                CompositeTypeDTO(id: ct.id, name: ct.name,
                                 fields: ct.fields.map { propertyDefinitionDTO($0) },
                                 labelHint: ct.labelHint, modifyDate: ct.modifyDate)
            },
            comboLists: comboListDefinitions.values.map { cl in
                ComboListDTO(id: cl.id, name: cl.name, systemOptions: cl.systemOptions,
                             userOptions: cl.userOptions, isUserExtensible: cl.isUserExtensible,
                             modifyDate: cl.modifyDate)
            },
            categories: categories.values.map { cat in
                CategoryDTO(id: cat.id, name: cat.name, iconName: cat.iconName,
                            propertyTemplates: cat.propertyTemplates.map { assetPropertyDTO($0) },
                            isDeleted: cat.isDeleted, deletedAt: cat.deletedAt, modifyDate: cat.modifyDate)
            },
            assets: assets.values.map { asset in
                AssetDTO(
                    id: asset.id, name: asset.name, categoryID: asset.category.id,
                    baseProperties: asset.baseProperties.map { assetPropertyDTO($0) },
                    customProperties: asset.customProperties.map { assetPropertyDTO($0) },
                    photos: asset.photos.map { photoDTO($0, includeData: includePhotoData) },
                    events: asset.events.map { eventDTO($0) },
                    transactions: asset.transactions.map { transactionDTO($0) },
                    parentID: asset.parentID, isDeleted: asset.isDeleted, deletedAt: asset.deletedAt,
                    createdDate: asset.createdDate, modifiedDate: asset.modifiedDate,
                    parentageModifyDate: asset.parentageModifyDate, headModifyDate: asset.headModifyDate,
                    isPurged: asset.isPurged
                )
            },
            activityLog: activityLog.map {
                ActivityLogDTO(id: $0.id, recordID: $0.recordID, kind: $0.kind.rawValue,
                               owningAssetID: $0.owningAssetID, timestamp: $0.timestamp)
            },
            // A fixed placeholder, not the live per-device value: writing this device's own
            // backgroundTheme here would mean two devices with different themes could never
            // converge on this field — each save would carry its own value, look like a
            // genuine foreign change to the other, and trigger another round-trip write,
            // forever. The DTO field only exists for backward file-format compatibility and
            // the one-time migration read in applySnapshot; it is never authoritative once
            // that migration has run once on this device (see backgroundTheme's doc comment).
            backgroundTheme: BackgroundTheme.mist.rawValue
        )
    }

    // MARK: - DTO → live object helpers

    private func resolvePropertyType(
        _ dto: PropertyTypeDTO,
        ctMap: [UUID: CompositeTypeDefinition],
        clMap: [UUID: ComboListDefinition]
    ) -> PropertyType? {
        switch dto.kind {
        case .basic:     return dto.basicType.map { .basic($0) }
        case .composite: return dto.typeID.flatMap { ctMap[$0] }.map { .composite($0) }
        case .comboList: return dto.typeID.flatMap { clMap[$0] }.map { .comboList($0) }
        }
    }

    private func propertyDefinition(
        from dto: PropertyDefinitionDTO,
        ctMap: [UUID: CompositeTypeDefinition],
        clMap: [UUID: ComboListDefinition]
    ) -> PropertyDefinition? {
        guard let type = resolvePropertyType(dto.type, ctMap: ctMap, clMap: clMap) else { return nil }
        return PropertyDefinition(id: dto.id, name: dto.name, type: type, isRequired: dto.isRequired)
    }

    private func storedValue(from dto: StoredValueDTO) -> StoredValue {
        switch dto {
        case .text(let s):      return .text(s)
        case .number(let n):    return .number(n)
        case .currency(let s):  return .currency(Decimal(string: s) ?? 0)
        case .date(let d):      return .date(d)
        case .contact(let s):   return .contact(s)
        case .data(let d):      return .data(d)
        case .composite(let m): return .composite(m.mapValues { storedValue(from: $0) })
        }
    }

    /// `fallbackModifyDate` stands in for files written before per-property timestamps existed:
    /// the owning asset's `modifiedDate` for asset properties, `.distantPast` for category
    /// templates (AssetCategory carries no date of its own).
    private func assetProperty(
        from dto: AssetPropertyDTO,
        ctMap: [UUID: CompositeTypeDefinition],
        clMap: [UUID: ComboListDefinition],
        fallbackModifyDate: Date
    ) -> AssetProperty? {
        guard let def = propertyDefinition(from: dto.definition, ctMap: ctMap, clMap: clMap) else { return nil }
        let prop = AssetProperty(id: dto.id, definition: def,
                                 value: dto.value.map { storedValue(from: $0) },
                                 sortOrder: dto.sortOrder,
                                 modifyDate: dto.modifyDate ?? fallbackModifyDate)
        prop.isDeleted = dto.isDeleted ?? false
        prop.deletedAt = dto.deletedAt
        return prop
    }

    /// `fallbackModifyDate` stands in for files written before inline records carried
    /// tombstones: the owning asset's `modifiedDate`. `Event.date` is the scheduled day and
    /// may be in the future, so it is never used as the timestamp fallback.
    private func event(from dto: EventDTO, fallbackModifyDate: Date) -> Event {
        let event = Event(id: dto.id, title: dto.title, date: dto.date, notes: dto.notes,
                          recurrence: dto.recurrence.flatMap(RecurrenceInterval.init),
                          modifyDate: dto.modifyDate ?? fallbackModifyDate)
        event.isDeleted = dto.isDeleted ?? false
        event.deletedAt = dto.deletedAt
        return event
    }

    /// See `event(from:fallbackModifyDate:)` — same fallback rule.
    private func transaction(from dto: TransactionDTO, fallbackModifyDate: Date) -> Transaction {
        let txn = Transaction(id: dto.id, details: dto.details,
                              amount: Decimal(string: dto.amount) ?? 0,
                              date: dto.date, kind: TransactionKind(rawValue: dto.kind) ?? .expense,
                              payeeContactID: dto.payeeContactID, notes: dto.notes,
                              recurrence: dto.recurrence.flatMap(RecurrenceInterval.init),
                              modifyDate: dto.modifyDate ?? fallbackModifyDate)
        txn.isDeleted = dto.isDeleted ?? false
        txn.deletedAt = dto.deletedAt
        return txn
    }

    /// `imageData`/`thumbnailData` are omitted so they default to nil — views populate them
    /// lazily via `PhotoStorage`. A photo carries its own creation instant, so unlike events
    /// and transactions its modify-date fallback needs nothing from the owning asset.
    private func photo(from dto: PhotoDTO) -> Photo {
        let photo = Photo(id: dto.id, caption: dto.caption, addedDate: dto.addedDate,
                          modifyDate: dto.modifyDate ?? dto.addedDate)
        photo.isDeleted = dto.isDeleted ?? false
        photo.deletedAt = dto.deletedAt
        return photo
    }

    // MARK: - Live object → DTO helpers

    private func propertyTypeDTO(_ type: PropertyType) -> PropertyTypeDTO {
        switch type {
        case .basic(let bt):     return PropertyTypeDTO(kind: .basic,     basicType: bt,  typeID: nil)
        case .composite(let ct): return PropertyTypeDTO(kind: .composite, basicType: nil, typeID: ct.id)
        case .comboList(let cl): return PropertyTypeDTO(kind: .comboList, basicType: nil, typeID: cl.id)
        }
    }

    private func propertyDefinitionDTO(_ def: PropertyDefinition) -> PropertyDefinitionDTO {
        PropertyDefinitionDTO(id: def.id, name: def.name,
                              type: propertyTypeDTO(def.type), isRequired: def.isRequired)
    }

    private func storedValueDTO(_ value: StoredValue) -> StoredValueDTO {
        switch value {
        case .text(let s):      return .text(s)
        case .number(let n):    return .number(n)
        case .currency(let d):  return .currency(d.description)
        case .date(let d):      return .date(d)
        case .contact(let s):   return .contact(s)
        case .data(let d):      return .data(d)
        case .composite(let m): return .composite(m.mapValues { storedValueDTO($0) })
        }
    }

    private func assetPropertyDTO(_ prop: AssetProperty) -> AssetPropertyDTO {
        AssetPropertyDTO(id: prop.id, definition: propertyDefinitionDTO(prop.definition),
                         value: prop.value.map { storedValueDTO($0) }, sortOrder: prop.sortOrder,
                         modifyDate: prop.modifyDate, isDeleted: prop.isDeleted, deletedAt: prop.deletedAt)
    }

    private func eventDTO(_ e: Event) -> EventDTO {
        EventDTO(id: e.id, title: e.title, date: e.date, notes: e.notes,
                 recurrence: e.recurrence?.rawValue,
                 modifyDate: e.modifyDate, isDeleted: e.isDeleted, deletedAt: e.deletedAt)
    }

    private func transactionDTO(_ t: Transaction) -> TransactionDTO {
        TransactionDTO(id: t.id, details: t.details, amount: t.amount.description,
                       date: t.date, kind: t.kind.rawValue, payeeContactID: t.payeeContactID,
                       notes: t.notes, recurrence: t.recurrence?.rawValue,
                       modifyDate: t.modifyDate, isDeleted: t.isDeleted, deletedAt: t.deletedAt)
    }

    /// A tombstoned photo's bytes are never embedded in an export — the peer is being told to
    /// delete the record, not to recreate the image.
    private func photoDTO(_ p: Photo, includeData: Bool) -> PhotoDTO {
        let embed = includeData && !p.isDeleted
        return PhotoDTO(id: p.id, caption: p.caption, addedDate: p.addedDate,
                        fullImage: embed ? PhotoStorage.loadFull(id: p.id) : nil,
                        thumbnail: embed ? PhotoStorage.loadThumb(id: p.id) : nil,
                        modifyDate: p.modifyDate, isDeleted: p.isDeleted, deletedAt: p.deletedAt)
    }

    // MARK: - Identity-preserving apply (cloud sync)

    /// Applies a snapshot to the live store IN PLACE — mutating existing objects by id rather
    /// than rebuilding the maps, so open SwiftUI views holding a live `Asset`/`AssetCategory`/
    /// etc. keep pointing at valid objects, and any local mutation already folded into `snap`
    /// (the caller is expected to pass `SnapshotReconciler.merge(buildSnapshot(), foreign)`)
    /// survives. Never removes an entry for absence — only `SnapshotReconciler.reap` removes
    /// records, and it already ran before this snapshot was built.
    ///
    /// Assumes `snap`'s asset hierarchy is already free of cycles and dangling references
    /// (`SnapshotReconciler.normalizeHierarchy` is a precondition, not something this redoes)
    /// and that expired tombstones are already dropped (`SnapshotReconciler.reap`). Used only
    /// by the cloud-monitor path — `load()` still uses `applySnapshot` (nothing live to
    /// preserve at launch) and `importJSON` still uses `mergeSnapshot` (its own additive,
    /// local-wins semantics, deliberately different from sync's last-writer-wins).
    func applyInPlace(_ snap: StoreSnapshotDTO) {
        // 1. Composite type shells — mutate existing, collect new for insertion. Fields filled
        // in step 3, same two-pass reason as applySnapshot: a field can reference a composite
        // type that hasn't been upserted yet.
        var newCompositeTypes: [CompositeTypeDefinition] = []
        for dto in snap.compositeTypes {
            if let existing = compositeTypes[dto.id] {
                existing.name = dto.name
                existing.labelHint = dto.labelHint
                existing.modifyDate = dto.modifyDate ?? .distantPast
            } else {
                newCompositeTypes.append(CompositeTypeDefinition(
                    id: dto.id, name: dto.name, labelHint: dto.labelHint, modifyDate: dto.modifyDate ?? .distantPast))
            }
        }
        _upsertLoaded(compositeTypes: newCompositeTypes)

        // 2. Combo lists — mutate existing, insert new. systemOptions/isUserExtensible never
        // change after creation, so only name/userOptions/modifyDate need updating in place.
        var newComboLists: [ComboListDefinition] = []
        for dto in snap.comboLists {
            if let existing = comboListDefinitions[dto.id] {
                existing.name = dto.name
                existing.userOptions = dto.userOptions
                existing.modifyDate = dto.modifyDate ?? .distantPast
            } else {
                newComboLists.append(ComboListDefinition(
                    id: dto.id, name: dto.name, systemOptions: dto.systemOptions, userOptions: dto.userOptions,
                    isUserExtensible: dto.isUserExtensible, modifyDate: dto.modifyDate ?? .distantPast))
            }
        }
        _upsertLoaded(comboLists: newComboLists)

        // 3. Fill/refresh composite type fields now that every composite type is resolvable.
        let ctMap = compositeTypes
        let clMap = comboListDefinitions
        for dto in snap.compositeTypes {
            guard let ct = ctMap[dto.id] else { continue }
            ct.fields = dto.fields.compactMap { propertyDefinition(from: $0, ctMap: ctMap, clMap: clMap) }
        }

        // 4. Categories — mutate existing header + upsert templates element-wise; insert new.
        var newCategories: [AssetCategory] = []
        for dto in snap.categories {
            if let existing = categories[dto.id] {
                existing.name = dto.name
                existing.iconName = dto.iconName
                existing.isDeleted = dto.isDeleted
                existing.deletedAt = dto.deletedAt
                existing.modifyDate = dto.modifyDate ?? .distantPast
                upsertAssetProperties(dto.propertyTemplates, into: &existing.propertyTemplates,
                                      ctMap: ctMap, clMap: clMap, fallbackModifyDate: .distantPast)
            } else {
                let templates = dto.propertyTemplates.compactMap {
                    assetProperty(from: $0, ctMap: ctMap, clMap: clMap, fallbackModifyDate: .distantPast)
                }
                let cat = AssetCategory(id: dto.id, name: dto.name, iconName: dto.iconName,
                                        propertyTemplates: templates, modifyDate: dto.modifyDate ?? .distantPast)
                cat.isDeleted = dto.isDeleted
                cat.deletedAt = dto.deletedAt
                newCategories.append(cat)
            }
        }
        _upsertLoaded(categories: newCategories)
        var catMap = categories

        // 5. Assets — mutate existing head/child-collections; insert new. A dangling
        // categoryID (same rationale as applySnapshot/mergeSnapshot) resurrects a placeholder
        // rather than dropping the asset; a placeholder is reused across every asset in this
        // batch that references the same missing category, then upserted once at the end. A
        // purged asset's placeholder is the one exception: nothing displays a purged tombstone,
        // so its placeholder is reused across purged assets sharing the missing categoryID but
        // never upserted into `categories`.
        var newAssets: [Asset] = []
        var recoveredPlaceholders: [UUID: AssetCategory] = [:]
        var purgedPlaceholders: [UUID: AssetCategory] = [:]
        func recoverCategory(_ categoryID: UUID, isPurged: Bool) -> AssetCategory {
            if let found = catMap[categoryID] { return found }
            if isPurged {
                if let existing = purgedPlaceholders[categoryID] { return existing }
                let placeholder = AssetCategory(id: categoryID, name: "Recovered",
                                                iconName: "questionmark.folder", propertyTemplates: [])
                purgedPlaceholders[categoryID] = placeholder
                return placeholder
            }
            if let existing = recoveredPlaceholders[categoryID] { return existing }
            let placeholder = AssetCategory(id: categoryID, name: "Recovered",
                                            iconName: "questionmark.folder", propertyTemplates: [])
            recoveredPlaceholders[categoryID] = placeholder
            catMap[categoryID] = placeholder
            return placeholder
        }
        for dto in snap.assets {
            let isPurged = dto.isPurged ?? false
            if let existing = assets[dto.id] {
                existing.name = dto.name
                existing.isDeleted = dto.isDeleted
                existing.deletedAt = dto.deletedAt
                existing.modifiedDate = dto.modifiedDate
                existing.headModifyDate = dto.headModifyDate ?? dto.modifiedDate
                existing.parentageModifyDate = dto.parentageModifyDate ?? dto.createdDate
                if isPurged {
                    // The merged snapshot already stripped this asset (`SnapshotReconciler.joinAsset`
                    // ran before `applyInPlace` is called) — the upsertX helpers below are
                    // additive-only unions and would never clear content this device still
                    // holds locally, so a purge replaces rather than merges.
                    purgeInPlace(existing)
                } else {
                    upsertAssetProperties(dto.baseProperties, into: &existing.baseProperties,
                                          ctMap: ctMap, clMap: clMap, fallbackModifyDate: dto.modifiedDate)
                    upsertAssetProperties(dto.customProperties, into: &existing.customProperties,
                                          ctMap: ctMap, clMap: clMap, fallbackModifyDate: dto.modifiedDate)
                    upsertPhotos(dto.photos, into: &existing.photos)
                    upsertEvents(dto.events, into: &existing.events, fallbackModifyDate: dto.modifiedDate)
                    upsertTransactions(dto.transactions, into: &existing.transactions, fallbackModifyDate: dto.modifiedDate)
                }
            } else {
                let cat = recoverCategory(dto.categoryID, isPurged: isPurged)
                let asset = Asset(
                    id: dto.id, name: dto.name, category: cat,
                    baseProperties: dto.baseProperties.compactMap {
                        assetProperty(from: $0, ctMap: ctMap, clMap: clMap, fallbackModifyDate: dto.modifiedDate)
                    },
                    customProperties: dto.customProperties.compactMap {
                        assetProperty(from: $0, ctMap: ctMap, clMap: clMap, fallbackModifyDate: dto.modifiedDate)
                    },
                    parentID: nil, createdDate: dto.createdDate, modifiedDate: dto.modifiedDate,
                    parentageModifyDate: dto.parentageModifyDate ?? dto.createdDate,
                    headModifyDate: dto.headModifyDate ?? dto.modifiedDate
                )
                asset.isDeleted = dto.isDeleted
                asset.deletedAt = dto.deletedAt
                asset.isPurged = isPurged
                asset.photos = dto.photos.map { photo(from: $0) }
                asset.events = dto.events.map { event(from: $0, fallbackModifyDate: dto.modifiedDate) }
                asset.transactions = dto.transactions.map { transaction(from: $0, fallbackModifyDate: dto.modifiedDate) }
                newAssets.append(asset)
            }
        }
        _upsertLoaded(categories: Array(recoveredPlaceholders.values), assets: newAssets)

        // 6. Hierarchy — reconcile every asset's live parent link against the merged
        // parentID, whether the asset is new (never wired) or existing (may already be
        // correctly wired, in which case this is a no-op). `snap` is assumed already
        // cycle-free, so no cycle guard is needed here, unlike `mergeHierarchy`.
        for dto in snap.assets {
            guard let live = assets[dto.id] else { continue }
            guard live.parent?.id != dto.parentID else { continue }
            if let currentParent = live.parent {
                currentParent._removeChild(live, stampParentage: false)
            }
            if let targetParentID = dto.parentID, let targetParent = assets[targetParentID] {
                targetParent._addChild(live, stampParentage: false)
            } else {
                live.parentID = dto.parentID
            }
        }

        // 7. Live/deleted boundary repair — a merge (unlike a single device's own
        // softDeleteAsset/restoreAsset, which always tombstones or restores a whole subtree
        // atomically) can leave a live asset linked to a deleted parent or a deleted asset
        // linked to a live parent, if the two sides' per-asset tombstones didn't move
        // together. Either mismatch is repaired the same way: detach, making the asset a root
        // of its own subtree — mirrors `detachAcrossDeletionBoundary`, generalized to run
        // after any tombstone change rather than only after an undelete.
        for dto in snap.assets {
            guard let live = assets[dto.id], let parent = live.parent, parent.isDeleted != live.isDeleted else { continue }
            parent._removeChild(live, stampParentage: false)
        }

        // 8. Activity log — union by id; entries are immutable, nothing to mutate in place.
        let mergedLog: [ActivityLogEntry] = snap.activityLog.compactMap { dto in
            guard let kind = LoggedRecordKind(rawValue: dto.kind) else { return nil }
            return ActivityLogEntry(recordID: dto.recordID, kind: kind,
                                    owningAssetID: dto.owningAssetID, id: dto.id, timestamp: dto.timestamp)
        }
        _upsertActivityLog(mergedLog)

        notificationScheduler?.requestResync(assets: allAssets)
    }

    private func upsertAssetProperties(
        _ dtos: [AssetPropertyDTO], into target: inout [AssetProperty],
        ctMap: [UUID: CompositeTypeDefinition], clMap: [UUID: ComboListDefinition], fallbackModifyDate: Date
    ) {
        var byID: [UUID: AssetProperty] = [:]
        for p in target { byID[p.id] = p }
        for dto in dtos {
            if let existing = byID[dto.id] {
                guard let def = propertyDefinition(from: dto.definition, ctMap: ctMap, clMap: clMap) else { continue }
                existing.definition = def
                existing.value = dto.value.map { storedValue(from: $0) }
                existing.sortOrder = dto.sortOrder
                existing.modifyDate = dto.modifyDate ?? fallbackModifyDate
                existing.isDeleted = dto.isDeleted ?? false
                existing.deletedAt = dto.deletedAt
            } else if let created = assetProperty(from: dto, ctMap: ctMap, clMap: clMap, fallbackModifyDate: fallbackModifyDate) {
                target.append(created)
                byID[created.id] = created
            }
        }
    }

    private func upsertPhotos(_ dtos: [PhotoDTO], into target: inout [Photo]) {
        var byID: [UUID: Photo] = [:]
        for p in target { byID[p.id] = p }
        for dto in dtos {
            if let existing = byID[dto.id] {
                existing.caption = dto.caption
                existing.modifyDate = dto.modifyDate ?? dto.addedDate
                existing.isDeleted = dto.isDeleted ?? false
                existing.deletedAt = dto.deletedAt
            } else {
                let created = photo(from: dto)
                target.append(created)
                byID[created.id] = created
            }
        }
    }

    private func upsertEvents(_ dtos: [EventDTO], into target: inout [Event], fallbackModifyDate: Date) {
        var byID: [UUID: Event] = [:]
        for e in target { byID[e.id] = e }
        for dto in dtos {
            if let existing = byID[dto.id] {
                existing.title = dto.title
                existing.date = dto.date
                existing.notes = dto.notes
                existing.recurrence = dto.recurrence.flatMap(RecurrenceInterval.init)
                existing.modifyDate = dto.modifyDate ?? fallbackModifyDate
                existing.isDeleted = dto.isDeleted ?? false
                existing.deletedAt = dto.deletedAt
            } else {
                let created = event(from: dto, fallbackModifyDate: fallbackModifyDate)
                target.append(created)
                byID[created.id] = created
            }
        }
    }

    private func upsertTransactions(_ dtos: [TransactionDTO], into target: inout [Transaction], fallbackModifyDate: Date) {
        var byID: [UUID: Transaction] = [:]
        for t in target { byID[t.id] = t }
        for dto in dtos {
            if let existing = byID[dto.id] {
                existing.details = dto.details
                existing.amount = Decimal(string: dto.amount) ?? 0
                existing.date = dto.date
                existing.kind = TransactionKind(rawValue: dto.kind) ?? .expense
                existing.payeeContactID = dto.payeeContactID
                existing.notes = dto.notes
                existing.recurrence = dto.recurrence.flatMap(RecurrenceInterval.init)
                existing.modifyDate = dto.modifyDate ?? fallbackModifyDate
                existing.isDeleted = dto.isDeleted ?? false
                existing.deletedAt = dto.deletedAt
            } else {
                let created = transaction(from: dto, fallbackModifyDate: fallbackModifyDate)
                target.append(created)
                byID[created.id] = created
            }
        }
    }
}
