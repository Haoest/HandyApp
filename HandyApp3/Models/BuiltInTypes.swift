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

    /// Registers all built-in combo list templates.
    /// Idempotent — skips any list whose name already exists in the store.
    /// Call once at app startup (or in tests) before creating assets that use built-in combo lists.
    @discardableResult
    func seedBuiltInComboLists() -> [ComboListDefinition] {
        let templates: [ComboListDefinition] = [
            BuiltInTypes.applianceComboList(),
            BuiltInTypes.powerSourceComboList(),
        ]
        var seeded: [ComboListDefinition] = []
        for template in templates {
            guard !comboListDefinitions.values.contains(where: { $0.name == template.name }) else { continue }
            let registered = createComboList(
                name: template.name,
                systemOptions: template.systemOptions,
                userOptions: template.userOptions,
                isUserExtensible: template.isUserExtensible
            )
            seeded.append(registered)
        }
        return seeded
    }

    /// Registers all built-in composite type templates.
    /// Idempotent — skips any template whose name already exists in the store.
    /// Call once at app startup (or in tests) before creating assets that use built-in types.
    @discardableResult
    func seedBuiltInTypes(scope: CompositeTypeScope = .global) -> [CompositeTypeDefinition] {
        let applianceCL = comboListDefinitions.values.first { $0.name == "ApplianceComboList" }
                          ?? BuiltInTypes.applianceComboList()
        let powerSourceCL = comboListDefinitions.values.first { $0.name == "PowerSourceComboList" }
                            ?? BuiltInTypes.powerSourceComboList()
        let templates: [CompositeTypeDefinition] = [
            BuiltInTypes.widthByLength(scope: scope),
            BuiltInTypes.widthByLengthByHeight(scope: scope),
            BuiltInTypes.appliance(applianceComboList: applianceCL, powerSourceComboList: powerSourceCL, scope: scope),
        ]
        var seeded: [CompositeTypeDefinition] = []
        for template in templates {
            guard !compositeTypes.values.contains(where: { $0.name == template.name }) else { continue }
            let registered = createCompositeType(
                name: template.name,
                systemFields: template.systemFields,
                userFields: template.userFields,
                isUserExtensible: template.isUserExtensible,
                scope: template.scope
            )
            seeded.append(registered)
        }
        return seeded
    }
}
