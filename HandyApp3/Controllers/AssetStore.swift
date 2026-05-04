//
//  AssetStore.swift
//  HandyApp3
//
//  Created by Hao Deng on 5/2/26.
//

import Foundation

// MARK: - Errors

enum AssetStoreError: Error, Equatable {
    case categoryNotFound(UUID)
    case assetNotFound(UUID)
    case compositeTypeNotFound(UUID)
    case definitionNotFound(UUID)
    /// The supplied StoredValue variant does not match the PropertyDefinition's type.
    case typeMismatch(expected: String, got: String)
    /// A composite payload is missing required fields or contains unknown field names.
    case compositeFieldMismatch(details: String)
    /// The composite type is category-scoped and the asset's category is not the allowed one.
    case compositeTypeScopeViolation(typeID: UUID, allowedCategoryID: UUID, assetCategoryID: UUID)
    /// Attaching a child would create a cycle in the asset hierarchy.
    case hierarchyCycle(childID: UUID, ancestorID: UUID)
    /// Attempted to remove or edit a system-defined field on a composite type.
    case cannotModifySystemField(UUID)
    /// Attempted to add, edit, or remove a user field on a non-extensible composite type.
    case notUserExtensible(UUID)
}

// MARK: - AssetStore

/// Single in-memory store for the entire domain.
/// All mutations happen through this object; there is no persistence at this layer.
final class AssetStore {

    // MARK: - Storage

    private(set) var categories: [UUID: AssetCategory] = [:]
    private(set) var assets: [UUID: Asset] = [:]
    private(set) var compositeTypes: [UUID: CompositeTypeDefinition] = [:]

    // MARK: - Derived collections

    var allCategories: [AssetCategory] { Array(categories.values) }
    var allAssets: [Asset] { Array(assets.values) }
    var allCompositeTypes: [CompositeTypeDefinition] { Array(compositeTypes.values) }

    // MARK: - Category CRUD

    @discardableResult
    func createCategory(name: String, propertyDefinitions: [PropertyDefinition] = []) -> AssetCategory {
        let cat = AssetCategory(name: name, propertyDefinitions: propertyDefinitions)
        categories[cat.id] = cat
        return cat
    }

    func updateCategory(id: UUID, name: String) throws {
        guard let cat = categories[id] else { throw AssetStoreError.categoryNotFound(id) }
        cat.name = name
    }

    /// Removes the category and all assets that belong to it.
    func deleteCategory(id: UUID) throws {
        guard categories[id] != nil else { throw AssetStoreError.categoryNotFound(id) }
        // Remove assets belonging to this category
        let orphanedAssets = assets.values.filter { $0.category.id == id }
        orphanedAssets.forEach { assets.removeValue(forKey: $0.id) }
        categories.removeValue(forKey: id)
    }

    // MARK: - PropertyDefinition management on categories

    @discardableResult
    func addPropertyDefinition(
        _ definition: PropertyDefinition,
        toCategoryID categoryID: UUID
    ) throws -> PropertyDefinition {
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        cat.propertyDefinitions.append(definition)
        return definition
    }

    func updatePropertyDefinition(
        id: UUID,
        inCategoryID categoryID: UUID,
        name: String? = nil,
        type: PropertyType? = nil
    ) throws {
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        guard let idx = cat.propertyDefinitions.firstIndex(where: { $0.id == id }) else {
            throw AssetStoreError.definitionNotFound(id)
        }
        if let name { cat.propertyDefinitions[idx].name = name }
        if let type { cat.propertyDefinitions[idx].type = type }
    }

    func removePropertyDefinition(id: UUID, fromCategoryID categoryID: UUID) throws {
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        guard cat.propertyDefinitions.contains(where: { $0.id == id }) else {
            throw AssetStoreError.definitionNotFound(id)
        }
        cat.propertyDefinitions.removeAll { $0.id == id }
        // Remove orphaned values from assets in this category
        assets.values
            .filter { $0.category.id == categoryID }
            .forEach { $0.propertyValues.removeAll { $0.definitionID == id } }
    }

    // MARK: - Asset CRUD

