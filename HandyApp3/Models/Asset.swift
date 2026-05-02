//
//  Asset.swift
//  HandyApp3
//
//  Created by Hao Deng on 5/2/26.
//

import Foundation

/// A physical asset owned by the user (e.g. "My House", "2022 Toyota Camry").
final class Asset: Identifiable, Equatable {
    let id: UUID
    var name: String
    var category: AssetCategory
    /// Values recorded against this asset, one entry per PropertyDefinition (sparse — not all definitions
    /// need a corresponding value).
    var propertyValues: [PropertyValue]

    init(
        id: UUID = UUID(),
        name: String,
        category: AssetCategory,
        propertyValues: [PropertyValue] = []
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.propertyValues = propertyValues
    }

    // MARK: Convenience

    /// Returns the PropertyValue for a given definition id, if one exists.
    func value(for definitionID: UUID) -> PropertyValue? {
        propertyValues.first { $0.definitionID == definitionID }
    }

    static func == (lhs: Asset, rhs: Asset) -> Bool {
        lhs.id == rhs.id
    }
}
