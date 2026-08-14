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

    /// Per-device cosmetic preference — deliberately NOT synced through the store. A field
    /// like this living inside a synced file would never converge: each device would keep
    /// rewriting the manifest with its own value, and the other device would see that as a
    /// genuine foreign change and write its own value right back, forever. Backed directly by
    /// UserDefaults rather than `@AppStorage` (a View-only property wrapper) so `@Observable`
    /// still instruments this as a normal stored property — the `Picker` binding in
    /// `ContentView` needs that. `_applyLoaded`/`applyInPlace` never touch this.
    var backgroundTheme: BackgroundTheme = AssetStore.loadBackgroundThemeFromDefaults() {
        didSet { UserDefaults.standard.set(backgroundTheme.rawValue, forKey: Self.backgroundThemeDefaultsKey) }
    }

    static let backgroundThemeDefaultsKey = "backgroundTheme"

    private static func loadBackgroundThemeFromDefaults() -> BackgroundTheme {
        UserDefaults.standard.string(forKey: backgroundThemeDefaultsKey).flatMap(BackgroundTheme.init) ?? .mist
    }

    /// Retained iCloud metadata query for remote-change monitoring. Set by startCloudMonitor().
    @ObservationIgnored
    var cloudQuery: NSMetadataQuery?

    /// Shards the store across many files on disk (one per asset, plus a few shared shards) and
    /// reassembles a snapshot on read. See `StoreFileLayout` for the on-disk shape and the
    /// failure policy that keeps a partial read from becoming a permanent deletion.
    @ObservationIgnored
    let fileLayout = StoreFileLayout()

    /// Pending debounced save task. Cancelled and replaced on each mutation.
    @ObservationIgnored
    private var saveTask: Task<Void, Never>?

    /// True while we have seeded in-memory data but have NOT yet confirmed the cloud
    /// container is empty. While set, save()/markDirty() are no-ops so seed data can
    /// never overwrite an unread cloud store. Not `@ObservationIgnored`: the Tools "waiting
    /// for iCloud" banner reads it directly and needs to react when it changes.
    var savesSuspended = false

    /// When this device last wrote to, or applied a foreign change from, the store — shown in
    /// Tools as a coarse sync status. `nil` until the first save or applied cloud change.
    var lastSyncDate: Date?

    /// True once this store's in-memory content has been confirmed authoritative — either
    /// loaded from disk, or seeded and explicitly un-suspended after confirming the cloud
    /// container was empty. False while `savesSuspended`: a freshly-seeded store must never be
    /// merged into a foreign snapshot, or its randomly-id'd seed data (categories, sample
    /// assets) would get unioned into the peer's real data instead of being replaced by it.
    var hasAuthoritativeLocalState: Bool { !savesSuspended }

    /// The whole-store digest (see `StoreFileLayout.storeDigest`) last written to, or read from,
    /// disk by this process — no longer literal bytes now that the store is many files, but the
    /// same role: the cloud monitor compares against this to tell foreign changes from echoes of
    /// our own saves — applying an echo would clobber newer in-memory mutations.
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

    // `isPurged` is checked alongside the tombstone, not because a purged record should ever
    // also be live — `hardDeleteAsset`/`purgeHardDeleted` always tombstone it first — but
    // because a purged record has no content left to show (a category's `name` is even blanked),
    // so it must stay invisible however it reached that state: an older build, a peer's sync, or
    // a hand-edited file. `deletedAssets`/`deletedCategories` exclude them for the same reason.
    var allAssets: [Asset] { assets.values.filter { !$0.isDeleted && !$0.isPurged } }
    var allCategories: [AssetCategory] { categories.values.filter { !$0.isDeleted && !$0.isPurged } }
    var deletedAssets: [Asset] { assets.values.filter { $0.isDeleted && !$0.isPurged } }
    var deletedCategories: [AssetCategory] { categories.values.filter { $0.isDeleted && !$0.isPurged } }
    var allCompositeTypes: [CompositeTypeDefinition] { Array(compositeTypes.values) }
    var allComboListDefinitions: [ComboListDefinition] { Array(comboListDefinitions.values) }

    /// Whether creating or restoring another asset is currently allowed under `assetCreationLimit`.
    var hasAssetCapacity: Bool { assetCreationLimit.map { allAssets.count < $0 } ?? true }

    /// Whether adding `n` more assets (e.g. a restored subtree) would stay within the limit.
    func hasCapacity(forAdditional n: Int) -> Bool {
        assetCreationLimit.map { allAssets.count + n <= $0 } ?? true
    }

    /// Whether adding another event to `asset` is currently allowed under `eventCreationLimit`.
    func hasEventCapacity(for asset: Asset) -> Bool {
        eventCreationLimit.map { asset.liveEvents.count < $0 } ?? true
    }

    /// Whether adding another transaction to `asset` is currently allowed under `transactionCreationLimit`.
    func hasTransactionCapacity(for asset: Asset) -> Bool {
        transactionCreationLimit.map { asset.liveTransactions.count < $0 } ?? true
    }

    // MARK: - AssetCategory CRUD

    @discardableResult
    func createCategory(id: UUID = UUID(), name: String, iconName: String = "square.grid.2x2", propertyTemplates: [AssetProperty] = []) throws -> AssetCategory {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if categories.values.contains(where: { !$0.isPurged && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            throw AssetStoreError.duplicateCategoryName(trimmed)
        }
        let cat = AssetCategory(id: id, name: trimmed, iconName: iconName, propertyTemplates: propertyTemplates)
        categories[cat.id] = cat
        markDirty()
        return cat
    }

    func updateCategory(id: UUID, name: String) throws {
        guard let cat = categories[id] else { throw AssetStoreError.categoryNotFound(id) }
        cat.name = name
        cat.modifyDate = Date()
        markDirty()
    }

    func updateCategoryIcon(id: UUID, iconName: String) throws {
        guard let cat = categories[id] else { throw AssetStoreError.categoryNotFound(id) }
        cat.iconName = iconName
        cat.modifyDate = Date()
        markDirty()
    }

    /// True removal — leaves no tombstone, so a peer that still has this category will union it
    /// straight back on the next sync. Not sync-safe; unused by app code, kept for tests only.
    /// See `hardDeleteCategory` for the sync-safe purge path.
    func deleteCategory(id: UUID) throws {
        guard categories[id] != nil else { throw AssetStoreError.categoryNotFound(id) }
        categories.removeValue(forKey: id)
        markDirty()
    }

    func softDeleteCategory(id: UUID) throws {
        guard let cat = categories[id] else { throw AssetStoreError.categoryNotFound(id) }
        let now = Date()
        cat.isDeleted = true
        cat.deletedAt = now
        cat.modifyDate = now
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
        prop.touch()
        markDirty()
    }

    func removeTemplatePropertyValue(forPropertyID propID: UUID, inCategoryID categoryID: UUID) throws {
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        guard let prop = cat.propertyTemplates.first(where: { $0.id == propID }) else {
            throw AssetStoreError.propertyNotFound(propID)
        }
        prop.value = nil
        prop.touch()
        markDirty()
    }

    /// Tombstones a template property on a category — does not affect existing assets, whose
    /// baseProperties were deep-copied at creation and are untouched by a later template edit.
    /// Soft, not a hard remove: an incoming sync/import that still has this template live must
    /// not resurrect it, which only works if the removal itself is a record the merge can see
    /// and a peer's later re-add can still outrace (see `SnapshotReconciler`'s per-template LWW).
    /// Reaped by `purgeHardDeleted` once its tombstone ages out, like every other soft delete.
    func removeTemplateProperty(id propID: UUID, fromCategoryID categoryID: UUID) throws {
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        guard let prop = cat.propertyTemplates.first(where: { $0.id == propID }) else {
            throw AssetStoreError.propertyNotFound(propID)
        }
        let now = Date()
        prop.isDeleted = true
        prop.deletedAt = now
        prop.touch(now)
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
        prop.touch()
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
        let baseProperties = cat.liveTemplates.enumerated().map { index, template in
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
        let now = Date()
        asset.name = name
        asset.modifiedDate = now
        asset.headModifyDate = now
        markDirty()
    }

    /// True removal — leaves no tombstone, so a peer that still has this asset will union it
    /// straight back on the next sync. Not sync-safe; unused by app code, kept for tests only.
    /// App code that needs to discard an asset for good should go through `softDeleteAsset`
    /// followed by `purgeHardDeleted`/`hardDeleteAsset`, which purge to a tombstone instead.
    func deleteAsset(id: UUID) throws {
        guard let asset = assets[id] else { throw AssetStoreError.assetNotFound(id) }
        let grandparent = asset.parent
        asset.parent?._removeChild(asset)
        for child in Array(asset.children) {
            asset._removeChild(child)
            grandparent?._addChild(child)
        }
        for photo in asset.photos { PhotoStorage.delete(id: photo.id) }
        assets.removeValue(forKey: id)
        notificationScheduler?.requestResync(assets: allAssets)
        markDirty()
    }

    /// Soft-deletes the asset and all of its descendants, preserving internal parent-child
    /// relationships until the records are hard-deleted by the retention sweep.
    /// The root is detached from its live parent; descendants stay linked to each other.
    func softDeleteAsset(id: UUID) throws {
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
            current.headModifyDate = now
        }
        notificationScheduler?.requestResync(assets: allAssets)
        markDirty()
    }

    /// Restores a soft-deleted asset and its entire subtree as top-level assets.
    /// Throws `freeLimitReached` if restoring the family would exceed the asset creation limit.
    func restoreAsset(id: UUID) throws {
        guard let asset = assets[id] else { throw AssetStoreError.assetNotFound(id) }
        // Nothing to restore once purged — the content is gone, so clearing the tombstone
        // would surface an empty husk. Mirrors the same guard in `restoreCategory`. Only
        // `importJSON`, which carries the content back with it, can undo a purge.
        guard !asset.isPurged else { return }
        let subtree = [asset] + asset.descendants
        if let limit = assetCreationLimit, allAssets.count + subtree.count > limit {
            throw AssetStoreError.freeLimitReached(limit: limit)
        }
        let now = Date()
        for node in subtree {
            node.isDeleted = false
            node.deletedAt = nil
            node.modifiedDate = now
            node.headModifyDate = now
        }
        notificationScheduler?.requestResync(assets: allAssets)
        markDirty()
    }

    /// Immediately purges a soft-deleted asset and its entire subtree to minimal tombstones,
    /// ignoring the retention window `purgeHardDeleted` normally waits out. See `purgeInPlace`.
    /// Soft-deletes first if the asset is still live: `purgeInPlace` only strips content — it
    /// deliberately leaves the tombstone alone, mirroring `SnapshotReconciler.stripPurged` — so
    /// without this an asset purged straight from live would carry no `deletedAt` for the reap
    /// sweep to age out, and peers would receive a stripped record that never reads as deleted.
    func hardDeleteAsset(id: UUID) throws {
        guard let asset = assets[id] else { throw AssetStoreError.assetNotFound(id) }
        if !asset.isDeleted { try softDeleteAsset(id: id) }
        let subtree = [asset] + asset.descendants
        for node in subtree { purgeInPlace(node) }
        notificationScheduler?.requestResync(assets: allAssets)
        markDirty()
    }

    func restoreCategory(id: UUID) throws {
        guard let cat = categories[id] else { throw AssetStoreError.categoryNotFound(id) }
        guard !cat.isPurged else { return }
        cat.isDeleted = false
        cat.deletedAt = nil
        cat.modifyDate = Date()
        markDirty()
    }

    /// Immediately purges a soft-deleted category to a minimal tombstone, ignoring the
    /// retention window `purgeHardDeleted` normally waits out. See `purgeCategoryInPlace`.
    /// Soft-deletes first if the category is still live, for the reason `hardDeleteAsset` does.
    func hardDeleteCategory(id: UUID) throws {
        guard let cat = categories[id] else { throw AssetStoreError.categoryNotFound(id) }
        if !cat.isDeleted { try softDeleteCategory(id: id) }
        purgeCategoryInPlace(cat)
        markDirty()
    }

    /// All assets belonging to the given category.
    func assets(ofCategoryID categoryID: UUID) throws -> [Asset] {
        guard categories[categoryID] != nil else { throw AssetStoreError.categoryNotFound(categoryID) }
        return assets.values.filter { $0.category.id == categoryID && !$0.isPurged }
    }

    /// Number of assets referencing this category, including soft-deleted ones.
    func associatedAssetCount(categoryID: UUID) -> Int {
        assets.values.filter { $0.category.id == categoryID && !$0.isPurged }.count
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
            let now = Date()
            prop.value = stored
            prop.touch(now)
            asset.modifiedDate = now
            markDirty()
            return prop
        }
        if let prop = asset.liveCustomProperties.first(where: { $0.definition.id == definitionID }) {
            try validate(stored: stored, against: prop.definition.type, definitionName: prop.definition.name)
            handleComboListAutoAdd(stored: stored, type: prop.definition.type)
            let now = Date()
            prop.value = stored
            prop.touch(now)
            asset.modifiedDate = now
            markDirty()
            return prop
        }
        throw AssetStoreError.definitionNotFound(definitionID)
    }

    /// Clears the value on a base or custom property. Does not remove the property itself.
    func removePropertyValue(forDefinitionID definitionID: UUID, fromAssetID assetID: UUID) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        if let prop = asset.baseProperties.first(where: { $0.definition.id == definitionID }) {
            let now = Date()
            prop.value = nil
            prop.touch(now)
            asset.modifiedDate = now
            markDirty()
            return
        }
        if let prop = asset.liveCustomProperties.first(where: { $0.definition.id == definitionID }) {
            let now = Date()
            prop.value = nil
            prop.touch(now)
            asset.modifiedDate = now
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
        guard let prop = asset.liveCustomProperties.first(where: { $0.id == propID }) else {
            throw AssetStoreError.propertyNotFound(propID)
        }
        try validate(stored: stored, against: prop.definition.type, definitionName: prop.definition.name)
        let now = Date()
        prop.value = stored
        prop.touch(now)
        asset.modifiedDate = now
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
        guard let prop = asset.liveCustomProperties.first(where: { $0.id == propID }) else {
            throw AssetStoreError.propertyNotFound(propID)
        }
        if let name { prop.definition.name = name }
        if let isRequired { prop.definition.isRequired = isRequired }
        if let type {
            prop.definition.type = type
            prop.value = nil
        }
        let now = Date()
        prop.touch(now)
        asset.modifiedDate = now
        markDirty()
    }

    /// Tombstones a custom property. The record stays in `customProperties` until
    /// `purgeHardDeleted` reaps it — deleting it outright would make the delete invisible to
    /// sync and let a peer's copy resurrect it on the next merge.
    func removeCustomProperty(id propID: UUID, fromAssetID assetID: UUID) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        guard let prop = asset.liveCustomProperties.first(where: { $0.id == propID }) else {
            throw AssetStoreError.propertyNotFound(propID)
        }
        let now = Date()
        prop.isDeleted = true
        prop.deletedAt = now
        prop.touch(now)
        asset.modifiedDate = now
        markDirty()
    }

    // MARK: - ComboListDefinition CRUD

    @discardableResult
    func createComboList(
        id: UUID = UUID(),
        name: String,
        systemOptions: [String] = [],
        userOptions: [String] = [],
        isUserExtensible: Bool = true
    ) -> ComboListDefinition {
        let cl = ComboListDefinition(id: id, name: name, systemOptions: systemOptions, userOptions: userOptions, isUserExtensible: isUserExtensible)
        comboListDefinitions[cl.id] = cl
        markDirty()
        return cl
    }

    func updateComboList(id: UUID, name: String) throws {
        guard let cl = comboListDefinitions[id] else { throw AssetStoreError.comboListNotFound(id) }
        cl.name = name
        cl.modifyDate = Date()
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
        cl.modifyDate = Date()
        markDirty()
    }

    func removeUserOption(_ option: String, fromComboListID id: UUID) throws {
        guard let cl = comboListDefinitions[id] else { throw AssetStoreError.comboListNotFound(id) }
        guard cl.isUserExtensible else { throw AssetStoreError.comboListNotExtensible(id) }
        guard !cl.systemOptions.contains(option) else {
            throw AssetStoreError.cannotModifySystemOption(listID: id, option: option)
        }
        cl.userOptions.removeAll { $0 == option }
        cl.modifyDate = Date()
        markDirty()
    }

    // MARK: - CompositeTypeDefinition CRUD

    @discardableResult
    func createCompositeType(
        id: UUID = UUID(),
        name: String,
        fields: [PropertyDefinition] = [],
        labelHint: String? = nil
    ) -> CompositeTypeDefinition {
        let ct = CompositeTypeDefinition(id: id, name: name, fields: fields, labelHint: labelHint)
        compositeTypes[ct.id] = ct
        markDirty()
        return ct
    }

    func updateCompositeType(id: UUID, name: String) throws {
        guard let ct = compositeTypes[id] else { throw AssetStoreError.compositeTypeNotFound(id) }
        ct.name = name
        ct.modifyDate = Date()
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
        ct.modifyDate = Date()
        markDirty()
        return field
    }

    func removeField(id fieldID: UUID, fromCompositeTypeID typeID: UUID) throws {
        guard let ct = compositeTypes[typeID] else { throw AssetStoreError.compositeTypeNotFound(typeID) }
        guard ct.fields.contains(where: { $0.id == fieldID }) else {
            throw AssetStoreError.definitionNotFound(fieldID)
        }
        ct.fields.removeAll { $0.id == fieldID }
        ct.modifyDate = Date()
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
        ct.modifyDate = Date()
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
        guard let photo = asset.livePhotos.first(where: { $0.id == photoID }) else { throw AssetStoreError.photoNotFound(photoID) }
        let now = Date()
        photo.caption = caption
        photo.touch(now)
        asset.modifiedDate = now
        markDirty()
    }

    /// Tombstones the photo. The JPEG files stay on disk until `purgeHardDeleted` reaps the
    /// tombstone — deleting bytes now would destroy them while the tombstone is still syncing,
    /// and a peer that hasn't seen the delete yet would render a photo with no image.
    func removePhoto(id photoID: UUID, fromAssetID assetID: UUID) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        guard let photo = asset.livePhotos.first(where: { $0.id == photoID }) else { throw AssetStoreError.photoNotFound(photoID) }
        let now = Date()
        photo.isDeleted = true
        photo.deletedAt = now
        photo.touch(now)
        asset.modifiedDate = now
        markDirty()
    }

    @discardableResult
    func addEvent(title: String, date: Date, notes: String = "", recurrence: RecurrenceInterval? = nil, toAssetID assetID: UUID) throws -> Event {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        if let limit = eventCreationLimit, asset.liveEvents.count >= limit {
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
        guard let event = asset.liveEvents.first(where: { $0.id == eventID }) else { throw AssetStoreError.eventNotFound(eventID) }
        let now = Date()
        event.title = title
        event.date = date
        event.notes = notes
        event.recurrence = recurrence
        event.touch(now)
        asset.modifiedDate = now
        notificationScheduler?.requestResync(assets: allAssets)
        markDirty()
    }

    func removeEvent(id eventID: UUID, fromAssetID assetID: UUID) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        guard let event = asset.liveEvents.first(where: { $0.id == eventID }) else { throw AssetStoreError.eventNotFound(eventID) }
        let now = Date()
        event.isDeleted = true
        event.deletedAt = now
        event.touch(now)
        asset.modifiedDate = now
        notificationScheduler?.requestResync(assets: allAssets)
        markDirty()
    }

    @discardableResult
    func addTransaction(details: String, amount: Decimal, date: Date, kind: TransactionKind, payeeContactID: String? = nil, notes: String = "", recurrence: RecurrenceInterval? = nil, toAssetID assetID: UUID) throws -> Transaction {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        if let limit = transactionCreationLimit, asset.liveTransactions.count >= limit {
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
        guard let txn = asset.liveTransactions.first(where: { $0.id == txnID }) else { throw AssetStoreError.transactionNotFound(txnID) }
        let now = Date()
        txn.details = details
        txn.amount = abs(amount)
        txn.date = date
        txn.kind = kind
        txn.payeeContactID = payeeContactID
        txn.notes = notes
        txn.recurrence = recurrence
        txn.touch(now)
        asset.modifiedDate = now
        notificationScheduler?.requestResync(assets: allAssets)
        markDirty()
    }

    func removeTransaction(id txnID: UUID, fromAssetID assetID: UUID) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        guard let txn = asset.liveTransactions.first(where: { $0.id == txnID }) else { throw AssetStoreError.transactionNotFound(txnID) }
        let now = Date()
        txn.isDeleted = true
        txn.deletedAt = now
        txn.touch(now)
        asset.modifiedDate = now
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
        list.modifyDate = Date()
    }

    // MARK: - Persistence internals
    // These must live here to write private(set) storage properties.

    enum ColdStartAction { case useLoaded, seedAndPersist, seedSuspended }

    static func coldStartAction(loaded: Bool, iCloudActive: Bool) -> ColdStartAction {
        if loaded { return .useLoaded }
        return iCloudActive ? .seedSuspended : .seedAndPersist
    }

    /// Schedules a background save ~2 s after the last mutation. Cancels and replaces
    /// any pending save, so rapid mutations collapse into one write.
    func markDirty() {
        guard !savesSuspended else { return }
        saveTask?.cancel()
        saveTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.save()
        }
    }

    /// Replaces in-memory state with the decoded snapshot. Called on the main thread.
    /// `backgroundTheme` is deliberately not a parameter here — it's UserDefaults-backed, not
    /// part of the loaded/replaced store state; see its doc comment.
    func _applyLoaded(
        compositeTypes: [UUID: CompositeTypeDefinition],
        comboLists: [UUID: ComboListDefinition],
        categories: [UUID: AssetCategory],
        assets: [UUID: Asset],
        activityLog: [ActivityLogEntry]
    ) {
        self.compositeTypes = compositeTypes
        self.comboListDefinitions = comboLists
        self.categories = categories
        self.assets = assets
        self.activityLog = activityLog
    }

    /// Inserts new records into the store's maps. Existing records are mutated directly by
    /// `applyInPlace` — they're reference types, so only insertion needs write access to these
    /// `private(set)` maps. Never removes anything; absence is never a delete.
    func _upsertLoaded(
        compositeTypes: [CompositeTypeDefinition] = [],
        comboLists: [ComboListDefinition] = [],
        categories: [AssetCategory] = [],
        assets: [Asset] = []
    ) {
        for ct in compositeTypes { self.compositeTypes[ct.id] = ct }
        for cl in comboLists { self.comboListDefinitions[cl.id] = cl }
        for cat in categories { self.categories[cat.id] = cat }
        for a in assets { self.assets[a.id] = a }
    }

    /// Union by id — entries are immutable, so unlike `_upsertLoaded` there's nothing to
    /// mutate in place, only append what's missing. Called by `applyInPlace`.
    func _upsertActivityLog(_ entries: [ActivityLogEntry]) {
        var seen = Set(activityLog.map(\.id))
        for entry in entries where !seen.contains(entry.id) {
            activityLog.append(entry)
            seen.insert(entry.id)
        }
        activityLog.sort { $0.timestamp < $1.timestamp }
    }

    /// Strips an asset down to a minimal tombstone — `id`, `name`, `categoryID`, and its
    /// timestamps survive; every photo file is deleted, and `photos`/`events`/`transactions`/
    /// `customProperties`/`baseProperties` are emptied and the asset is detached from its
    /// parent and children. The record itself is never removed: `applyInPlace`/`_upsertLoaded`
    /// can only insert, never delete, so a real removal here would be silently resurrected the
    /// next time a peer that still has the full asset syncs. Keeping the (now-tiny) record
    /// around with `isPurged = true` is what makes the strip visible to that peer instead.
    /// Idempotent — safe to call on an already-purged asset. Called only on assets already
    /// soft-deleted; see `purgeHardDeleted` and `hardDeleteAsset`. Not `private`: `applyInPlace`
    /// (`AssetStore+Persistence.swift`) also calls it, to replace rather than additively merge
    /// content on a local asset a peer has already purged.
    func purgeInPlace(_ asset: Asset) {
        guard !asset.isPurged else { return }
        for photo in asset.photos { PhotoStorage.delete(id: photo.id) }
        asset.photos = []
        asset.events = []
        asset.transactions = []
        asset.customProperties = []
        asset.baseProperties = []
        asset.parent?._removeChild(asset, stampParentage: false)
        for child in Array(asset.children) {
            asset._removeChild(child, stampParentage: false)
        }
        asset.isPurged = true
    }

    /// Strips a category down to a minimal tombstone — `id`, tombstone, and `modifyDate`
    /// survive; `name` and `iconName` are blanked to `""` and `propertyTemplates` emptied.
    /// The record itself is never removed, for the same reason `purgeInPlace` keeps the asset
    /// record: `applyInPlace`/`_upsertLoaded` can only insert, never delete, so a real removal
    /// here would be silently resurrected the next time a peer that still has the full category
    /// syncs. Blanking rather than keeping the name (unlike `purgeInPlace`) is safe because
    /// nothing ever displays a purged category — `deletedCategories` filters them out.
    /// Idempotent — safe to call on an already-purged category. Called only on categories
    /// already soft-deleted; see `purgeHardDeleted` and `hardDeleteCategory`. Not `private`:
    /// `applyInPlace` (`AssetStore+Persistence.swift`) also calls it, to replace rather than
    /// additively merge templates on a local category a peer has already purged.
    func purgeCategoryInPlace(_ category: AssetCategory) {
        guard !category.isPurged else { return }
        category.name = ""
        category.iconName = ""
        category.propertyTemplates = []
        category.isPurged = true
    }

    /// Purges soft-deleted assets and categories whose deletedAt is older than `seconds` to
    /// minimal tombstones (see `purgeInPlace`/`purgeCategoryInPlace`) — never removes the
    /// record — then the same age-based reaping as before for tombstoned
    /// events/transactions/photos/custom properties inside assets that are not (yet) purged,
    /// and for aged-out category property-template tombstones on categories that are not (yet)
    /// purged. Categories are evaluated after assets — a category kept alive only by a
    /// now-purged asset is eligible for purging in the same sweep, since a purged asset no
    /// longer counts as a reference. Categories still referenced by any non-purged asset are
    /// retained regardless of age to avoid dangling categoryIDs. Old activity-log entries whose
    /// owning asset is gone or purged are dropped once their own timestamp ages past cutoff —
    /// mirrors `SnapshotReconciler.reap`, so a local sweep and a sync merge converge.
    func purgeHardDeleted(olderThan seconds: TimeInterval = 90 * 86_400) {
        let cutoff = Date().addingTimeInterval(-seconds)
        for asset in assets.values
        where asset.isDeleted && (asset.deletedAt ?? .distantFuture) < cutoff && !asset.isPurged {
            purgeInPlace(asset)
        }
        // Photo bytes are freed here rather than at removePhoto time so a peer that hasn't
        // seen the delete can still resolve the file for the life of the tombstone.
        for asset in assets.values where !asset.isPurged {
            for photo in asset.photos where Self.isExpiredTombstone(photo.isDeleted, photo.deletedAt, before: cutoff) {
                PhotoStorage.delete(id: photo.id)
            }
            asset.photos.removeAll { Self.isExpiredTombstone($0.isDeleted, $0.deletedAt, before: cutoff) }
            asset.events.removeAll { Self.isExpiredTombstone($0.isDeleted, $0.deletedAt, before: cutoff) }
            asset.transactions.removeAll { Self.isExpiredTombstone($0.isDeleted, $0.deletedAt, before: cutoff) }
            asset.customProperties.removeAll { Self.isExpiredTombstone($0.isDeleted, $0.deletedAt, before: cutoff) }
        }
        for category in categories.values where !category.isPurged {
            category.propertyTemplates.removeAll {
                Self.isExpiredTombstone($0.isDeleted, $0.deletedAt, before: cutoff)
            }
        }
        let referencedCategoryIDs = Set(assets.values.filter { !$0.isPurged }.map { $0.category.id })
        for category in categories.values
        where category.isDeleted && (category.deletedAt ?? .distantFuture) < cutoff
            && !referencedCategoryIDs.contains(category.id) {
            purgeCategoryInPlace(category)
        }
        activityLog.removeAll { entry in
            let referenced = entry.owningAssetID ?? (entry.kind == .asset ? entry.recordID : nil)
            guard let referenced else { return false }
            let owner = assets[referenced]
            return (owner == nil || owner!.isPurged) && entry.timestamp < cutoff
        }
        notificationScheduler?.requestResync(assets: allAssets)
    }

    /// A tombstone with no `deletedAt` is never expired — the same guard the asset and
    /// category sweeps above have always used.
    private static func isExpiredTombstone(_ isDeleted: Bool, _ deletedAt: Date?, before cutoff: Date) -> Bool {
        isDeleted && (deletedAt ?? .distantFuture) < cutoff
    }
}