    @discardableResult
    func createAsset(name: String, categoryID: UUID) throws -> Asset {
        guard let cat = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }
        let asset = Asset(name: name, category: cat)
        assets[asset.id] = asset
        return asset
    }

    func updateAsset(id: UUID, name: String) throws {
        guard let asset = assets[id] else { throw AssetStoreError.assetNotFound(id) }
        asset.name = name
    }

    func deleteAsset(id: UUID) throws {
        guard let asset = assets[id] else { throw AssetStoreError.assetNotFound(id) }
        // Capture grandparent before detaching (detach nils asset.parent)
        let grandparent = asset.parent
        asset.parent?._removeChild(asset)
        // Promote children to grandparent, or make them roots if no grandparent exists
        for child in Array(asset.children) {
            asset._removeChild(child)
            grandparent?._addChild(child)
        }
        assets.removeValue(forKey: id)
    }

    func assets(inCategoryID categoryID: UUID) throws -> [Asset] {
        guard categories[categoryID] != nil else { throw AssetStoreError.categoryNotFound(categoryID) }
        return assets.values.filter { $0.category.id == categoryID }
    }

    // MARK: - PropertyValue management on assets

    /// Sets (insert or replace) a property value on an asset.
    /// Validates that the StoredValue variant matches the PropertyDefinition's type.
    @discardableResult
    func setPropertyValue(
        _ stored: StoredValue,
        forDefinitionID definitionID: UUID,
        onAssetID assetID: UUID
    ) throws -> PropertyValue {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        // Locate the definition in the asset's category
        guard let definition = asset.category.propertyDefinitions.first(where: { $0.id == definitionID }) else {
            throw AssetStoreError.definitionNotFound(definitionID)
        }
        // Validate the value against the definition's type
        try validate(stored: stored, against: definition.type, definitionName: definition.name)

        if let idx = asset.propertyValues.firstIndex(where: { $0.definitionID == definitionID }) {
            asset.propertyValues[idx].value = stored
            return asset.propertyValues[idx]
        } else {
            let pv = PropertyValue(definitionID: definitionID, value: stored)
            asset.propertyValues.append(pv)
            return pv
        }
    }

    func removePropertyValue(forDefinitionID definitionID: UUID, fromAssetID assetID: UUID) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        asset.propertyValues.removeAll { $0.definitionID == definitionID }
    }



    // MARK: - CompositeTypeDefinition CRUD

    /// Creates a composite type with purely user-defined fields (no system fields).
    /// To create a type with system fields, pass them explicitly via `systemFields:`.
    @discardableResult
    func createCompositeType(
        name: String,
        systemFields: [PropertyDefinition] = [],
        userFields: [PropertyDefinition] = [],
        isUserExtensible: Bool = true,
        scope: CompositeTypeScope = .global
    ) -> CompositeTypeDefinition {
        let ct = CompositeTypeDefinition(name: name, systemFields: systemFields, userFields: userFields, isUserExtensible: isUserExtensible, scope: scope)
        compositeTypes[ct.id] = ct
        return ct
    }

    /// Updates the name and/or scope of a composite type.
    /// Fields are managed separately via `addUserField`, `removeUserField`, `updateUserField`.
    func updateCompositeType(
        id: UUID,
        name: String? = nil,
        scope: CompositeTypeScope? = nil
    ) throws {
        guard let ct = compositeTypes[id] else { throw AssetStoreError.compositeTypeNotFound(id) }
        if let name  { ct.name  = name  }
        if let scope { ct.scope = scope }
    }

    /// Returns all composite types available for a given category (global + category-scoped to that category).
    func compositeTypes(availableForCategoryID categoryID: UUID) throws -> [CompositeTypeDefinition] {
        guard categories[categoryID] != nil else { throw AssetStoreError.categoryNotFound(categoryID) }
        return compositeTypes.values.filter { ct in
            switch ct.scope {
            case .global: return true
            case .category(let cat): return cat.id == categoryID
            }
        }
    }

    func deleteCompositeType(id: UUID) throws {
        guard compositeTypes[id] != nil else { throw AssetStoreError.compositeTypeNotFound(id) }
        compositeTypes.removeValue(forKey: id)
    }

    // MARK: - User field management on composite types

    /// Appends a user-defined field to an existing composite type.
    @discardableResult
    func addUserField(_ field: PropertyDefinition, toCompositeTypeID typeID: UUID) throws -> PropertyDefinition {
        guard let ct = compositeTypes[typeID] else { throw AssetStoreError.compositeTypeNotFound(typeID) }
        guard ct.isUserExtensible else { throw AssetStoreError.notUserExtensible(typeID) }
        ct.userFields.append(field)
        return field
    }

    /// Removes a user-defined field. Throws `.cannotModifySystemField` if the field is system-defined.
    func removeUserField(id fieldID: UUID, fromCompositeTypeID typeID: UUID) throws {
        guard let ct = compositeTypes[typeID] else { throw AssetStoreError.compositeTypeNotFound(typeID) }
        guard ct.isUserExtensible else { throw AssetStoreError.notUserExtensible(typeID) }
        if ct.systemFields.contains(where: { $0.id == fieldID }) {
            throw AssetStoreError.cannotModifySystemField(fieldID)
        }
        guard ct.userFields.contains(where: { $0.id == fieldID }) else {
            throw AssetStoreError.definitionNotFound(fieldID)
        }
        ct.userFields.removeAll { $0.id == fieldID }
    }

    /// Updates a user-defined field's name, type, or isRequired flag.
    /// Throws `.cannotModifySystemField` if the field is system-defined.
    func updateUserField(
        id fieldID: UUID,
        inCompositeTypeID typeID: UUID,
        name: String? = nil,
        type: PropertyType? = nil,
        isRequired: Bool? = nil
    ) throws {
        guard let ct = compositeTypes[typeID] else { throw AssetStoreError.compositeTypeNotFound(typeID) }
        guard ct.isUserExtensible else { throw AssetStoreError.notUserExtensible(typeID) }
        if ct.systemFields.contains(where: { $0.id == fieldID }) {
            throw AssetStoreError.cannotModifySystemField(fieldID)
        }
        guard let idx = ct.userFields.firstIndex(where: { $0.id == fieldID }) else {
            throw AssetStoreError.definitionNotFound(fieldID)
        }
        if let name       { ct.userFields[idx].name       = name       }
        if let type       { ct.userFields[idx].type       = type       }
        if let isRequired { ct.userFields[idx].isRequired = isRequired }
    }

    // MARK: - Validation helpers

    /// Recursively validates a StoredValue against a PropertyType.
    func validate(stored: StoredValue, against type: PropertyType, definitionName: String) throws {
        switch type {
        case .basic(let basic):
            guard let actual = stored.basicType, actual == basic else {
                let expected = basic.rawValue
                let got: String
                if let b = stored.basicType { got = b.rawValue } else { got = "composite" }
                throw AssetStoreError.typeMismatch(expected: expected, got: got)
            }

        case .composite(let definition):
            guard case .composite(let payload) = stored else {
                let got = stored.basicType?.rawValue ?? "composite"
                throw AssetStoreError.typeMismatch(expected: "composite(\(definition.name))", got: got)
            }
            let fieldsByName = Dictionary(uniqueKeysWithValues: definition.fields.map { ($0.name, $0) })

            // Enforce required fields are present in the payload
            for field in definition.fields where field.isRequired {
                if payload[field.name] == nil {
                    throw AssetStoreError.compositeFieldMismatch(
                        details: "Required field '\(field.name)' is missing from composite type '\(definition.name)'"
                    )
                }
            }

            // Validate each supplied field value (optional fields are fine to omit; unknown keys are rejected)
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

    /// Makes `childID` a direct child of `parentID`.
    /// Throws `.hierarchyCycle` if `parentID` is already a descendant of `childID`,
    /// or if `childID == parentID`.
    func addChild(assetID childID: UUID, toParentID parentID: UUID) throws {
        guard let child  = assets[childID]  else { throw AssetStoreError.assetNotFound(childID) }
        guard let newParent = assets[parentID] else { throw AssetStoreError.assetNotFound(parentID) }
        guard childID != parentID else {
            throw AssetStoreError.hierarchyCycle(childID: childID, ancestorID: parentID)
        }
        if child.descendants.contains(where: { $0.id == parentID }) {
            throw AssetStoreError.hierarchyCycle(childID: childID, ancestorID: parentID)
        }
        child.parent?._removeChild(child)
        newParent._addChild(child)
    }

    /// Detaches `assetID` from its current parent, making it a root asset.
    /// No-op if the asset is already a root.
    func removeFromParent(assetID: UUID) throws {
        guard let asset = assets[assetID] else { throw AssetStoreError.assetNotFound(assetID) }
        asset.parent?._removeChild(asset)
    }

    /// Moves `assetID` to a new parent, replacing any existing parent relationship.
    func moveAsset(assetID: UUID, toParentID newParentID: UUID) throws {
        try removeFromParent(assetID: assetID)
        try addChild(assetID: assetID, toParentID: newParentID)
    }

    /// All root assets (no parent) across the entire store.
    var rootAssets: [Asset] {
        assets.values.filter(\.isRoot)
    }

    /// All root assets belonging to a specific category.
    func rootAssets(inCategoryID categoryID: UUID) throws -> [Asset] {
        guard categories[categoryID] != nil else { throw AssetStoreError.categoryNotFound(categoryID) }
        return assets.values.filter { $0.isRoot && $0.category.id == categoryID }
    }
}
