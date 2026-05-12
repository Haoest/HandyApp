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

    /// Keyed by SystemCategory; value is the ordered list of property definitions.
    static let categoryTemplates: [SystemCategory: [PropertyDefinition]] = {
        let applianceBase = Array(applianceBaseDefinitions.values)
        let powerSourceField = PropertyDefinition(name: "Power source", type: .comboList(powerSourceComboList()), isRequired: true)
        return [
            .residentialHousing: [
                PropertyDefinition(name: "Address",       type: .basic(.text), isRequired: true),
                PropertyDefinition(name: "Address2",      type: .basic(.text), isRequired: false),
                PropertyDefinition(name: "City",          type: .basic(.text), isRequired: false),
                PropertyDefinition(name: "State",         type: .basic(.text), isRequired: false),
                PropertyDefinition(name: "Zip",           type: .basic(.text), isRequired: false),
                PropertyDefinition(name: "Purchase date", type: .basic(.date), isRequired: false),
            ],
            .automobile: [
                PropertyDefinition(name: "Make",          type: .basic(.text),   isRequired: true),
                PropertyDefinition(name: "Model",         type: .basic(.text),   isRequired: true),
                PropertyDefinition(name: "Year",          type: .basic(.number), isRequired: false),
                PropertyDefinition(name: "License Plate", type: .basic(.text),   isRequired: false),
                PropertyDefinition(name: "Engine Oil",    type: .basic(.text),   isRequired: false),
                PropertyDefinition(name: "Oil Filter",    type: .basic(.text),   isRequired: false),
            ],
            .appliance:    applianceBase,
            .refrigerator: applianceBase,
            .clothWasher:  applianceBase,
            .hvac:         applianceBase,
            .range:      applianceBase + [powerSourceField],
            .clothDryer: applianceBase + [powerSourceField],
        ]
    }()
}
