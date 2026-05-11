import Foundation

// MARK: - Built-in AssetCategory factories

extension BuiltInTypes {

    /// Shared appliance fields, keyed by field name.
    static let applianceBaseDefinitions: [String: PropertyDefinition] = [
        "Make":          PropertyDefinition(name: "Make",          type: .basic(.text),     isRequired: true),
        "Purchase date": PropertyDefinition(name: "Purchase date", type: .basic(.date),     isRequired: false),
        "Price":         PropertyDefinition(name: "Price",         type: .basic(.currency), isRequired: false),
        "Warranty":      PropertyDefinition(name: "Warranty",      type: .basic(.text),     isRequired: false),
        "Retailer":      PropertyDefinition(name: "Retailer",      type: .basic(.text),     isRequired: false),
        "Notes":         PropertyDefinition(name: "Notes",         type: .basic(.text),     isRequired: false),
    ]

    /// Keyed by category name; value is the ordered list of property definitions.
    /// Range and Cloth Dryer are excluded — they reference a ComboListDefinition at seed time.
    static let categoryTemplates: [String: [PropertyDefinition]] = {
        let applianceBase = Array(applianceBaseDefinitions.values)
        return [
            "housingUnit": [
                PropertyDefinition(name: "Address",       type: .basic(.text), isRequired: true),
                PropertyDefinition(name: "Address2",      type: .basic(.text), isRequired: false),
                PropertyDefinition(name: "City",          type: .basic(.text), isRequired: false),
                PropertyDefinition(name: "State",         type: .basic(.text), isRequired: false),
                PropertyDefinition(name: "Zip",           type: .basic(.text), isRequired: false),
                PropertyDefinition(name: "Purchase date", type: .basic(.date), isRequired: false),
            ],
            "automobile": [
                PropertyDefinition(name: "Make",          type: .basic(.text),   isRequired: true),
                PropertyDefinition(name: "Model",         type: .basic(.text),   isRequired: true),
                PropertyDefinition(name: "Year",          type: .basic(.number), isRequired: false),
                PropertyDefinition(name: "License Plate", type: .basic(.text),   isRequired: false),
                PropertyDefinition(name: "Engine Oil",    type: .basic(.text),   isRequired: false),
                PropertyDefinition(name: "Oil Filter",    type: .basic(.text),   isRequired: false),
            ],
            "appliance":    applianceBase,
            "refrigerator": applianceBase,
            "clothWasher":  applianceBase,
            "hvac":         applianceBase,
        ]
    }()

    static func rangeCategory(powerSource: ComboListDefinition) -> AssetCategory {
        let defs = (categoryTemplates["appliance"] ?? []) + [
            PropertyDefinition(name: "Power source", type: .comboList(powerSource), isRequired: true),
        ]
        return AssetCategory(name: "Range", propertyTemplates: defs.map { AssetProperty(definition: $0) })
    }

    static func clothDryerCategory(powerSource: ComboListDefinition) -> AssetCategory {
        let defs = (categoryTemplates["appliance"] ?? []) + [
            PropertyDefinition(name: "Power source", type: .comboList(powerSource), isRequired: true),
        ]
        return AssetCategory(name: "Cloth Dryer", propertyTemplates: defs.map { AssetProperty(definition: $0) })
    }
}
