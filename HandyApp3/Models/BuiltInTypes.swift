//
//  BuiltInTypes.swift
//  HandyApp3
//
//  Created by Hao Deng on 5/2/26.
//

import Foundation

/// Namespace for built-in composite type factories.
/// Individual types live in `SystemTypes/` as extensions on this enum.
enum BuiltInTypes {}

// MARK: - AssetStore seeding

extension AssetStore {

    /// Registers all built-in composite type templates.
    /// Idempotent — skips any template whose name already exists in the store.
    /// Call once at app startup (or in tests) before creating assets that use built-in types.
    @discardableResult
    func seedBuiltInTypes(scope: CompositeTypeScope = .global) -> [CompositeTypeDefinition] {
        let templates: [CompositeTypeDefinition] = [
            BuiltInTypes.widthByLength(scope: scope),
        ]
        var seeded: [CompositeTypeDefinition] = []
        for template in templates {
            guard !compositeTypes.values.contains(where: { $0.name == template.name }) else { continue }
            let registered = createCompositeType(
                name: template.name,
                systemFields: template.systemFields,
                userFields: template.userFields,
                scope: template.scope
            )
            seeded.append(registered)
        }
        return seeded
    }
}
