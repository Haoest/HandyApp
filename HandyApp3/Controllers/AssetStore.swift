import Foundation
import Observation

// MARK: - Errors

enum AssetStoreError: Error, Equatable {
    case assetNotFound(UUID)
    case categoryNotFound(UUID)
    case compositeTypeNotFound(UUID)
    case definitionNotFound(UUID)
    /// The supplied StoredValue variant does not match the PropertyDefinition's type.
    case typeMismatch(expected: String, got: String)
    /// A composite payload is missing required fields or contains unknown field names.
    case compositeFieldMismatch(details: String)
    /// Attaching a child would create a cycle in the asset hierarchy.
    case hierarchyCycle(childID: UUID, ancestorID: UUID)
    /// A ComboListDefinition with the given ID was not found.
    case comboListNotFound(UUID)
    /// Attempted to modify a system combo list option.
    case cannotModifySystemOption(listID: UUID, option: String)
    /// Attempted to add or remove a user option on a non-extensible combo list.
    case comboListNotExtensible(UUID)
    /// An AssetProperty with the given id was not found on the specified asset.
    case propertyNotFound(UUID)
    /// Attempted to add a child that already has a parent; call removeFromParent first.
    case assetAlreadyHasParent(UUID)
    /// A category with the given name already exists.
    case duplicateCategoryName(String)
    case photoNotFound(UUID)
    case eventNotFound(UUID)
    case transactionNotFound(UUID)
    /// Creating or restoring an asset would exceed the free-tier asset limit.
    case freeLimitReached(limit: Int)
    /// Adding an event would exceed the free-tier per-asset event limit.
    case freeEventLimitReached(limit: Int)
    /// Adding a transaction would exceed the free-tier per-asset transaction limit.
    case freeTransactionLimitReached(limit: Int)
}

// MARK: - AssetStore

/// Single in-memory store for the entire domain.
/// All mutations happen through this object; there is no persistence at this layer.
@Observable
final class AssetStore {

    // MARK: - Storage

    private(set) var assets: [UUID: Asset] = [:]
    private(set) var categories: [UUID: AssetCategory] = [:]
    private(set) var compositeTypes: [UUID: CompositeTypeDefinition] = [:]
    private(set) var comboListDefinitions: [UUID: ComboListDefinition] = [:]

    /// Append-only, chronological record of asset/event/transaction creations.
    private(set) var activityLog: [ActivityLogEntry] = []

    /// When set, event/transaction mutations (and asset deletions) trigger a full
    /// notification resync. Nil in tests keeps the store notification-free.
    var notificationScheduler: NotificationScheduler?

    /// Max live assets `createAsset`/`restoreAsset` allow; nil = unlimited.
    /// Runtime-only — driven by purchase state, never persisted.
    var assetCreationLimit: Int?

    /// Max events per individual asset `addEvent` allows; nil = unlimited.
    /// Per-asset (compares one asset's own `events.count`), unlike the global asset limit.
    /// Runtime-only — driven by purchase state, never persisted.
    var eventCreationLimit: Int?

    /// Max transactions per individual asset `addTransaction` allows; nil = unlimited.
    /// Per-asset (compares one asset's own `transactions.count`), unlike the global asset limit.
    /// Runtime-only — driven by purchase state, never persisted.
    var transactionCreationLimit: Int?

    var backgroundTheme: BackgroundTheme = .mist {
        didSet { markDirty() }
    }

    /// Retained iCloud metadata query for remote-change monitoring. Set by startCloudMonitor().
    @ObservationIgnored
    var cloudQuery: NSMetadataQuery?

    /// Pending debounced save task. Cancelled and replaced on each mutation.
    @ObservationIgnored
    private var saveTask: Task<Void, Never>?

    /// The exact bytes last written to (or read from) store.json by this process.
    /// The cloud monitor compares against this to tell foreign changes from echoes
    /// of our own saves — applying an echo would clobber newer in-memory mutations.
    /// Guarded by `persistLock`: written on background save threads, read on main.
    @ObservationIgnored
    private let persistLock = NSLock()
    @ObservationIgnored
    private var _lastPersistedData: Data?

    var lastPersistedData: Data? {
        get { persistLock.lock(); defer { persistLock.unlock() }; return _lastPersistedData }
        set { persistLock.lock(); _lastPersistedData = newValue; persistLock.unlock() }
    }

    // MARK: - Derived collections

