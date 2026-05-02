//
//  BuiltInTypes.swift
//  HandyApp3
//
//  Created by Hao Deng on 5/2/26.
//

import Foundation

/// A library of pre-defined composite type templates.
/// Each factory method returns a *new* instance ready to be passed to
/// `AssetStore.seedBuiltInTypes()` or `AssetStore.createCompositeType(...)`.
enum BuiltInTypes {

    /// Width × Height composite with an optional Unit label.
    ///
    /// Fields:
    ///   • Width  — Number   (required)
    ///   • Height — Number   (required)
    ///   • Unit   — Text     (optional, e.g. UnitIndex.feet.symbol → "ft")
    static func widthByHeight(scope: CompositeTypeScope = .global) -> CompositeTypeDefinition {
        CompositeTypeDefinition(
            name: "W × H",
            fields: [
                PropertyDefinition(name: "Width",  type: .basic(.number), isRequired: true),
                PropertyDefinition(name: "Height", type: .basic(.number), isRequired: true),
                PropertyDefinition(name: "Unit",   type: .basic(.text),   isRequired: false),
            ],
            scope: scope
        )
    }
}

// MARK: - AssetStore seeding

extension AssetStore {

    /// Registers all built-in composite type templates.
    /// Idempotent — skips any template whose name already exists in the store.
    /// Call once at app startup (or in tests) before creating assets that use built-in types.
    @discardableResult
    func seedBuiltInTypes(scope: CompositeTypeScope = .global) -> [CompositeTypeDefinition] {
        let templates: [CompositeTypeDefinition] = [
            BuiltInTypes.widthByHeight(scope: scope),
        ]
        var seeded: [CompositeTypeDefinition] = []
        for template in templates {
            guard !compositeTypes.values.contains(where: { $0.name == template.name }) else { continue }
            let registered = createCompositeType(name: template.name, fields: template.fields, scope: template.scope)
            seeded.append(registered)
        }
        return seeded
    }
}
