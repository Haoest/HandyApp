import Foundation

// MARK: - Photo file storage

enum PhotoStorage {
    static func fullURL(id: UUID) -> URL {
        AssetStore.baseDir.appendingPathComponent("Photos/\(id)_full.jpg")
    }
    static func thumbURL(id: UUID) -> URL {
        AssetStore.baseDir.appendingPathComponent("Photos/\(id)_thumb.jpg")
    }

    static func save(id: UUID, imageData: Data, thumbnailData: Data) {
        try? imageData.write(to: fullURL(id: id), options: .atomic)
        try? thumbnailData.write(to: thumbURL(id: id), options: .atomic)
    }

    private static func read(_ url: URL) -> Data? {
        if let data = try? Data(contentsOf: url) { return data }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        return nil
    }

    static func loadFull(id: UUID) -> Data? { read(fullURL(id: id)) }
    static func loadThumb(id: UUID) -> Data? { read(thumbURL(id: id)) }

    static func delete(id: UUID) {
        try? FileManager.default.removeItem(at: fullURL(id: id))
        try? FileManager.default.removeItem(at: thumbURL(id: id))
    }
}

// MARK: - AssetStore persistence

extension AssetStore {

    // MARK: - URL resolution

    /// Master switch for iCloud document sync of the store. While false, all store files
    /// live in local Documents and no ubiquity-container access happens. iCloud Backup of
    /// the local Documents directory is unaffected. Flip to true to re-enable sync.
    static let iCloudSyncEnabled = false

    /// Tests only: points the store at a private temp directory.
    static var baseDirOverride: URL?

    static var baseDir: URL {
        if let override = baseDirOverride {
            try? FileManager.default.createDirectory(
                at: override.appendingPathComponent("Photos", isDirectory: true),
                withIntermediateDirectories: true)
            return override
        }
        return resolvedBaseDir
    }

