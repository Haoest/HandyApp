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
    /// Attempted to create an asset at an id already present in the store — belt-and-braces
    /// against silently replacing a live or purged record. See `createAsset`'s doc comment.
    case duplicateAssetID(UUID)
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
    /// `ToolsView` needs that. `_applyLoaded`/`applyInPlace` never touch this.
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

    /// True when the on-disk store, or a snapshot that arrived via cloud sync, was written by a
    /// newer build — its schemaVersion exceeds this code's `storeSchemaVersion`. While set,
    /// `save()`/`markDirty()` are no-ops: this build would decode-drop DTO fields it doesn't
    /// know about, and `buildSnapshot()` always stamps its own (older) `storeSchemaVersion`, so
    /// writing would silently strip the newer build's data and re-stamp the manifest down. The
    /// store still loads and displays read-only. Not persisted — re-derived from the manifest
    /// on every launch. Not `@ObservationIgnored`: `ContentView`'s banner and `ToolsView`'s
    /// status line read it directly. Cleared only by `factoryReset` (an explicit, confirmed
    /// destructive act) or by relaunching on a build whose `storeSchemaVersion` has caught up.
    var storeRequiresNewerApp = false

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
    /// Live combo lists, for pickers. `comboListDefinitions` itself (the raw dict) must keep
    /// soft-deleted entries — `resolvePropertyType` looks a property's type up there, and if a
    /// referenced list were missing entirely the property would decode to nil and silently drop
    /// (see `AssetStore+Persistence.propertyDefinition(from:)`). Filtering only here keeps that
    /// resolution intact while hiding deleted lists from UI that lists choices to pick from.
    var allComboListDefinitions: [ComboListDefinition] { comboListDefinitions.values.filter { !$0.isDeleted } }
    var deletedComboListDefinitions: [ComboListDefinition] { comboListDefinitions.values.filter { $0.isDeleted } }

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
        let trimmed = TextLimits.clamp(name.trimmingCharacters(in: .whitespaces), to: TextLimits.categoryName)
        if categories.values.contains(where: { !$0.isPurged && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            throw AssetStoreError.duplicateCategoryName(trimmed)
        }
        for template in propertyTemplates {
            template.definition.name = TextLimits.clamp(template.definition.name, to: TextLimits.propertyName)
            if let ml = template.definition.maxLength { template.definition.maxLength = Self.clampedMaxLength(ml) }
            if let value = template.value {
                let clamped = Self.clampedTextValue(value, for: template.definition)
                template.value = clamped
                handleComboListAutoAdd(stored: clamped, type: template.definition.type)
            }
        }
        let cat = AssetCategory(id: id, name: trimmed, iconName: iconName, propertyTemplates: propertyTemplates)
        categories[cat.id] = cat
        markDirty()
        return cat
    }

    func updateCategory(id: UUID, name: String) throws {
        guard let cat = categories[id] else { throw AssetStoreError.categoryNotFound(id) }
        cat.name = TextLimits.clamp(name, to: TextLimits.categoryName)
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

    /// Appends a new property template to an existing category, honoring whatever `sortOrder`
    /// the caller put on `property` — used by `upgradeBuiltInCategories`, which places a newly
    /// shipped built-in field at its declared position rather than at the end.
    @discardableResult
    func addTemplateProperty(_ property: AssetProperty, toCategoryID categoryID: UUID) throws -> AssetProperty {
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        if let value = property.value {
            handleComboListAutoAdd(stored: value, type: property.definition.type)
        }
        cat.propertyTemplates.append(property)
        markDirty()
        return property
    }

    /// Adds a new property template to an existing category, placed after every template the
    /// category already has (`SortOrdering.next`). This is the path the "＋" button on the
    /// category screen uses — `addTemplateProperty` above is for a caller that already knows
    /// where the new field belongs.
    @discardableResult
    func appendTemplateProperty(definition: PropertyDefinition, value: StoredValue? = nil, toCategoryID categoryID: UUID) throws -> AssetProperty {
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        var definition = definition
        definition.name = TextLimits.clamp(definition.name, to: TextLimits.propertyName)
        if let ml = definition.maxLength { definition.maxLength = Self.clampedMaxLength(ml) }
        let value = value.map { Self.clampedTextValue($0, for: definition) }
        let sortOrder = SortOrdering.next(after: cat.propertyTemplates.map(\.sortOrder))
        let prop = AssetProperty(definition: definition, value: value, sortOrder: sortOrder)
        return try addTemplateProperty(prop, toCategoryID: categoryID)
    }

    /// Reorders a category's property templates: `fromOffsets`/`toOffset` index the same
    /// sorted, live list `CategoryEditorView` renders (`SwiftUI`'s `.onMove` convention).
    func moveTemplateProperties(fromOffsets: IndexSet, toOffset: Int, inCategoryID categoryID: UUID) throws {
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        let writes = Self.moveWrites(fromOffsets: fromOffsets, toOffset: toOffset, live: cat.liveTemplates.sorted(by: SortOrdering.precedes))
        guard !writes.isEmpty else { return }
        let now = Date()
        var byID: [UUID: AssetProperty] = [:]
        for prop in cat.propertyTemplates { byID[prop.id] = prop }
        for (id, sortOrder) in writes {
            guard let prop = byID[id] else { continue }
            prop.sortOrder = sortOrder
            prop.touch(now)
        }
        markDirty()
    }

    func setTemplatePropertyValue(_ stored: StoredValue, forPropertyID propID: UUID, inCategoryID categoryID: UUID) throws {
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        guard let prop = cat.propertyTemplates.first(where: { $0.id == propID }) else {
            throw AssetStoreError.propertyNotFound(propID)
        }
        let clamped = Self.clampedTextValue(stored, for: prop.definition)
        try validate(stored: clamped, against: prop.definition.type, definitionName: prop.definition.name)
        handleComboListAutoAdd(stored: clamped, type: prop.definition.type)
        prop.value = clamped
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

    /// Tombstones a template property on a category — does not by itself affect existing assets,
    /// whose baseProperties were deep-copied at creation and stay untouched by a later template
    /// edit unless the user explicitly runs `propagateTemplates(forCategoryID:)`
    /// (`AssetStore+TemplatePropagation.swift`) to reconcile them.
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
        type: PropertyType? = nil,
        isRequired: Bool? = nil,
        maxLength: Int? = nil
    ) throws {
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        guard let prop = cat.propertyTemplates.first(where: { $0.id == propID }) else {
            throw AssetStoreError.propertyNotFound(propID)
        }
        if let name { prop.definition.name = TextLimits.clamp(name, to: TextLimits.propertyName) }
        if let type, type != prop.definition.type {
            prop.definition.type = type
            prop.value = nil
        }
        if let isRequired { prop.definition.isRequired = isRequired }
        if let maxLength {
            prop.definition.maxLength = Self.clampedMaxLength(maxLength)
            if let value = prop.value {
                prop.value = Self.clampedTextValue(value, for: prop.definition)
            }
        }
        prop.touch()
        markDirty()
    }

    // MARK: - Asset CRUD

    /// Creates an Asset, deep-copying the category's property templates into baseProperties.
    /// A later template edit does not retroactively reach this asset — see
    /// `propagateTemplates(forCategoryID:)` for the explicit, user-triggered reconciliation.
    ///
    /// `id` defaults to a fresh random `UUID`, matching `createCategory`/`createComboList`/
    /// `createCompositeType`. Pass an explicit id only for a deterministically-seeded record
    /// (see `BuiltInTypes.assetSeeds`) — the id must not already be present in `assets` in any
    /// state, including a purged husk: silently replacing one destroys a tombstone that peers
    /// depend on to receive a wipe (see `factoryReset`'s husk comment), which is a stronger
    /// failure than an ordinary duplicate. The real guarantee against that lives in the caller
    /// (`BuiltInTypes.resolveBuiltInAsset` never calls this with an occupied id); this guard is
    /// belt-and-braces.
    @discardableResult
    func createAsset(id: UUID = UUID(), name: String, categoryID: UUID) throws -> Asset {
        guard assets[id] == nil else { throw AssetStoreError.duplicateAssetID(id) }
        if let limit = assetCreationLimit, allAssets.count >= limit {
            throw AssetStoreError.freeLimitReached(limit: limit)
        }
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        // Copies the template's own `sortOrder` rather than deriving one from array position,
        // so a freshly created asset matches whatever order the category's templates were
        // reordered into.
        let baseProperties = cat.liveTemplates.map { template in
            AssetProperty(definition: template.definition, value: template.value, sortOrder: template.sortOrder)
        }
        let asset = Asset(id: id, name: TextLimits.clamp(name, to: TextLimits.assetName), category: cat, baseProperties: baseProperties)
        assets[asset.id] = asset
        logCreation(of: asset.id, kind: .asset)
        markDirty()
        return asset
    }

    func updateAsset(id: UUID, name: String) throws {
        guard let asset = assets[id] else { throw AssetStoreError.assetNotFound(id) }
        let now = Date()
        asset.name = TextLimits.clamp(name, to: TextLimits.assetName)
        asset.modifiedDate = now
        asset.headModifyDate = now
        notificationScheduler?.requestResync(assets: allAssets)
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
        if let prop = asset.liveBaseProperties.first(where: { $0.definition.id == definitionID }) {
            let clamped = Self.clampedTextValue(stored, for: prop.definition)
            try validate(stored: clamped, against: prop.definition.type, definitionName: prop.definition.name)
            handleComboListAutoAdd(stored: clamped, type: prop.definition.type)
            let now = Date()
            prop.value = clamped
            prop.touch(now)
            asset.modifiedDate = now
            markDirty()
            return prop
        }
        if let prop = asset.liveCustomProperties.first(where: { $0.definition.id == definitionID }) {
            let clamped = Self.clampedTextValue(stored, for: prop.definition)
            try validate(stored: clamped, against: prop.definition.type, definitionName: prop.definition.name)
            handleComboListAutoAdd(stored: clamped, type: prop.definition.type)
            let now = Date()
            prop.value = clamped
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
        if let prop = asset.liveBaseProperties.first(where: { $0.definition.id == definitionID }) {
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

    /// Adds a new per-asset custom property with an optional initial value. Placed after every
    /// custom property the asset already has (`SortOrdering.next`), against the raw array —
    /// matching `appendMissingProperties`' convention on the sync-import path — so a new field
    /// lands at the bottom instead of tying at 0 with every other custom property.
    @discardableResult
    func addCustomProperty(
        definition: PropertyDefinition,
        value: StoredValue? = nil,
        toAssetID assetID: UUID
    ) throws -> AssetProperty {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        var definition = definition
        definition.name = TextLimits.clamp(definition.name, to: TextLimits.propertyName)
        if let ml = definition.maxLength { definition.maxLength = Self.clampedMaxLength(ml) }
        var value = value
        if let stored = value {
            let clamped = Self.clampedTextValue(stored, for: definition)
            try validate(stored: clamped, against: definition.type, definitionName: definition.name)
            handleComboListAutoAdd(stored: clamped, type: definition.type)
            value = clamped
        }
        let sortOrder = SortOrdering.next(after: asset.customProperties.map(\.sortOrder))
        let prop = AssetProperty(definition: definition, value: value, sortOrder: sortOrder)
        asset.customProperties.append(prop)
        asset.modifiedDate = Date()
        markDirty()
        return prop
    }

    /// Reorders an asset's base (category-derived) properties: `fromOffsets`/`toOffset` index
    /// the same sorted, live list the Specs tab renders.
    func moveBaseProperties(fromOffsets: IndexSet, toOffset: Int, onAssetID assetID: UUID) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        let writes = Self.moveWrites(fromOffsets: fromOffsets, toOffset: toOffset, live: asset.liveBaseProperties.sorted(by: SortOrdering.precedes))
        guard !writes.isEmpty else { return }
        let now = Date()
        var byID: [UUID: AssetProperty] = [:]
        for prop in asset.baseProperties { byID[prop.id] = prop }
        for (id, sortOrder) in writes {
            guard let prop = byID[id] else { continue }
            prop.sortOrder = sortOrder
            prop.touch(now)
        }
        asset.modifiedDate = now
        markDirty()
    }

    /// Reorders an asset's custom properties: `fromOffsets`/`toOffset` index the same sorted,
    /// live list the Specs tab renders.
    func moveCustomProperties(fromOffsets: IndexSet, toOffset: Int, onAssetID assetID: UUID) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        let writes = Self.moveWrites(fromOffsets: fromOffsets, toOffset: toOffset, live: asset.liveCustomProperties.sorted(by: SortOrdering.precedes))
        guard !writes.isEmpty else { return }
        let now = Date()
        var byID: [UUID: AssetProperty] = [:]
        for prop in asset.customProperties { byID[prop.id] = prop }
        for (id, sortOrder) in writes {
            guard let prop = byID[id] else { continue }
            prop.sortOrder = sortOrder
            prop.touch(now)
        }
        asset.modifiedDate = now
        markDirty()
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
        let clamped = Self.clampedTextValue(stored, for: prop.definition)
        try validate(stored: clamped, against: prop.definition.type, definitionName: prop.definition.name)
        handleComboListAutoAdd(stored: clamped, type: prop.definition.type)
        let now = Date()
        prop.value = clamped
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
        isRequired: Bool? = nil,
        maxLength: Int? = nil
    ) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        guard let prop = asset.liveCustomProperties.first(where: { $0.id == propID }) else {
            throw AssetStoreError.propertyNotFound(propID)
        }
        if let name { prop.definition.name = TextLimits.clamp(name, to: TextLimits.propertyName) }
        if let isRequired { prop.definition.isRequired = isRequired }
        if let type, type != prop.definition.type {
            prop.definition.type = type
            prop.value = nil
        }
        if let maxLength {
            prop.definition.maxLength = Self.clampedMaxLength(maxLength)
            if let value = prop.value {
                prop.value = Self.clampedTextValue(value, for: prop.definition)
            }
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

    /// Trims and drops blank entries from `systemOptions`/`userOptions` — a combo list option
    /// is meaningless empty, and every render site (`ComboListField`, the option pickers) would
    /// otherwise have to defend against a stray blank pill.
    private static func sanitizedOptions(_ options: [String]) -> [String] {
        options
            .map { TextLimits.clamp($0.trimmingCharacters(in: .whitespaces), to: TextLimits.comboListOption) }
            .filter { !$0.isEmpty }
    }

    @discardableResult
    func createComboList(
        id: UUID = UUID(),
        name: String,
        systemOptions: [String] = [],
        userOptions: [String] = [],
        isUserExtensible: Bool = true
    ) -> ComboListDefinition {
        let cl = ComboListDefinition(
            id: id, name: TextLimits.clamp(name, to: TextLimits.comboListName),
            systemOptions: Self.sanitizedOptions(systemOptions),
            userOptions: Self.sanitizedOptions(userOptions),
            isUserExtensible: isUserExtensible
        )
        comboListDefinitions[cl.id] = cl
        markDirty()
        return cl
    }

    func updateComboList(id: UUID, name: String) throws {
        guard let cl = comboListDefinitions[id] else { throw AssetStoreError.comboListNotFound(id) }
        cl.name = TextLimits.clamp(name, to: TextLimits.comboListName)
        cl.modifyDate = Date()
        markDirty()
    }

    /// Turns off-list answers on or off. When off, `handleComboListAutoAdd` stops appending
    /// typed values, so the list becomes a closed set — existing values already stored on
    /// assets are left alone, since narrowing the list must not silently blank them.
    func setComboListExtensible(id: UUID, _ isUserExtensible: Bool) throws {
        guard let cl = comboListDefinitions[id] else { throw AssetStoreError.comboListNotFound(id) }
        guard cl.isUserExtensible != isUserExtensible else { return }
        cl.isUserExtensible = isUserExtensible
        cl.modifyDate = Date()
        markDirty()
    }

    /// Case-insensitive uniqueness check over live lists, for the authoring UI.
    /// `createComboList` itself does not enforce this (it's also the seeder's entry point).
    func comboListNameIsAvailable(_ name: String, excluding id: UUID? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !allComboListDefinitions.contains {
            $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    /// Tombstones a combo list. Live properties that reference it are unaffected — see
    /// `allComboListDefinitions`'s doc comment — so any asset already using it keeps its value
    /// and options. Never auto-purged; see `purgeHardDeleted`'s doc comment.
    func softDeleteComboList(id: UUID) throws {
        guard let cl = comboListDefinitions[id] else { throw AssetStoreError.comboListNotFound(id) }
        let now = Date()
        cl.isDeleted = true
        cl.deletedAt = now
        cl.modifyDate = now
        markDirty()
    }

    func restoreComboList(id: UUID) throws {
        guard let cl = comboListDefinitions[id] else { throw AssetStoreError.comboListNotFound(id) }
        cl.isDeleted = false
        cl.deletedAt = nil
        cl.modifyDate = Date()
        markDirty()
    }

    /// True removal — leaves no tombstone, so a peer that still has this list will union it
    /// straight back on the next sync, and any property still typed on it silently drops (see
    /// `allComboListDefinitions`'s doc comment). Not sync-safe; never call from UI — use
    /// `softDeleteComboList`. Kept for tests only.
    func deleteComboList(id: UUID) throws {
        guard comboListDefinitions[id] != nil else { throw AssetStoreError.comboListNotFound(id) }
        comboListDefinitions.removeValue(forKey: id)
        markDirty()
    }

    /// `isUserExtensible` governs whether an end user typing a value into a `ComboListField`
    /// gets it auto-added (see `handleComboListAutoAdd`) — it does not gate definition-authoring
    /// UI, which must be able to curate options on any list regardless of that flag.
    func addUserOption(_ option: String, toComboListID id: UUID) throws {
        guard let cl = comboListDefinitions[id] else { throw AssetStoreError.comboListNotFound(id) }
        let trimmed = TextLimits.clamp(option.trimmingCharacters(in: .whitespaces), to: TextLimits.comboListOption)
        guard !trimmed.isEmpty, !cl.allOptions.contains(trimmed) else { return }
        cl.userOptions.append(trimmed)
        cl.modifyDate = Date()
        markDirty()
    }

    func removeUserOption(_ option: String, fromComboListID id: UUID) throws {
        guard let cl = comboListDefinitions[id] else { throw AssetStoreError.comboListNotFound(id) }
        guard !cl.systemOptions.contains(option) else {
            throw AssetStoreError.cannotModifySystemOption(listID: id, option: option)
        }
        cl.userOptions.removeAll { $0 == option }
        cl.modifyDate = Date()
        markDirty()
    }

    /// Moves a user option one place up or down within `userOptions`, which is what the pick
    /// list editor's ↑/↓ buttons drive. System options are fixed at the head of `allOptions`
    /// and are not part of this ordering.
    ///
    /// Order is not a merged field: `SnapshotReconciler.joinComboList` takes the winning side's
    /// `userOptions` wholesale and appends only what the loser had that the winner lacked, so a
    /// reorder that races a peer's reorder resolves to one side's arrangement rather than an
    /// interleaving. Options are never lost either way.
    func moveUserOption(_ option: String, inComboListID id: UUID, by offset: Int) throws {
        guard let cl = comboListDefinitions[id] else { throw AssetStoreError.comboListNotFound(id) }
        guard let index = cl.userOptions.firstIndex(of: option) else { return }
        let destination = index + offset
        guard destination >= 0, destination < cl.userOptions.count else { return }
        cl.userOptions.remove(at: index)
        cl.userOptions.insert(option, at: destination)
        cl.modifyDate = Date()
        markDirty()
    }

    /// Renames a user option in place, preserving its position — the authoring UI's tap-to-edit
    /// flow needs this rather than a remove+append, which would move the edited option to the
    /// end of the list. A no-op if `oldOption` isn't a current user option. If `newOption`
    /// collides with another option already on the list, the old entry is simply dropped rather
    /// than creating a duplicate.
    func renameUserOption(_ oldOption: String, to newOption: String, inComboListID id: UUID) throws {
        guard let cl = comboListDefinitions[id] else { throw AssetStoreError.comboListNotFound(id) }
        guard !cl.systemOptions.contains(oldOption) else {
            throw AssetStoreError.cannotModifySystemOption(listID: id, option: oldOption)
        }
        guard let idx = cl.userOptions.firstIndex(of: oldOption) else { return }
        let trimmed = TextLimits.clamp(newOption.trimmingCharacters(in: .whitespaces), to: TextLimits.comboListOption)
        guard !trimmed.isEmpty, trimmed != oldOption else { return }
        if cl.allOptions.contains(trimmed) {
            cl.userOptions.remove(at: idx)
        } else {
            cl.userOptions[idx] = trimmed
        }
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
        ct.name = TextLimits.clamp(name, to: TextLimits.compositeTypeName)
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
        isRequired: Bool? = nil,
        maxLength: Int? = nil
    ) throws {
        guard let ct = compositeTypes[typeID] else { throw AssetStoreError.compositeTypeNotFound(typeID) }
        guard let idx = ct.fields.firstIndex(where: { $0.id == fieldID }) else {
            throw AssetStoreError.definitionNotFound(fieldID)
        }
        if let name       { ct.fields[idx].name       = TextLimits.clamp(name, to: TextLimits.propertyName) }
        if let type, type != ct.fields[idx].type { ct.fields[idx].type = type }
        if let isRequired { ct.fields[idx].isRequired = isRequired }
        if let maxLength  { ct.fields[idx].maxLength  = Self.clampedMaxLength(maxLength) }
        ct.modifyDate = Date()
        markDirty()
    }

    // MARK: - Validation helpers

    /// Caps a caller-supplied `maxLength` to `PropertyDefinition.systemMaxLength` (and floors it
    /// at 1) — defense in depth behind `PropertyEditView`'s own `1...systemMaxLength` validation,
    /// so a category property or asset custom property's bound can never exceed the system max
    /// regardless of how it was set.
    private static func clampedMaxLength(_ n: Int) -> Int {
        min(max(n, 1), PropertyDefinition.systemMaxLength)
    }

    /// Clamps any `.text` payload reachable from `stored` to its definition's `maxLength` —
    /// recursing into composite sub-fields, each clamped against its own field definition.
    /// Applied *before* `validate`, not after: a value that exactly matches a non-extensible
    /// combo-list option must still match once clamped, so clamping has to happen first, not
    /// silently invalidate an otherwise-legal value.
    static func clampedTextValue(_ stored: StoredValue, for definition: PropertyDefinition) -> StoredValue {
        switch stored {
        case .text(let s) where definition.acceptsMaxLength:
            return .text(definition.clamped(s))
        case .composite(let payload):
            guard case .composite(let compositeDef) = definition.type else { return stored }
            let fieldsByName = Dictionary(uniqueKeysWithValues: compositeDef.fields.map { ($0.name, $0) })
            var clampedPayload = payload
            for (key, subValue) in payload {
                guard let fieldDef = fieldsByName[key] else { continue }
                clampedPayload[key] = clampedTextValue(subValue, for: fieldDef)
            }
            return .composite(clampedPayload)
        default:
            return stored
        }
    }

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

    /// Live (not deleted, not purged) top-level assets — same `!isDeleted && !isPurged` filter
    /// as `allAssets`. A record can be `isPurged == true` with `isDeleted == false` after a sync
    /// merge refuses a purge on `isDeleted` alone but a peer's stale strip briefly races it (see
    /// `SnapshotReconciler.joinAsset`'s belt-and-braces `isDeleted` force) — filtering both here
    /// keeps this in step with `allAssets` regardless.
    var rootAssets: [Asset] {
        assets.values.filter { $0.isRoot && !$0.isDeleted && !$0.isPurged }
    }

    func rootAssets(ofCategoryID categoryID: UUID) throws -> [Asset] {
        guard categories[categoryID] != nil else { throw AssetStoreError.categoryNotFound(categoryID) }
        return assets.values.filter { $0.isRoot && $0.category.id == categoryID && !$0.isDeleted && !$0.isPurged }
    }

    // MARK: - Attachments

    @discardableResult
    func addPhoto(imageData: Data, thumbnailData: Data, caption: String = "", toAssetID assetID: UUID) throws -> Photo {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        let photo = Photo(imageData: imageData, thumbnailData: thumbnailData, caption: TextLimits.clamp(caption, to: TextLimits.photoCaption))
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
        photo.caption = TextLimits.clamp(caption, to: TextLimits.photoCaption)
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
    func addEvent(title: String, date: Date, notes: String = "", recurrence: RecurrenceInterval? = nil, due: DueSettings = DueSettings(), toAssetID assetID: UUID) throws -> Event {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        if let limit = eventCreationLimit, asset.liveEvents.count >= limit {
            throw AssetStoreError.freeEventLimitReached(limit: limit)
        }
        let event = Event(title: TextLimits.clamp(title, to: TextLimits.eventTitle), date: date,
                          notes: TextLimits.clamp(notes, to: TextLimits.eventNotes), recurrence: recurrence,
                          dueDate: due.dueDate, messageDaysBefore: due.messageDaysBefore,
                          messageDaysAfter: due.messageDaysAfter,
                          deviceNotificationOn: due.deviceNotificationOn,
                          deviceNotificationDaysBefore: due.deviceNotificationDaysBefore)
        asset.events.append(event)
        asset.modifiedDate = Date()
        logCreation(of: event.id, kind: .event, owningAssetID: assetID)
        notificationScheduler?.requestResync(assets: allAssets)
        markDirty()
        return event
    }

    func updateEvent(id eventID: UUID, onAssetID assetID: UUID, title: String, date: Date, notes: String, recurrence: RecurrenceInterval?, due: DueSettings) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        guard let event = asset.liveEvents.first(where: { $0.id == eventID }) else { throw AssetStoreError.eventNotFound(eventID) }
        let now = Date()
        event.title = TextLimits.clamp(title, to: TextLimits.eventTitle)
        event.date = date
        event.notes = TextLimits.clamp(notes, to: TextLimits.eventNotes)
        event.recurrence = recurrence
        event.dueDate = due.dueDate
        event.messageDaysBefore = due.messageDaysBefore
        event.messageDaysAfter = due.messageDaysAfter
        event.deviceNotificationOn = due.deviceNotificationOn
        event.deviceNotificationDaysBefore = due.deviceNotificationDaysBefore
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

    /// Suffixed title a duplicate of `sourceID` would get if created at `date`, per
    /// `SeriesLogic.duplicateTitle`. Non-recurring sources return the title verbatim — series
    /// membership (and therefore the suffix) only applies to duplicates of recurring records.
    /// Used both to prefill the "Log & Edit"/"Duplicate & Edit" sheet and internally by the
    /// immediate "Log Now"/"Duplicate" action.
    func suggestedDuplicateTitle(forEventID id: UUID, onAssetID assetID: UUID, at date: Date = Date()) -> String {
        guard let asset = assets[assetID], let source = asset.liveEvents.first(where: { $0.id == id }) else { return "" }
        guard source.recurrence != nil else { return source.title }
        let siblingTitles = SeriesLogic.members(of: source, in: asset.liveEvents)
            .filter { $0.id != source.id }
            .map { $0.title }
        return SeriesLogic.duplicateTitle(source: source.title, seriesTitles: siblingTitles, creationDate: date)
    }

    /// Due settings the "Log & Edit"/"Duplicate & Edit" sheet prefills for a duplicate of
    /// `sourceID` dated `date`: the projected next due date (see `SeriesLogic.projectedDueDate`)
    /// plus the source's message/notification window. Companion to `suggestedDuplicateTitle`.
    /// Unlike the immediate "Log Now" path this carries `deviceNotificationOn` verbatim even for
    /// a non-recurring source — the sheet shows both fields before the user commits.
    func suggestedDuplicateDue(forEventID id: UUID, onAssetID assetID: UUID, at date: Date = Date()) -> DueSettings {
        guard let asset = assets[assetID], let source = asset.liveEvents.first(where: { $0.id == id }) else { return DueSettings() }
        return DueSettings(dueDate: SeriesLogic.projectedDueDate(for: source, in: asset.liveEvents, occurrenceDate: date, interval: source.recurrence),
                           messageDaysBefore: source.messageDaysBefore, messageDaysAfter: source.messageDaysAfter,
                           deviceNotificationOn: source.deviceNotificationOn,
                           deviceNotificationDaysBefore: source.deviceNotificationDaysBefore)
    }

    /// See `suggestedDuplicateDue(forEventID:onAssetID:at:)` — same rule, mirrored for Transaction.
    func suggestedDuplicateDue(forTransactionID id: UUID, onAssetID assetID: UUID, at date: Date = Date()) -> DueSettings {
        guard let asset = assets[assetID], let source = asset.liveTransactions.first(where: { $0.id == id }) else { return DueSettings() }
        return DueSettings(dueDate: SeriesLogic.projectedDueDate(for: source, in: asset.liveTransactions, occurrenceDate: date, interval: source.recurrence),
                           messageDaysBefore: source.messageDaysBefore, messageDaysAfter: source.messageDaysAfter,
                           deviceNotificationOn: source.deviceNotificationOn,
                           deviceNotificationDaysBefore: source.deviceNotificationDaysBefore)
    }

    /// Immediate duplicate (context-menu "Log Now"/"Duplicate"): date = now, title = suggested suffix,
    /// everything else copied from the source. If the source is recurring, the copy inherits
    /// recurrence and joins (or starts) the source's series.
    @discardableResult
    func duplicateEvent(id sourceID: UUID, onAssetID assetID: UUID) throws -> Event {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        guard let source = asset.liveEvents.first(where: { $0.id == sourceID }) else { throw AssetStoreError.eventNotFound(sourceID) }
        let now = Date()
        let title = suggestedDuplicateTitle(forEventID: sourceID, onAssetID: assetID, at: now)
        let due = DueSettings(dueDate: SeriesLogic.projectedDueDate(for: source, in: asset.liveEvents, occurrenceDate: now, interval: source.recurrence),
                              messageDaysBefore: source.messageDaysBefore,
                              messageDaysAfter: source.messageDaysAfter,
                              // projectedDueDate only rolls a *recurring* source forward, so a
                              // non-recurring duplicate carries the source's due date verbatim.
                              // Inheriting the toggle here would schedule a second identical
                              // reminder for the same moment — and since no seriesID is
                              // assigned for a non-recurring source (below), isSuppressed can
                              // silence neither copy. The duplicate-and-edit sheet is
                              // deliberately unaffected: it shows both fields before the user
                              // commits, so the normal formula runs on whatever they save.
                              deviceNotificationOn: source.recurrence != nil && source.deviceNotificationOn,
                              deviceNotificationDaysBefore: source.deviceNotificationDaysBefore)
        return try duplicateEventCore(source: source, asset: asset, title: title, date: now, notes: source.notes, recurrence: source.recurrence, due: due)
    }

    /// "Log & Edit"/"Duplicate & Edit" sheet save: field values come from the form verbatim
    /// (the sheet was prefilled with `suggestedDuplicateTitle`/the advanced due date, but the
    /// user may have edited them) — no re-suffixing here. Series assignment still happens at
    /// save time, so cancelling the sheet leaves the source untouched.
    @discardableResult
    func duplicateEvent(id sourceID: UUID, onAssetID assetID: UUID, title: String, date: Date, notes: String, recurrence: RecurrenceInterval?, due: DueSettings) throws -> Event {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        guard let source = asset.liveEvents.first(where: { $0.id == sourceID }) else { throw AssetStoreError.eventNotFound(sourceID) }
        return try duplicateEventCore(source: source, asset: asset, title: title, date: date, notes: notes, recurrence: recurrence, due: due)
    }

    private func duplicateEventCore(source: Event, asset: Asset, title: String, date: Date, notes: String, recurrence: RecurrenceInterval?, due: DueSettings) throws -> Event {
        if let limit = eventCreationLimit, asset.liveEvents.count >= limit {
            throw AssetStoreError.freeEventLimitReached(limit: limit)
        }
        let title = TextLimits.clamp(title, to: TextLimits.eventTitle)
        let notes = TextLimits.clamp(notes, to: TextLimits.eventNotes)
        let now = Date()
        var seriesID: UUID? = nil
        if source.recurrence != nil {
            if source.seriesID == nil {
                source.seriesID = UUID()
                source.touch(now)
            }
            seriesID = source.seriesID
        }
        // Guarantees the duplicate outranks `source` (and any earlier duplicates) as the
        // series' newest member even when created within the same wall-clock second — see
        // SeriesLogic.createdAtForNewSeriesMember's doc comment.
        let createdAt = SeriesLogic.createdAtForNewSeriesMember(after: source, in: asset.liveEvents, now: now)
        let event = Event(title: title, date: date, notes: notes, recurrence: recurrence,
                          dueDate: due.dueDate, seriesID: seriesID, createdAt: createdAt,
                          messageDaysBefore: due.messageDaysBefore, messageDaysAfter: due.messageDaysAfter,
                          deviceNotificationOn: due.deviceNotificationOn,
                          deviceNotificationDaysBefore: due.deviceNotificationDaysBefore)
        asset.events.append(event)
        asset.modifiedDate = now
        logCreation(of: event.id, kind: .event, owningAssetID: asset.id)
        notificationScheduler?.requestResync(assets: allAssets)
        markDirty()
        return event
    }

    @discardableResult
    func addTransaction(details: String, amount: Decimal, date: Date, kind: TransactionKind, payeeContactID: String? = nil, notes: String = "", recurrence: RecurrenceInterval? = nil, due: DueSettings = DueSettings(), toAssetID assetID: UUID) throws -> Transaction {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        if let limit = transactionCreationLimit, asset.liveTransactions.count >= limit {
            throw AssetStoreError.freeTransactionLimitReached(limit: limit)
        }
        let txn = Transaction(details: TextLimits.clamp(details, to: TextLimits.transactionDetails), amount: amount, date: date, kind: kind, payeeContactID: payeeContactID, notes: TextLimits.clamp(notes, to: TextLimits.transactionNotes), recurrence: recurrence,
                              dueDate: due.dueDate, messageDaysBefore: due.messageDaysBefore,
                              messageDaysAfter: due.messageDaysAfter,
                              deviceNotificationOn: due.deviceNotificationOn,
                              deviceNotificationDaysBefore: due.deviceNotificationDaysBefore)
        asset.transactions.append(txn)
        asset.modifiedDate = Date()
        logCreation(of: txn.id, kind: .transaction, owningAssetID: assetID)
        notificationScheduler?.requestResync(assets: allAssets)
        markDirty()
        return txn
    }

    func updateTransaction(id txnID: UUID, onAssetID assetID: UUID, details: String, amount: Decimal, date: Date, kind: TransactionKind, payeeContactID: String?, notes: String, recurrence: RecurrenceInterval?, due: DueSettings) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        guard let txn = asset.liveTransactions.first(where: { $0.id == txnID }) else { throw AssetStoreError.transactionNotFound(txnID) }
        let now = Date()
        txn.details = TextLimits.clamp(details, to: TextLimits.transactionDetails)
        txn.amount = abs(amount)
        txn.date = date
        txn.kind = kind
        txn.payeeContactID = payeeContactID
        txn.notes = TextLimits.clamp(notes, to: TextLimits.transactionNotes)
        txn.recurrence = recurrence
        txn.dueDate = due.dueDate
        txn.messageDaysBefore = due.messageDaysBefore
        txn.messageDaysAfter = due.messageDaysAfter
        txn.deviceNotificationOn = due.deviceNotificationOn
        txn.deviceNotificationDaysBefore = due.deviceNotificationDaysBefore
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

    /// See `suggestedDuplicateTitle(forEventID:onAssetID:at:)` — same rule, on `details`.
    func suggestedDuplicateTitle(forTransactionID id: UUID, onAssetID assetID: UUID, at date: Date = Date()) -> String {
        guard let asset = assets[assetID], let source = asset.liveTransactions.first(where: { $0.id == id }) else { return "" }
        guard source.recurrence != nil else { return source.details }
        let siblingTitles = SeriesLogic.members(of: source, in: asset.liveTransactions)
            .filter { $0.id != source.id }
            .map { $0.details }
        return SeriesLogic.duplicateTitle(source: source.details, seriesTitles: siblingTitles, creationDate: date)
    }

    /// See `duplicateEvent(id:onAssetID:)` — same rule, mirrored for Transaction.
    @discardableResult
    func duplicateTransaction(id sourceID: UUID, onAssetID assetID: UUID) throws -> Transaction {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        guard let source = asset.liveTransactions.first(where: { $0.id == sourceID }) else { throw AssetStoreError.transactionNotFound(sourceID) }
        let now = Date()
        let details = suggestedDuplicateTitle(forTransactionID: sourceID, onAssetID: assetID, at: now)
        let due = DueSettings(dueDate: SeriesLogic.projectedDueDate(for: source, in: asset.liveTransactions, occurrenceDate: now, interval: source.recurrence),
                              messageDaysBefore: source.messageDaysBefore,
                              messageDaysAfter: source.messageDaysAfter,
                              // See duplicateEvent(id:onAssetID:) — same non-recurring
                              // double-notification guard, mirrored for Transaction.
                              deviceNotificationOn: source.recurrence != nil && source.deviceNotificationOn,
                              deviceNotificationDaysBefore: source.deviceNotificationDaysBefore)
        return try duplicateTransactionCore(source: source, asset: asset, details: details, amount: source.amount, date: now, kind: source.kind, payeeContactID: source.payeeContactID, notes: source.notes, recurrence: source.recurrence, due: due)
    }

    /// See `duplicateEvent(id:onAssetID:title:date:notes:recurrence:due:)` — same rule, mirrored for Transaction.
    @discardableResult
    func duplicateTransaction(id sourceID: UUID, onAssetID assetID: UUID, details: String, amount: Decimal, date: Date, kind: TransactionKind, payeeContactID: String?, notes: String, recurrence: RecurrenceInterval?, due: DueSettings) throws -> Transaction {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        guard let source = asset.liveTransactions.first(where: { $0.id == sourceID }) else { throw AssetStoreError.transactionNotFound(sourceID) }
        return try duplicateTransactionCore(source: source, asset: asset, details: details, amount: amount, date: date, kind: kind, payeeContactID: payeeContactID, notes: notes, recurrence: recurrence, due: due)
    }

    private func duplicateTransactionCore(source: Transaction, asset: Asset, details: String, amount: Decimal, date: Date, kind: TransactionKind, payeeContactID: String?, notes: String, recurrence: RecurrenceInterval?, due: DueSettings) throws -> Transaction {
        if let limit = transactionCreationLimit, asset.liveTransactions.count >= limit {
            throw AssetStoreError.freeTransactionLimitReached(limit: limit)
        }
        let details = TextLimits.clamp(details, to: TextLimits.transactionDetails)
        let notes = TextLimits.clamp(notes, to: TextLimits.transactionNotes)
        let now = Date()
        var seriesID: UUID? = nil
        if source.recurrence != nil {
            if source.seriesID == nil {
                source.seriesID = UUID()
                source.touch(now)
            }
            seriesID = source.seriesID
        }
        // See SeriesLogic.createdAtForNewSeriesMember's doc comment.
        let createdAt = SeriesLogic.createdAtForNewSeriesMember(after: source, in: asset.liveTransactions, now: now)
        let txn = Transaction(details: details, amount: amount, date: date, kind: kind, payeeContactID: payeeContactID, notes: notes, recurrence: recurrence,
                              dueDate: due.dueDate, seriesID: seriesID, createdAt: createdAt,
                              messageDaysBefore: due.messageDaysBefore, messageDaysAfter: due.messageDaysAfter,
                              deviceNotificationOn: due.deviceNotificationOn,
                              deviceNotificationDaysBefore: due.deviceNotificationDaysBefore)
        asset.transactions.append(txn)
        asset.modifiedDate = now
        logCreation(of: txn.id, kind: .transaction, owningAssetID: asset.id)
        notificationScheduler?.requestResync(assets: allAssets)
        markDirty()
        return txn
    }


    // MARK: - Private helpers

    /// Computes the `sortOrder` writes needed to realize an `.onMove`-style reorder of `live`
    /// (a live `[AssetProperty]` — a category's templates, or one asset's base/custom
    /// properties). `fromOffsets`/`toOffset` are `.onMove`'s own arguments, and they index the
    /// row order the user was looking at — so `live` MUST be sorted by `SortOrdering.precedes`,
    /// the same comparator every display site uses. Passing the raw array is wrong the moment
    /// array order and `sortOrder` order diverge, which the first reorder guarantees (a move
    /// rewrites `sortOrder` in place and never repositions the array).
    ///
    /// Returns `(id, newSortOrder)` pairs for every row that must change — normally just the
    /// moved block (`SortOrdering.values`), but the whole list when that can't find room (see
    /// `SortOrdering`'s doc comment on why, including how this self-heals today's all-zero-
    /// `sortOrder` custom properties on their first move). Callers apply the writes and stamp
    /// `touch()`/`asset.modifiedDate` themselves, since that differs between a category's
    /// templates and an asset's properties.
    private static func moveWrites(fromOffsets: IndexSet, toOffset: Int, live: [AssetProperty]) -> [(id: UUID, sortOrder: Double)] {
        let movedIDs = Set(fromOffsets.map { live[$0].id })
        let reordered = SortOrdering.moved(live, fromOffsets: fromOffsets, toOffset: toOffset)
        guard let firstMovedIndex = reordered.firstIndex(where: { movedIDs.contains($0.id) }) else { return [] }
        let movedCount = movedIDs.count
        let movedSlice = Array(reordered[firstMovedIndex..<(firstMovedIndex + movedCount)])
        let prev = firstMovedIndex > 0 ? reordered[firstMovedIndex - 1].sortOrder : nil
        let afterIndex = firstMovedIndex + movedCount
        let next = afterIndex < reordered.count ? reordered[afterIndex].sortOrder : nil
        if let values = SortOrdering.values(count: movedCount, after: prev, before: next) {
            return Array(zip(movedSlice.map(\.id), values))
        }
        let values = SortOrdering.normalized(count: reordered.count)
        return Array(zip(reordered.map(\.id), values))
    }

    private func logCreation(of recordID: UUID, kind: LoggedRecordKind, owningAssetID: UUID? = nil) {
        activityLog.append(ActivityLogEntry(recordID: recordID, kind: kind, owningAssetID: owningAssetID))
    }

    /// Registers a text value on an extensible combo list if it's new. Not `private`: also
    /// called from `AssetStore+TemplatePropagation.swift` when a propagated definition change
    /// preserves an asset's existing value against a combo list it wasn't yet registered on.
    func handleComboListAutoAdd(stored: StoredValue, type: PropertyType) {
        guard case .comboList(let list) = type,
              case .text(let value) = stored,
              list.isUserExtensible else { return }
        let trimmed = TextLimits.clamp(value.trimmingCharacters(in: .whitespaces), to: TextLimits.comboListOption)
        guard !trimmed.isEmpty, !list.allOptions.contains(trimmed) else { return }
        list.userOptions.append(trimmed)
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
        guard !savesSuspended, !storeRequiresNewerApp else { return }
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
    ///
    /// `instant` is the purge decision's own timestamp, recorded in `asset.purgedAt` — not to be
    /// confused with `deletedAt` (when the user decided to *delete*). Callers pick what it means:
    /// `hardDeleteAsset`'s default (`Date()`, "now") is explicit intent that should be able to
    /// outrank content edited since the original delete; `purgeHardDeleted`'s automatic retention
    /// sweep passes `deletedAt` instead, so the stamp stays content-derived and identical however
    /// many devices independently aged the same tombstone out; `applyInPlace` passes the merged
    /// snapshot's own `dto.purgedAt` when it needs to actually apply an already-decided strip
    /// locally. See `SnapshotReconciler.joinAsset` for what actually reads this.
    ///
    /// Ratchets `purgedAt` forward (keeps it if `instant` isn't later) rather than only setting
    /// it once: `existing.purgedAt` can already be non-nil here even though `isPurged` was still
    /// `false` a moment ago — `applyInPlace`'s refused-purge branch stamps `purgedAt` from a
    /// merge's `dto.purgedAt` without setting `isPurged`, precisely so a *later*, more
    /// authoritative purge decision (a bigger `max` fold, or an explicit "delete now") can still
    /// win. A plain "set only if nil" would freeze the stamp at that first, possibly-refused
    /// attempt and make every later purge decision for this record permanently unable to record
    /// its own, more current, timestamp.
    func purgeInPlace(_ asset: Asset, at instant: Date = Date()) {
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
        if asset.purgedAt == nil || instant > asset.purgedAt! { asset.purgedAt = instant }
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
    /// See `purgeInPlace(_:at:)`'s doc comment for what `instant` means, who passes what, and
    /// why the stamp ratchets forward instead of being set only once.
    func purgeCategoryInPlace(_ category: AssetCategory, at instant: Date = Date()) {
        guard !category.isPurged else { return }
        category.name = ""
        category.iconName = ""
        category.propertyTemplates = []
        category.isPurged = true
        if category.purgedAt == nil || instant > category.purgedAt! { category.purgedAt = instant }
    }

    /// Purges soft-deleted assets and categories whose deletedAt is older than `seconds` to
    /// minimal tombstones (see `purgeInPlace`/`purgeCategoryInPlace`) — never removes the
    /// record — then the same age-based reaping as before for tombstoned
    /// events/transactions/photos/base/custom properties inside assets that are not (yet) purged,
    /// and for aged-out category property-template tombstones on categories that are not (yet)
    /// purged. Categories are evaluated after assets — a category kept alive only by a
    /// now-purged asset is eligible for purging in the same sweep, since a purged asset no
    /// longer counts as a reference. Categories still referenced by any non-purged asset are
    /// retained regardless of age to avoid dangling categoryIDs. Old activity-log entries whose
    /// owning asset is gone or purged are dropped once their own timestamp ages past cutoff —
    /// mirrors `SnapshotReconciler.reap`, so a local sweep and a sync merge converge.
    ///
    /// Both selection loops also skip a record flagged `isProtectedFromAutoPurge` — content
    /// edited after `deletedAt` — mirroring `SnapshotReconciler`'s join-time gate exactly, so
    /// this automatic sweep never destroys content a sync merge would have protected. Left
    /// alone, that record simply stays a live tombstone in Trash — restorable, or removable via
    /// an explicit "delete now" — rather than being aged out from under the user.
    ///
    /// Soft-deleted combo lists are deliberately never touched here — there is no purge/strip
    /// path for them at all. A stripped combo list (name/options blanked, the way
    /// `purgeCategoryInPlace` blanks a category) would leave any property still typed on it with
    /// an empty option set instead of the values it actually holds; a tombstoned-but-intact list
    /// costs only a handful of strings and keeps every reference resolvable indefinitely. See
    /// `allComboListDefinitions`'s doc comment.
    func purgeHardDeleted(olderThan seconds: TimeInterval = 90 * 86_400) {
        let cutoff = Date().addingTimeInterval(-seconds)
        for asset in assets.values
        where asset.isDeleted && (asset.deletedAt ?? .distantFuture) < cutoff && !asset.isPurged
            && !asset.isProtectedFromAutoPurge {
            // deletedAt, not Date(): this is automatic housekeeping, not an explicit purge
            // decision, so the stamp must stay content-derived — see purgeInPlace(_:at:).
            purgeInPlace(asset, at: asset.deletedAt ?? Date())
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
            asset.baseProperties.removeAll { Self.isExpiredTombstone($0.isDeleted, $0.deletedAt, before: cutoff) }
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
            && !referencedCategoryIDs.contains(category.id)
            && !category.isProtectedFromAutoPurge {
            purgeCategoryInPlace(category, at: category.deletedAt ?? Date())
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
