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

    static func loadFull(id: UUID) -> Data? { try? Data(contentsOf: fullURL(id: id)) }
    static func loadThumb(id: UUID) -> Data? { try? Data(contentsOf: thumbURL(id: id)) }

    static func delete(id: UUID) {
        try? FileManager.default.removeItem(at: fullURL(id: id))
        try? FileManager.default.removeItem(at: thumbURL(id: id))
    }
}

// MARK: - AssetStore persistence

extension AssetStore {

    // MARK: - URL resolution

    /// Base directory for all store files. Uses the iCloud ubiquity container when available;
    /// falls back to the local Documents directory. Creates the Photos/ subdirectory as a side effect.
    static var baseDir: URL {
        let dir: URL
        if let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            dir = container.appendingPathComponent("Documents", isDirectory: true)
        } else {
            dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        let photosDir = dir.appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        return dir
    }

    static var storeURL: URL { baseDir.appendingPathComponent("store.json") }

    // MARK: - Public API

    /// Loads persisted state from disk. File I/O runs on a background thread internally;
    /// safe to call from the main thread. Returns false if no file exists or decoding fails.
    @discardableResult
    func load() -> Bool {
        var snapshot: StoreSnapshotDTO? = nil
        DispatchQueue.global(qos: .userInitiated).sync {
            snapshot = readSnapshot()
        }
        guard let snap = snapshot else { return false }
        applySnapshot(migrate(snap))
        return true
    }

    /// Encodes the current store state to disk via NSFileCoordinator.
    /// Must be called on a background thread.
    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(buildSnapshot()) else { return }
        let url = Self.storeURL
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing,
                                       error: &coordinatorError) { dest in
            try? data.write(to: dest, options: .atomic)
        }
        if let err = coordinatorError { print("[AssetStore] save error: \(err)") }
    }

    /// Starts watching the iCloud ubiquity container for remote changes pushed by other devices.
    /// Call once from the app's `.task` modifier after launch.
    func startCloudMonitor() {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "%K == 'store.json'", NSMetadataItemFSNameKey)
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate, object: query, queue: .main
        ) { [weak self] _ in
            query.disableUpdates()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let snap = self.readSnapshot()
                DispatchQueue.main.async {
                    if let snap { self.applySnapshot(self.migrate(snap)) }
                    query.enableUpdates()
                }
            }
        }
        query.start()
        cloudQuery = query
    }

    // MARK: - File I/O (background thread)

    private func readSnapshot() -> StoreSnapshotDTO? {
        let url = Self.storeURL
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        var result: StoreSnapshotDTO? = nil
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges,
                                       error: &coordinatorError) { src in
            guard let data = try? Data(contentsOf: src) else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            result = try? decoder.decode(StoreSnapshotDTO.self, from: data)
        }
        if let err = coordinatorError { print("[AssetStore] load error: \(err)") }
        return result
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
        var assetMap: [UUID: Asset] = [:]
        for dto in snap.assets {
            guard let cat = catMap[dto.categoryID] else { continue }
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

    private func buildSnapshot() -> StoreSnapshotDTO {
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
                    photos: asset.photos.map { PhotoDTO(id: $0.id, caption: $0.caption, addedDate: $0.addedDate) },
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