    var allAssets: [Asset] { assets.values.filter { !$0.isDeleted } }
    var allCategories: [AssetCategory] { categories.values.filter { !$0.isDeleted } }
    var deletedAssets: [Asset] { assets.values.filter { $0.isDeleted } }
    var deletedCategories: [AssetCategory] { categories.values.filter { $0.isDeleted } }
    var allCompositeTypes: [CompositeTypeDefinition] { Array(compositeTypes.values) }
    var allComboListDefinitions: [ComboListDefinition] { Array(comboListDefinitions.values) }

    /// Whether creating or restoring another asset is currently allowed under `assetCreationLimit`.
    var hasAssetCapacity: Bool { assetCreationLimit.map { allAssets.count < $0 } ?? true }

    /// Whether adding another event to `asset` is currently allowed under `eventCreationLimit`.
    func hasEventCapacity(for asset: Asset) -> Bool {
        eventCreationLimit.map { asset.events.count < $0 } ?? true
    }

    /// Whether adding another transaction to `asset` is currently allowed under `transactionCreationLimit`.
    func hasTransactionCapacity(for asset: Asset) -> Bool {
        transactionCreationLimit.map { asset.transactions.count < $0 } ?? true
    }

    // MARK: - AssetCategory CRUD

    @discardableResult
    func createCategory(name: String, iconName: String = "square.grid.2x2", propertyTemplates: [AssetProperty] = []) throws -> AssetCategory {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if categories.values.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            throw AssetStoreError.duplicateCategoryName(trimmed)
        }
        let cat = AssetCategory(name: trimmed, iconName: iconName, propertyTemplates: propertyTemplates)
        categories[cat.id] = cat
        markDirty()
        return cat
    }

    func updateCategory(id: UUID, name: String) throws {
        guard let cat = categories[id] else { throw AssetStoreError.categoryNotFound(id) }
        cat.name = name
        markDirty()
    }

    func updateCategoryIcon(id: UUID, iconName: String) throws {
        guard let cat = categories[id] else { throw AssetStoreError.categoryNotFound(id) }
        cat.iconName = iconName
        markDirty()
    }

    func deleteCategory(id: UUID) throws {
        guard categories[id] != nil else { throw AssetStoreError.categoryNotFound(id) }
        categories.removeValue(forKey: id)
        markDirty()
    }

    func softDeleteCategory(id: UUID) throws {
        guard let cat = categories[id] else { throw AssetStoreError.categoryNotFound(id) }
        cat.isDeleted = true
        cat.deletedAt = Date()
        markDirty()
    }

    /// Appends a new property template to an existing category.
    @discardableResult
    func addTemplateProperty(_ property: AssetProperty, toCategoryID categoryID: UUID) throws -> AssetProperty {
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        cat.propertyTemplates.append(property)
        markDirty()
        return property
    }

    func setTemplatePropertyValue(_ stored: StoredValue, forPropertyID propID: UUID, inCategoryID categoryID: UUID) throws {
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        guard let prop = cat.propertyTemplates.first(where: { $0.id == propID }) else {
            throw AssetStoreError.propertyNotFound(propID)
        }
        try validate(stored: stored, against: prop.definition.type, definitionName: prop.definition.name)
        prop.value = stored
        markDirty()
    }

    func removeTemplatePropertyValue(forPropertyID propID: UUID, inCategoryID categoryID: UUID) throws {
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        guard let prop = cat.propertyTemplates.first(where: { $0.id == propID }) else {
            throw AssetStoreError.propertyNotFound(propID)
        }
        prop.value = nil
        markDirty()
    }

    /// Removes a template property from a category. Does not affect existing assets.
    func removeTemplateProperty(id propID: UUID, fromCategoryID categoryID: UUID) throws {
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        guard cat.propertyTemplates.contains(where: { $0.id == propID }) else {
            throw AssetStoreError.propertyNotFound(propID)
        }
        cat.propertyTemplates.removeAll { $0.id == propID }
        markDirty()
    }

    func updateTemplateProperty(
        id propID: UUID,
        inCategoryID categoryID: UUID,
        name: String? = nil,
        type: PropertyType? = nil
    ) throws {
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        guard let prop = cat.propertyTemplates.first(where: { $0.id == propID }) else {
            throw AssetStoreError.propertyNotFound(propID)
        }
        if let name { prop.definition.name = name }
        if let type {
            prop.definition.type = type
            prop.value = nil
        }
        markDirty()
    }

    // MARK: - Asset CRUD

    /// Creates an Asset, deep-copying the category's property templates into baseProperties.
    @discardableResult
    func createAsset(name: String, categoryID: UUID) throws -> Asset {
        if let limit = assetCreationLimit, allAssets.count >= limit {
            throw AssetStoreError.freeLimitReached(limit: limit)
        }
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        let baseProperties = cat.propertyTemplates.enumerated().map { index, template in
            AssetProperty(definition: template.definition, value: template.value,
                          sortOrder: Double(index) * AssetProperty.sortOrderIncrement)
        }
        let asset = Asset(name: name, category: cat, baseProperties: baseProperties)
        assets[asset.id] = asset
        logCreation(of: asset.id, kind: .asset)
        markDirty()
        return asset
    }

    func updateAsset(id: UUID, name: String) throws {
        guard let asset = assets[id] else { throw AssetStoreError.assetNotFound(id) }
        asset.name = name
        asset.modifiedDate = Date()
        markDirty()
    }

    func deleteAsset(id: UUID) throws {
        guard let asset = assets[id] else { throw AssetStoreError.assetNotFound(id) }
        let grandparent = asset.parent
        asset.parent?._removeChild(asset)
        for child in Array(asset.children) {
            asset._removeChild(child)
            grandparent?._addChild(child)
        }
        assets.removeValue(forKey: id)
        notificationScheduler?.requestResync(assets: allAssets)
        markDirty()
    }

    /// Marks the asset as deleted without removing it from the store.
    /// Detaches it from its parent; direct children become top-level assets.
    func softDeleteAsset(id: UUID) throws {
        guard let asset = assets[id] else { throw AssetStoreError.assetNotFound(id) }
        asset.parent?._removeChild(asset)
        for child in Array(asset.children) {
            asset._removeChild(child)
        }
        asset.isDeleted = true
        asset.deletedAt = Date()
        asset.modifiedDate = Date()
        notificationScheduler?.requestResync(assets: allAssets)
        markDirty()
    }

    /// Soft-deletes the asset and all of its descendants, preserving their parent-child
    /// relationships until the records are hard-deleted by the retention sweep.
    func softDeleteAssetDeep(id: UUID) throws {
        guard let asset = assets[id] else { throw AssetStoreError.assetNotFound(id) }
        let now = Date()
        asset.parent?._removeChild(asset)
        var queue: [Asset] = [asset]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            queue.append(contentsOf: current.children)
            current.isDeleted = true
            current.deletedAt = now
            current.modifiedDate = now
        }
        notificationScheduler?.requestResync(assets: allAssets)
        markDirty()
    }

    func restoreAsset(id: UUID) throws {
        guard let asset = assets[id] else { throw AssetStoreError.assetNotFound(id) }
        if let limit = assetCreationLimit, allAssets.count >= limit {
            throw AssetStoreError.freeLimitReached(limit: limit)
        }
        asset.isDeleted = false
        asset.deletedAt = nil
        asset.modifiedDate = Date()
        notificationScheduler?.requestResync(assets: allAssets)
        markDirty()
    }

    func restoreCategory(id: UUID) throws {
        guard let cat = categories[id] else { throw AssetStoreError.categoryNotFound(id) }
        cat.isDeleted = false
        cat.deletedAt = nil
        markDirty()
    }

    /// All assets belonging to the given category.
    func assets(ofCategoryID categoryID: UUID) throws -> [Asset] {
        guard categories[categoryID] != nil else { throw AssetStoreError.categoryNotFound(categoryID) }
        return assets.values.filter { $0.category.id == categoryID }
    }

    // MARK: - Property value management

    /// Sets a value on a base or custom property identified by its definition id.
    /// Validates type compatibility before writing.
    @discardableResult
    func setPropertyValue(
        _ stored: StoredValue,
        forDefinitionID definitionID: UUID,
        onAssetID assetID: UUID
    ) throws -> AssetProperty {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        if let prop = asset.baseProperties.first(where: { $0.definition.id == definitionID }) {
            try validate(stored: stored, against: prop.definition.type, definitionName: prop.definition.name)
            handleComboListAutoAdd(stored: stored, type: prop.definition.type)
            prop.value = stored
            asset.modifiedDate = Date()
            markDirty()
            return prop
        }
        if let prop = asset.customProperties.first(where: { $0.definition.id == definitionID }) {
            try validate(stored: stored, against: prop.definition.type, definitionName: prop.definition.name)
            handleComboListAutoAdd(stored: stored, type: prop.definition.type)
            prop.value = stored
            asset.modifiedDate = Date()
            markDirty()
            return prop
        }
        throw AssetStoreError.definitionNotFound(definitionID)
    }

    /// Clears the value on a base or custom property. Does not remove the property itself.
    func removePropertyValue(forDefinitionID definitionID: UUID, fromAssetID assetID: UUID) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        if let prop = asset.baseProperties.first(where: { $0.definition.id == definitionID }) {
            prop.value = nil
            asset.modifiedDate = Date()
            markDirty()
            return
        }
        if let prop = asset.customProperties.first(where: { $0.definition.id == definitionID }) {
            prop.value = nil
            asset.modifiedDate = Date()
            markDirty()
            return
        }
        throw AssetStoreError.definitionNotFound(definitionID)
    }

    // MARK: - Custom property management on assets

    /// Adds a new per-asset custom property with an optional initial value.
    @discardableResult
    func addCustomProperty(
        definition: PropertyDefinition,
        value: StoredValue? = nil,
        toAssetID assetID: UUID
    ) throws -> AssetProperty {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        if let stored = value {
            try validate(stored: stored, against: definition.type, definitionName: definition.name)
        }
        let prop = AssetProperty(definition: definition, value: value)
        asset.customProperties.append(prop)
        asset.modifiedDate = Date()
        markDirty()
        return prop
    }

    /// Replaces the value on an existing custom property.
    @discardableResult
    func setCustomPropertyValue(
        _ stored: StoredValue,
        forCustomPropertyID propID: UUID,
        onAssetID assetID: UUID
    ) throws -> AssetProperty {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        guard let prop = asset.customProperties.first(where: { $0.id == propID }) else {
            throw AssetStoreError.propertyNotFound(propID)
        }
        try validate(stored: stored, against: prop.definition.type, definitionName: prop.definition.name)
        prop.value = stored
        asset.modifiedDate = Date()
        markDirty()
        return prop
    }

    /// Updates the definition of an existing custom property.
    /// Clears the stored value if the type changes.
    func updateCustomProperty(
        id propID: UUID,
        onAssetID assetID: UUID,
        name: String? = nil,
        type: PropertyType? = nil,
        isRequired: Bool? = nil
    ) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        guard let prop = asset.customProperties.first(where: { $0.id == propID }) else {
            throw AssetStoreError.propertyNotFound(propID)
        }
        if let name { prop.definition.name = name }
        if let isRequired { prop.definition.isRequired = isRequired }
        if let type {
            prop.definition.type = type
            prop.value = nil
        }
        asset.modifiedDate = Date()
        markDirty()
    }

    /// Removes a custom property and its value from an asset.
    func removeCustomProperty(id propID: UUID, fromAssetID assetID: UUID) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        guard asset.customProperties.contains(where: { $0.id == propID }) else {
            throw AssetStoreError.propertyNotFound(propID)
        }
        asset.customProperties.removeAll { $0.id == propID }
        asset.modifiedDate = Date()
        markDirty()
    }

    // MARK: - ComboListDefinition CRUD

    @discardableResult
    func createComboList(
        name: String,
        systemOptions: [String] = [],
        userOptions: [String] = [],
        isUserExtensible: Bool = true
    ) -> ComboListDefinition {
        let cl = ComboListDefinition(name: name, systemOptions: systemOptions, userOptions: userOptions, isUserExtensible: isUserExtensible)
        comboListDefinitions[cl.id] = cl
        markDirty()
        return cl
    }

    func updateComboList(id: UUID, name: String) throws {
        guard let cl = comboListDefinitions[id] else { throw AssetStoreError.comboListNotFound(id) }
        cl.name = name
        markDirty()
    }

    func deleteComboList(id: UUID) throws {
        guard comboListDefinitions[id] != nil else { throw AssetStoreError.comboListNotFound(id) }
        comboListDefinitions.removeValue(forKey: id)
        markDirty()
    }

    func addUserOption(_ option: String, toComboListID id: UUID) throws {
        guard let cl = comboListDefinitions[id] else { throw AssetStoreError.comboListNotFound(id) }
        guard cl.isUserExtensible else { throw AssetStoreError.comboListNotExtensible(id) }
        guard !cl.allOptions.contains(option) else { return }
        cl.userOptions.append(option)
        markDirty()
    }

    func removeUserOption(_ option: String, fromComboListID id: UUID) throws {
        guard let cl = comboListDefinitions[id] else { throw AssetStoreError.comboListNotFound(id) }
        guard cl.isUserExtensible else { throw AssetStoreError.comboListNotExtensible(id) }
        guard !cl.systemOptions.contains(option) else {
            throw AssetStoreError.cannotModifySystemOption(listID: id, option: option)
        }
        cl.userOptions.removeAll { $0 == option }
        markDirty()
    }

    // MARK: - CompositeTypeDefinition CRUD

    @discardableResult
    func createCompositeType(
        name: String,
        fields: [PropertyDefinition] = [],
        labelHint: String? = nil
    ) -> CompositeTypeDefinition {
        let ct = CompositeTypeDefinition(name: name, fields: fields, labelHint: labelHint)
        compositeTypes[ct.id] = ct
        markDirty()
        return ct
    }

    func updateCompositeType(id: UUID, name: String) throws {
        guard let ct = compositeTypes[id] else { throw AssetStoreError.compositeTypeNotFound(id) }
        ct.name = name
        markDirty()
    }

    func deleteCompositeType(id: UUID) throws {
        guard compositeTypes[id] != nil else { throw AssetStoreError.compositeTypeNotFound(id) }
        compositeTypes.removeValue(forKey: id)
        markDirty()
    }

    @discardableResult
    func addField(_ field: PropertyDefinition, toCompositeTypeID typeID: UUID) throws -> PropertyDefinition {
        guard let ct = compositeTypes[typeID] else { throw AssetStoreError.compositeTypeNotFound(typeID) }
        ct.fields.append(field)
        markDirty()
        return field
    }

    func removeField(id fieldID: UUID, fromCompositeTypeID typeID: UUID) throws {
        guard let ct = compositeTypes[typeID] else { throw AssetStoreError.compositeTypeNotFound(typeID) }
        guard ct.fields.contains(where: { $0.id == fieldID }) else {
            throw AssetStoreError.definitionNotFound(fieldID)
        }
        ct.fields.removeAll { $0.id == fieldID }
        markDirty()
    }

    func updateField(
        id fieldID: UUID,
        inCompositeTypeID typeID: UUID,
        name: String? = nil,
        type: PropertyType? = nil,
        isRequired: Bool? = nil
    ) throws {
        guard let ct = compositeTypes[typeID] else { throw AssetStoreError.compositeTypeNotFound(typeID) }
        guard let idx = ct.fields.firstIndex(where: { $0.id == fieldID }) else {
            throw AssetStoreError.definitionNotFound(fieldID)
        }
        if let name       { ct.fields[idx].name       = name       }
        if let type       { ct.fields[idx].type       = type       }
        if let isRequired { ct.fields[idx].isRequired = isRequired }
        markDirty()
    }

    // MARK: - Validation helpers

    func validate(stored: StoredValue, against type: PropertyType, definitionName: String) throws {
        switch type {
        case .basic(let basic):
            guard let actual = stored.basicType, actual == basic else {
                let expected = basic.rawValue
                let got = stored.basicType?.rawValue ?? "composite"
                throw AssetStoreError.typeMismatch(expected: expected, got: got)
            }

        case .comboList(let list):
            guard case .text(let value) = stored else {
                let got = stored.basicType?.rawValue ?? "composite"
                throw AssetStoreError.typeMismatch(expected: "comboList(\(list.name))", got: got)
            }
            if !list.isUserExtensible && !list.allOptions.contains(value) {
                throw AssetStoreError.typeMismatch(
                    expected: "one of [\(list.allOptions.joined(separator: ", "))]",
                    got: value
                )
            }

        case .composite(let definition):
            guard case .composite(let payload) = stored else {
                let got = stored.basicType?.rawValue ?? "composite"
                throw AssetStoreError.typeMismatch(expected: "composite(\(definition.name))", got: got)
            }
            let fieldsByName = Dictionary(uniqueKeysWithValues: definition.fields.map { ($0.name, $0) })
            for field in definition.fields where field.isRequired {
                if payload[field.name] == nil {
                    throw AssetStoreError.compositeFieldMismatch(
                        details: "Required field '\(field.name)' is missing from composite type '\(definition.name)'"
                    )
                }
            }
            for (key, subValue) in payload {
                guard let fieldDef = fieldsByName[key] else {
                    throw AssetStoreError.compositeFieldMismatch(
                        details: "Unknown field '\(key)' in composite type '\(definition.name)'"
                    )
                }
                try validate(stored: subValue, against: fieldDef.type, definitionName: fieldDef.name)
            }
        }
    }

    // MARK: - Asset hierarchy

    func addChild(assetID childID: UUID, toParentID parentID: UUID) throws {
        guard let child     = assets[childID]  else { throw AssetStoreError.assetNotFound(childID) }
        guard let newParent = assets[parentID] else { throw AssetStoreError.assetNotFound(parentID) }
        guard childID != parentID else {
            throw AssetStoreError.hierarchyCycle(childID: childID, ancestorID: parentID)
        }
        if child.parent != nil {
            throw AssetStoreError.assetAlreadyHasParent(childID)
        }
        if child.descendants.contains(where: { $0.id == parentID }) {
            throw AssetStoreError.hierarchyCycle(childID: childID, ancestorID: parentID)
        }
        newParent._addChild(child)
        markDirty()
    }

    func removeFromParent(assetID: UUID) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        asset.parent?._removeChild(asset)
        markDirty()
    }

    func moveAsset(assetID: UUID, toParentID newParentID: UUID) throws {
        try removeFromParent(assetID: assetID)
        try addChild(assetID: assetID, toParentID: newParentID)
    }

    var rootAssets: [Asset] {
        assets.values.filter(\.isRoot)
    }

    func rootAssets(ofCategoryID categoryID: UUID) throws -> [Asset] {
        guard categories[categoryID] != nil else { throw AssetStoreError.categoryNotFound(categoryID) }
        return assets.values.filter { $0.isRoot && $0.category.id == categoryID }
    }

    // MARK: - Attachments

    @discardableResult
    func addPhoto(imageData: Data, thumbnailData: Data, caption: String = "", toAssetID assetID: UUID) throws -> Photo {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        let photo = Photo(imageData: imageData, thumbnailData: thumbnailData, caption: caption)
        PhotoStorage.save(id: photo.id, imageData: imageData, thumbnailData: thumbnailData)
        asset.photos.append(photo)
        asset.modifiedDate = Date()
        logCreation(of: photo.id, kind: .photo, owningAssetID: assetID)
        markDirty()
        return photo
    }

    func updatePhotoCaption(_ caption: String, forPhotoID photoID: UUID, onAssetID assetID: UUID) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        guard let photo = asset.photos.first(where: { $0.id == photoID }) else { throw AssetStoreError.photoNotFound(photoID) }
        photo.caption = caption
        asset.modifiedDate = Date()
        markDirty()
    }

    func removePhoto(id photoID: UUID, fromAssetID assetID: UUID) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        guard asset.photos.contains(where: { $0.id == photoID }) else { throw AssetStoreError.photoNotFound(photoID) }
        PhotoStorage.delete(id: photoID)
        asset.photos.removeAll { $0.id == photoID }
        asset.modifiedDate = Date()
        markDirty()
    }

    @discardableResult
    func addEvent(title: String, date: Date, notes: String = "", recurrence: RecurrenceInterval? = nil, toAssetID assetID: UUID) throws -> Event {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        if let limit = eventCreationLimit, asset.events.count >= limit {
            throw AssetStoreError.freeEventLimitReached(limit: limit)
        }
        let event = Event(title: title, date: date, notes: notes, recurrence: recurrence)
        asset.events.append(event)
        asset.modifiedDate = Date()
        logCreation(of: event.id, kind: .event, owningAssetID: assetID)
        notificationScheduler?.requestResync(assets: allAssets)
        markDirty()
        return event
    }

    func updateEvent(id eventID: UUID, onAssetID assetID: UUID, title: String, date: Date, notes: String, recurrence: RecurrenceInterval?) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        guard let event = asset.events.first(where: { $0.id == eventID }) else { throw AssetStoreError.eventNotFound(eventID) }
        event.title = title
        event.date = date
        event.notes = notes
        event.recurrence = recurrence
        asset.modifiedDate = Date()
        notificationScheduler?.requestResync(assets: allAssets)
        markDirty()
    }

    func removeEvent(id eventID: UUID, fromAssetID assetID: UUID) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        guard asset.events.contains(where: { $0.id == eventID }) else { throw AssetStoreError.eventNotFound(eventID) }
        asset.events.removeAll { $0.id == eventID }
        asset.modifiedDate = Date()
        notificationScheduler?.requestResync(assets: allAssets)
        markDirty()
    }

    @discardableResult
    func addTransaction(details: String, amount: Decimal, date: Date, kind: TransactionKind, payeeContactID: String? = nil, notes: String = "", recurrence: RecurrenceInterval? = nil, toAssetID assetID: UUID) throws -> Transaction {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        if let limit = transactionCreationLimit, asset.transactions.count >= limit {
            throw AssetStoreError.freeTransactionLimitReached(limit: limit)
        }
        let txn = Transaction(details: details, amount: amount, date: date, kind: kind, payeeContactID: payeeContactID, notes: notes, recurrence: recurrence)
        asset.transactions.append(txn)
        asset.modifiedDate = Date()
        logCreation(of: txn.id, kind: .transaction, owningAssetID: assetID)
        notificationScheduler?.requestResync(assets: allAssets)
        markDirty()
        return txn
    }

    func updateTransaction(id txnID: UUID, onAssetID assetID: UUID, details: String, amount: Decimal, date: Date, kind: TransactionKind, payeeContactID: String?, notes: String, recurrence: RecurrenceInterval?) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        guard let txn = asset.transactions.first(where: { $0.id == txnID }) else { throw AssetStoreError.transactionNotFound(txnID) }
        txn.details = details
        txn.amount = abs(amount)
        txn.date = date
        txn.kind = kind
        txn.payeeContactID = payeeContactID
        txn.notes = notes
        txn.recurrence = recurrence
        asset.modifiedDate = Date()
        notificationScheduler?.requestResync(assets: allAssets)
        markDirty()
    }

    func removeTransaction(id txnID: UUID, fromAssetID assetID: UUID) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        guard asset.transactions.contains(where: { $0.id == txnID }) else { throw AssetStoreError.transactionNotFound(txnID) }
        asset.transactions.removeAll { $0.id == txnID }
        asset.modifiedDate = Date()
        notificationScheduler?.requestResync(assets: allAssets)
        markDirty()
    }

    // MARK: - Private helpers

    private func logCreation(of recordID: UUID, kind: LoggedRecordKind, owningAssetID: UUID? = nil) {
        activityLog.append(ActivityLogEntry(recordID: recordID, kind: kind, owningAssetID: owningAssetID))
    }

    private func handleComboListAutoAdd(stored: StoredValue, type: PropertyType) {
        guard case .comboList(let list) = type,
              case .text(let value) = stored,
              list.isUserExtensible,
              !list.allOptions.contains(value) else { return }
        list.userOptions.append(value)
    }

    // MARK: - Persistence internals
    // These must live here to write private(set) storage properties.

    /// Schedules a background save ~2 s after the last mutation. Cancels and replaces
    /// any pending save, so rapid mutations collapse into one write.
    func markDirty() {
        saveTask?.cancel()
        saveTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.save()
        }
    }

    /// Replaces in-memory state with the decoded snapshot. Called on the main thread.
    func _applyLoaded(
        compositeTypes: [UUID: CompositeTypeDefinition],
        comboLists: [UUID: ComboListDefinition],
        categories: [UUID: AssetCategory],
        assets: [UUID: Asset],
        activityLog: [ActivityLogEntry],
        backgroundTheme: BackgroundTheme
    ) {
        self.compositeTypes = compositeTypes
        self.comboListDefinitions = comboLists
        self.categories = categories
        self.assets = assets
        self.activityLog = activityLog
        self.backgroundTheme = backgroundTheme
    }

    /// Permanently removes soft-deleted assets/categories whose deletedAt is older than `seconds`.
    /// Deletes associated photo files before discarding each asset. Categories still referenced
    /// by any surviving asset are kept regardless of age — purging them would leave dangling
    /// categoryIDs that load/import cannot resolve.
    func purgeHardDeleted(olderThan seconds: TimeInterval = 90 * 86_400) {
        let cutoff = Date().addingTimeInterval(-seconds)
        assets = assets.filter { _, a in
            guard a.isDeleted, (a.deletedAt ?? .distantFuture) < cutoff else { return true }
            for photo in a.photos { PhotoStorage.delete(id: photo.id) }
            return false
        }
        let referencedCategoryIDs = Set(assets.values.map { $0.category.id })
        categories = categories.filter { id, c in
            referencedCategoryIDs.contains(id)
                || !(c.isDeleted && (c.deletedAt ?? .distantFuture) < cutoff)
        }
    }
}