    /// Base directory for all store files. When `iCloudSyncEnabled` is true and the
    /// ubiquity container is available, uses the iCloud Documents directory (migrating
    /// any existing local store on first run). Otherwise uses local Documents.
    /// Resolved once per launch — `url(forUbiquityContainerIdentifier:)` can block.
    /// Creates the Photos/ subdirectory as a side effect.
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
        let photosDir = dir.appendingPathComponent("Photos", isDirectory: true)
        try? fm.createDirectory(at: photosDir, withIntermediateDirectories: true)
        return dir
    }()

    /// One-time move of pre-iCloud data into the ubiquity container. Without this, the first
    /// launch after enabling iCloud would find an empty container, reseed sample data, and the
    /// user's real store would appear wiped. Copies (rather than moves) so the local files
    /// remain as a frozen fallback if the app is ever built without iCloud entitlements again.
    /// Never overwrites cloud data: if the container already has a store (downloaded or still
    /// a placeholder), another device got there first and its copy wins.
    private static func migrateLocalStoreIfNeeded(from localDocs: URL, to cloudDocs: URL) {
        let fm = FileManager.default
        let localStore = localDocs.appendingPathComponent("store.json")
        let cloudStore = cloudDocs.appendingPathComponent("store.json")
        let cloudPlaceholder = cloudDocs.appendingPathComponent(".store.json.icloud")
        guard fm.fileExists(atPath: localStore.path),
              !fm.fileExists(atPath: cloudStore.path),
              !fm.fileExists(atPath: cloudPlaceholder.path) else { return }

        try? fm.createDirectory(at: cloudDocs, withIntermediateDirectories: true)
        try? fm.copyItem(at: localStore, to: cloudStore)

        let localPhotos = localDocs.appendingPathComponent("Photos", isDirectory: true)
        let cloudPhotos = cloudDocs.appendingPathComponent("Photos", isDirectory: true)
        try? fm.createDirectory(at: cloudPhotos, withIntermediateDirectories: true)
        if let files = try? fm.contentsOfDirectory(at: localPhotos, includingPropertiesForKeys: nil) {
            for file in files {
                try? fm.copyItem(at: file, to: cloudPhotos.appendingPathComponent(file.lastPathComponent))
            }
        }
    }

    static var storeURL: URL { baseDir.appendingPathComponent("store.json") }

    // MARK: - Public API

    /// Loads persisted state from disk. File I/O runs on a background thread internally;
    /// safe to call from the main thread. Returns false if no file exists or decoding fails.
    @discardableResult
    func load() -> Bool {
        var data: Data? = nil
        DispatchQueue.global(qos: .userInitiated).sync {
            Self.waitForCloudStore(timeout: 10)
            data = readStoreData()
        }
        guard let data, let snap = decodeSnapshot(data) else { return false }
        lastPersistedData = data
        applySnapshot(migrate(snap))
        return true
    }

    /// If iCloud sync is enabled, the ubiquity container is active, the local file is
    /// absent, and a placeholder exists, triggers download and polls up to `timeout`
    /// seconds for it to arrive.
    private static func waitForCloudStore(timeout: TimeInterval) {
        let fm = FileManager.default
        guard iCloudSyncEnabled,
              baseDirOverride == nil,
              fm.url(forUbiquityContainerIdentifier: nil) != nil else { return }
        let url = storeURL
        guard !fm.fileExists(atPath: url.path) else { return }
        let placeholder = url.deletingLastPathComponent()
            .appendingPathComponent(".store.json.icloud")
        guard fm.fileExists(atPath: placeholder.path) else { return }
        try? fm.startDownloadingUbiquitousItem(at: url)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !fm.fileExists(atPath: url.path) {
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    func factoryReset() {
        savesSuspended = false
        let photosDir = Self.baseDir.appendingPathComponent("Photos", isDirectory: true)
        if let files = try? FileManager.default.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: nil) {
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
        // Do NOT removeItem on storeURL — overwriting via save() propagates as content
        // (a "tombstone by overwrite") so other devices apply it, rather than ignoring a deletion.
        _applyLoaded(compositeTypes: [:], comboLists: [:], categories: [:], assets: [:],
                     activityLog: [], backgroundTheme: .mist)
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
        let incoming = try decoder.decode(StoreSnapshotDTO.self, from: data)

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

    /// Encodes the current store state to disk via NSFileCoordinator.
    /// Must be called on a background thread.
    func save() {
        guard !savesSuspended else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(buildSnapshot()) else { return }
        let url = Self.storeURL
        var written = false
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing,
                                       error: &coordinatorError) { dest in
            written = (try? data.write(to: dest, options: .atomic)) != nil
        }
        if written {
            lastPersistedData = data
            resolveConflicts()
        }
        if let err = coordinatorError { print("[AssetStore] save error: \(err)") }
    }

    private func resolveConflicts() {
        guard Self.baseDirOverride == nil else { return }
        if let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: Self.storeURL),
           !conflicts.isEmpty {
            for version in conflicts { version.isResolved = true }
            try? NSFileVersion.removeOtherVersionsOfItem(at: Self.storeURL)
        }
    }

    /// Starts watching the iCloud ubiquity container for remote changes pushed by other devices.
    /// Call once from the app's `.task` modifier after launch. No-op when `iCloudSyncEnabled` is false.
    func startCloudMonitor() {
        guard Self.iCloudSyncEnabled else { return }
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "%K == 'store.json'", NSMetadataItemFSNameKey)
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
            let data = self.readStoreData()
            DispatchQueue.main.async {
                defer { query.enableUpdates() }
                if isGather && query.resultCount == 0 {
                    // Gather finished with no store.json in cloud — seeds are safe to persist.
                    if self.savesSuspended {
                        self.savesSuspended = false
                        self.markDirty()
                    }
                    return
                }
                // Upload-progress events echo our own saves back at us. Applying an
                // echo (or any bytes we already persisted) would clobber in-memory
                // mutations made since that write — only foreign content may apply.
                guard let data, data != self.lastPersistedData else { return }
                if let snap = self.decodeSnapshot(data) {
                    self.lastPersistedData = data
                    self.applySnapshot(self.migrate(snap))
                    self.savesSuspended = false
                    self.resolveConflicts()
                }
            }
        }
    }

    // MARK: - File I/O (background thread)

    private func readStoreData() -> Data? {
        let url = Self.storeURL
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        var result: Data? = nil
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges,
                                       error: &coordinatorError) { src in
            result = try? Data(contentsOf: src)
        }
        if let err = coordinatorError { print("[AssetStore] load error: \(err)") }
        return result
    }

    private func decodeSnapshot(_ data: Data) -> StoreSnapshotDTO? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StoreSnapshotDTO.self, from: data)
    }

    // MARK: - Migration

    private func migrate(_ s: StoreSnapshotDTO) -> StoreSnapshotDTO {
        // Future: if s.schemaVersion < 2 { var s = s; /* transform */; return s }
        return s
    }

    // MARK: - Snapshot → live objects (main thread)

    private func applySnapshot(_ snap: StoreSnapshotDTO) {
        // 1. CompositeTypeDefinition shells — fields filled in step 3
        var ctMap: [UUID: CompositeTypeDefinition] = [:]
        for dto in snap.compositeTypes {
            let ct = CompositeTypeDefinition(id: dto.id, name: dto.name, labelHint: dto.labelHint)
            ctMap[dto.id] = ct
        }

        // 2. ComboListDefinition map
        var clMap: [UUID: ComboListDefinition] = [:]
        for dto in snap.comboLists {
            clMap[dto.id] = ComboListDefinition(
                id: dto.id, name: dto.name,
                systemOptions: dto.systemOptions, userOptions: dto.userOptions,
                isUserExtensible: dto.isUserExtensible
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
            let cat = AssetCategory(id: dto.id, name: dto.name, iconName: dto.iconName, propertyTemplates: templates)
            cat.isDeleted = dto.isDeleted
            cat.deletedAt = dto.deletedAt
            catMap[dto.id] = cat
        }

        // 5. Assets — no hierarchy links yet; photo imageData/thumbnailData start nil (lazy load)
        // A dangling categoryID (category hard-deleted while its assets lived on) must never
        // cost the user an asset: resurrect a placeholder category instead of dropping.
        var assetMap: [UUID: Asset] = [:]
        for dto in snap.assets {
            let cat: AssetCategory
            if let existing = catMap[dto.categoryID] {
                cat = existing
            } else {
                let placeholder = AssetCategory(id: dto.categoryID, name: "Recovered",
                                                iconName: "questionmark.folder", propertyTemplates: [])
                catMap[dto.categoryID] = placeholder
                cat = placeholder
            }
            let asset = Asset(
                id: dto.id, name: dto.name, category: cat,
                baseProperties: dto.baseProperties.compactMap {
                    assetProperty(from: $0, ctMap: ctMap, clMap: clMap, fallbackModifyDate: dto.modifiedDate)
                },
                customProperties: dto.customProperties.compactMap {
                    assetProperty(from: $0, ctMap: ctMap, clMap: clMap, fallbackModifyDate: dto.modifiedDate)
                },
                parentID: dto.parentID, createdDate: dto.createdDate, modifiedDate: dto.modifiedDate,
                parentageModifyDate: dto.parentageModifyDate ?? dto.createdDate
            )
            asset.isDeleted = dto.isDeleted
            asset.deletedAt = dto.deletedAt
            asset.photos = dto.photos.map { Photo(id: $0.id, caption: $0.caption, addedDate: $0.addedDate) }
            asset.events = dto.events.map {
                Event(id: $0.id, title: $0.title, date: $0.date, notes: $0.notes,
                      recurrence: $0.recurrence.flatMap(RecurrenceInterval.init))
            }
            asset.transactions = dto.transactions.map {
                Transaction(id: $0.id, details: $0.details,
                            amount: Decimal(string: $0.amount) ?? 0,
                            date: $0.date, kind: TransactionKind(rawValue: $0.kind) ?? .expense,
                            payeeContactID: $0.payeeContactID, notes: $0.notes,
                            recurrence: $0.recurrence.flatMap(RecurrenceInterval.init))
            }
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
        _applyLoaded(
            compositeTypes: ctMap, comboLists: clMap, categories: catMap, assets: assetMap,
            activityLog: log, backgroundTheme: BackgroundTheme(rawValue: snap.backgroundTheme) ?? .mist
        )
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
            ctMap[dto.id] = CompositeTypeDefinition(id: dto.id, name: dto.name, labelHint: dto.labelHint)
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
                    isUserExtensible: dto.isUserExtensible
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
                catMap[dto.id] = AssetCategory(id: dto.id, name: dto.name, iconName: dto.iconName, propertyTemplates: templates)
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
                    undeletedAssets.append(local)
                    changed += 1
                }
                if changed > 0 { local.modifiedDate = Date() }
                for p in dto.photos { photoIDsToMaterialize.insert(p.id) }
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
                parentageModifyDate: dto.parentageModifyDate ?? dto.createdDate
            )
            asset.photos = dto.photos.map { Photo(id: $0.id, caption: $0.caption, addedDate: $0.addedDate) }
            asset.events = dto.events.map {
                Event(id: $0.id, title: $0.title, date: $0.date, notes: $0.notes,
                      recurrence: $0.recurrence.flatMap(RecurrenceInterval.init))
            }
            asset.transactions = dto.transactions.map {
                Transaction(id: $0.id, details: $0.details,
                            amount: Decimal(string: $0.amount) ?? 0,
                            date: $0.date, kind: TransactionKind(rawValue: $0.kind) ?? .expense,
                            payeeContactID: $0.payeeContactID, notes: $0.notes,
                            recurrence: $0.recurrence.flatMap(RecurrenceInterval.init))
            }
            assetMap[asset.id] = asset
            newAssets.append((asset, dto))
            for p in dto.photos { photoIDsToMaterialize.insert(p.id) }
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

        // 8. Commit. backgroundTheme is a per-device cosmetic preference — local wins unconditionally.
        _applyLoaded(
            compositeTypes: ctMap, comboLists: clMap, categories: catMap, assets: assetMap,
            activityLog: log, backgroundTheme: backgroundTheme
        )
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
            let cat = AssetCategory(id: catDTO.id, name: catDTO.name, iconName: catDTO.iconName, propertyTemplates: templates)
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

        let seenEventIDs = Set(local.events.map(\.id))
        for edto in dto.events where !seenEventIDs.contains(edto.id) {
            local.events.append(Event(id: edto.id, title: edto.title, date: edto.date, notes: edto.notes,
                                      recurrence: edto.recurrence.flatMap(RecurrenceInterval.init)))
            added += 1
        }

        let seenTxnIDs = Set(local.transactions.map(\.id))
        for tdto in dto.transactions where !seenTxnIDs.contains(tdto.id) {
            local.transactions.append(Transaction(
                id: tdto.id, details: tdto.details, amount: Decimal(string: tdto.amount) ?? 0,
                date: tdto.date, kind: TransactionKind(rawValue: tdto.kind) ?? .expense,
                payeeContactID: tdto.payeeContactID, notes: tdto.notes,
                recurrence: tdto.recurrence.flatMap(RecurrenceInterval.init)
            ))
            added += 1
        }

        let seenPhotoIDs = Set(local.photos.map(\.id))
        for pdto in dto.photos where !seenPhotoIDs.contains(pdto.id) {
            local.photos.append(Photo(id: pdto.id, caption: pdto.caption, addedDate: pdto.addedDate))
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

    private func buildSnapshot(includePhotoData: Bool = false) -> StoreSnapshotDTO {
        StoreSnapshotDTO(
            schemaVersion: storeSchemaVersion,
            compositeTypes: compositeTypes.values.map { ct in
                CompositeTypeDTO(id: ct.id, name: ct.name,
                                 fields: ct.fields.map { propertyDefinitionDTO($0) },
                                 labelHint: ct.labelHint)
            },
            comboLists: comboListDefinitions.values.map { cl in
                ComboListDTO(id: cl.id, name: cl.name, systemOptions: cl.systemOptions,
                             userOptions: cl.userOptions, isUserExtensible: cl.isUserExtensible)
            },
            categories: categories.values.map { cat in
                CategoryDTO(id: cat.id, name: cat.name, iconName: cat.iconName,
                            propertyTemplates: cat.propertyTemplates.map { assetPropertyDTO($0) },
                            isDeleted: cat.isDeleted, deletedAt: cat.deletedAt)
            },
            assets: assets.values.map { asset in
                AssetDTO(
                    id: asset.id, name: asset.name, categoryID: asset.category.id,
                    baseProperties: asset.baseProperties.map { assetPropertyDTO($0) },
                    customProperties: asset.customProperties.map { assetPropertyDTO($0) },
                    photos: asset.photos.map { p in
                        PhotoDTO(
                            id: p.id, caption: p.caption, addedDate: p.addedDate,
                            fullImage: includePhotoData ? PhotoStorage.loadFull(id: p.id) : nil,
                            thumbnail: includePhotoData ? PhotoStorage.loadThumb(id: p.id) : nil
                        )
                    },
                    events: asset.events.map {
                        EventDTO(id: $0.id, title: $0.title, date: $0.date,
                                 notes: $0.notes, recurrence: $0.recurrence?.rawValue)
                    },
                    transactions: asset.transactions.map { txn in
                        TransactionDTO(id: txn.id, details: txn.details, amount: txn.amount.description,
                                       date: txn.date, kind: txn.kind.rawValue,
                                       payeeContactID: txn.payeeContactID, notes: txn.notes,
                                       recurrence: txn.recurrence?.rawValue)
                    },
                    parentID: asset.parentID, isDeleted: asset.isDeleted, deletedAt: asset.deletedAt,
                    createdDate: asset.createdDate, modifiedDate: asset.modifiedDate,
                    parentageModifyDate: asset.parentageModifyDate
                )
            },
            activityLog: activityLog.map {
                ActivityLogDTO(id: $0.id, recordID: $0.recordID, kind: $0.kind.rawValue,
                               owningAssetID: $0.owningAssetID, timestamp: $0.timestamp)
            },
            backgroundTheme: backgroundTheme.rawValue
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
        return AssetProperty(id: dto.id, definition: def,
                             value: dto.value.map { storedValue(from: $0) },
                             sortOrder: dto.sortOrder,
                             modifyDate: dto.modifyDate ?? fallbackModifyDate)
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
                         modifyDate: prop.modifyDate)
    }
}
