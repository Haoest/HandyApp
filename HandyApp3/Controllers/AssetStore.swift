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

    // MARK: - Derived collections

    var allAssets: [Asset] { assets.values.filter { !$0.isDeleted } }
    var allCategories: [AssetCategory] { Array(categories.values) }
    var allCompositeTypes: [CompositeTypeDefinition] { Array(compositeTypes.values) }
    var allComboListDefinitions: [ComboListDefinition] { Array(comboListDefinitions.values) }

    // MARK: - AssetCategory CRUD

    @discardableResult
    func createCategory(name: String, iconName: String = "square.grid.2x2", propertyTemplates: [AssetProperty] = []) -> AssetCategory {
        let cat = AssetCategory(name: name, iconName: iconName, propertyTemplates: propertyTemplates)
        categories[cat.id] = cat
        return cat
    }

    func updateCategory(id: UUID, name: String) throws {
        guard let cat = categories[id] else { throw AssetStoreError.categoryNotFound(id) }
        cat.name = name
    }

    func updateCategoryIcon(id: UUID, iconName: String) throws {
        guard let cat = categories[id] else { throw AssetStoreError.categoryNotFound(id) }
        cat.iconName = iconName
    }

    func deleteCategory(id: UUID) throws {
        guard categories[id] != nil else { throw AssetStoreError.categoryNotFound(id) }
        categories.removeValue(forKey: id)
    }

    /// Appends a new property template to an existing category.
    @discardableResult
    func addTemplateProperty(_ property: AssetProperty, toCategoryID categoryID: UUID) throws -> AssetProperty {
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        cat.propertyTemplates.append(property)
        return property
    }

    func setTemplatePropertyValue(_ stored: StoredValue, forPropertyID propID: UUID, inCategoryID categoryID: UUID) throws {
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        guard let prop = cat.propertyTemplates.first(where: { $0.id == propID }) else {
            throw AssetStoreError.propertyNotFound(propID)
        }
        try validate(stored: stored, against: prop.definition.type, definitionName: prop.definition.name)
        prop.value = stored
    }

    func removeTemplatePropertyValue(forPropertyID propID: UUID, inCategoryID categoryID: UUID) throws {
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        guard let prop = cat.propertyTemplates.first(where: { $0.id == propID }) else {
            throw AssetStoreError.propertyNotFound(propID)
        }
        prop.value = nil
    }

    /// Removes a template property from a category. Does not affect existing assets.
    func removeTemplateProperty(id propID: UUID, fromCategoryID categoryID: UUID) throws {
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        guard cat.propertyTemplates.contains(where: { $0.id == propID }) else {
            throw AssetStoreError.propertyNotFound(propID)
        }
        cat.propertyTemplates.removeAll { $0.id == propID }
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
    }

    // MARK: - Asset CRUD

    /// Creates an Asset, deep-copying the category's property templates into baseProperties.
    @discardableResult
    func createAsset(name: String, categoryID: UUID) throws -> Asset {
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        let baseProperties = cat.propertyTemplates.enumerated().map { index, template in
            AssetProperty(definition: template.definition, value: template.value,
                          sortOrder: Double(index) * AssetProperty.sortOrderIncrement)
        }
        let asset = Asset(name: name, category: cat, baseProperties: baseProperties)
        assets[asset.id] = asset
        return asset
    }

    func updateAsset(id: UUID, name: String) throws {
        guard let asset = assets[id] else { throw AssetStoreError.assetNotFound(id) }
        asset.name = name
        asset.modifiedDate = Date()
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
    }

    /// Marks the asset as deleted without removing it from the store.
    /// Detaches it from its parent and sets all direct children to top-level.
    func softDeleteAsset(id: UUID) throws {
        guard let asset = assets[id] else { throw AssetStoreError.assetNotFound(id) }
        asset.parent?._removeChild(asset)
        for child in Array(asset.children) {
            asset._removeChild(child)
        }
        asset.isDeleted = true
        asset.modifiedDate = Date()
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
            return prop
        }
        if let prop = asset.customProperties.first(where: { $0.definition.id == definitionID }) {
            try validate(stored: stored, against: prop.definition.type, definitionName: prop.definition.name)
            handleComboListAutoAdd(stored: stored, type: prop.definition.type)
            prop.value = stored
            asset.modifiedDate = Date()
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
            return
        }
        if let prop = asset.customProperties.first(where: { $0.definition.id == definitionID }) {
            prop.value = nil
            asset.modifiedDate = Date()
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
    }

    /// Removes a custom property and its value from an asset.
    func removeCustomProperty(id propID: UUID, fromAssetID assetID: UUID) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        guard asset.customProperties.contains(where: { $0.id == propID }) else {
            throw AssetStoreError.propertyNotFound(propID)
        }
        asset.customProperties.removeAll { $0.id == propID }
        asset.modifiedDate = Date()
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
        return cl
    }

    func updateComboList(id: UUID, name: String) throws {
        guard let cl = comboListDefinitions[id] else { throw AssetStoreError.comboListNotFound(id) }
        cl.name = name
    }

    func deleteComboList(id: UUID) throws {
        guard comboListDefinitions[id] != nil else { throw AssetStoreError.comboListNotFound(id) }
        comboListDefinitions.removeValue(forKey: id)
    }

    func addUserOption(_ option: String, toComboListID id: UUID) throws {
        guard let cl = comboListDefinitions[id] else { throw AssetStoreError.comboListNotFound(id) }
        guard cl.isUserExtensible else { throw AssetStoreError.comboListNotExtensible(id) }
        guard !cl.allOptions.contains(option) else { return }
        cl.userOptions.append(option)
    }

    func removeUserOption(_ option: String, fromComboListID id: UUID) throws {
        guard let cl = comboListDefinitions[id] else { throw AssetStoreError.comboListNotFound(id) }
        guard cl.isUserExtensible else { throw AssetStoreError.comboListNotExtensible(id) }
        guard !cl.systemOptions.contains(option) else {
            throw AssetStoreError.cannotModifySystemOption(listID: id, option: option)
        }
        cl.userOptions.removeAll { $0 == option }
    }

    // MARK: - CompositeTypeDefinition CRUD

    @discardableResult
    func createCompositeType(
        name: String,
        fields: [PropertyDefinition] = []
    ) -> CompositeTypeDefinition {
        let ct = CompositeTypeDefinition(name: name, fields: fields)
        compositeTypes[ct.id] = ct
        return ct
    }

    func updateCompositeType(id: UUID, name: String) throws {
        guard let ct = compositeTypes[id] else { throw AssetStoreError.compositeTypeNotFound(id) }
        ct.name = name
    }

    func deleteCompositeType(id: UUID) throws {
        guard compositeTypes[id] != nil else { throw AssetStoreError.compositeTypeNotFound(id) }
        compositeTypes.removeValue(forKey: id)
    }

    @discardableResult
    func addField(_ field: PropertyDefinition, toCompositeTypeID typeID: UUID) throws -> PropertyDefinition {
        guard let ct = compositeTypes[typeID] else { throw AssetStoreError.compositeTypeNotFound(typeID) }
        ct.fields.append(field)
        return field
    }

    func removeField(id fieldID: UUID, fromCompositeTypeID typeID: UUID) throws {
        guard let ct = compositeTypes[typeID] else { throw AssetStoreError.compositeTypeNotFound(typeID) }
        guard ct.fields.contains(where: { $0.id == fieldID }) else {
            throw AssetStoreError.definitionNotFound(fieldID)
        }
        ct.fields.removeAll { $0.id == fieldID }
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
    }

    func removeFromParent(assetID: UUID) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        asset.parent?._removeChild(asset)
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

    // MARK: - Private helpers

    private func handleComboListAutoAdd(stored: StoredValue, type: PropertyType) {
        guard case .comboList(let list) = type,
              case .text(let value) = stored,
              list.isUserExtensible,
              !list.allOptions.contains(value) else { return }
        list.userOptions.append(value)
    }
}
