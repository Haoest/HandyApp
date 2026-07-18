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

    /// Decodes the given exported JSON, wipes all local data and photos, then replaces the
    /// store with the imported content. Caller must obtain user confirmation before calling.
    func importJSON(data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let incoming = try decoder.decode(StoreSnapshotDTO.self, from: data)

        // Phase 2A: only delete photo files not referenced by the incoming snapshot.
        let keepIDs = Set(incoming.assets.flatMap { $0.photos.map(\.id) })
        let photosDir = Self.baseDir.appendingPathComponent("Photos", isDirectory: true)
        if let files = try? FileManager.default.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: nil) {
            for file in files {
                let prefix = file.lastPathComponent.split(separator: "_").first.map(String.init) ?? ""
                if let id = UUID(uuidString: prefix), keepIDs.contains(id) { continue }
                try? FileManager.default.removeItem(at: file)
            }
        }

        applySnapshot(migrate(incoming))

        // Phase 2B: write embedded photo bytes so other-device imports recreate the files.
        for assetDTO in incoming.assets {
            for photoDTO in assetDTO.photos {
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
            let templates = dto.propertyTemplates.compactMap { assetProperty(from: $0, ctMap: ctMap, clMap: clMap) }
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
                baseProperties: dto.baseProperties.compactMap { assetProperty(from: $0, ctMap: ctMap, clMap: clMap) },
                customProperties: dto.customProperties.compactMap { assetProperty(from: $0, ctMap: ctMap, clMap: clMap) },
                parentID: dto.parentID, createdDate: dto.createdDate, modifiedDate: dto.modifiedDate
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

        // 6. Wire parent→child hierarchy
        for dto in snap.assets {
            guard let asset = assetMap[dto.id],
                  let parentID = dto.parentID,
                  let parent = assetMap[parentID] else { continue }
            parent._addChild(asset)
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
                    createdDate: asset.createdDate, modifiedDate: asset.modifiedDate
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

    private func assetProperty(
        from dto: AssetPropertyDTO,
        ctMap: [UUID: CompositeTypeDefinition],
        clMap: [UUID: ComboListDefinition]
    ) -> AssetProperty? {
        guard let def = propertyDefinition(from: dto.definition, ctMap: ctMap, clMap: clMap) else { return nil }
        return AssetProperty(id: dto.id, definition: def,
                             value: dto.value.map { storedValue(from: $0) },
                             sortOrder: dto.sortOrder)
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
                         value: prop.value.map { storedValueDTO($0) }, sortOrder: prop.sortOrder)
    }
}
