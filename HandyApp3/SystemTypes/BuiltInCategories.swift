import Foundation

// MARK: - Built-in AssetCategory factories

extension BuiltInTypes {

    /// Shared appliance fields in display order.
    static let applianceBaseDefinitions: [PropertyDefinition] = [
        PropertyDefinition(name: "Make",          type: .basic(.text),     isRequired: true),
        PropertyDefinition(name: "Purchase date", type: .basic(.date),     isRequired: false),
        PropertyDefinition(name: "Price",         type: .basic(.currency), isRequired: false),
        PropertyDefinition(name: "Warranty",      type: .basic(.text),     isRequired: false),
        PropertyDefinition(name: "Retailer",      type: .basic(.text),     isRequired: false),
        PropertyDefinition(name: "Notes",         type: .basic(.text),     isRequired: false),
    ]

    /// SF Symbol name for each system category. Appliance descendants share the appliance icon.
    static let categoryIcons: [SystemCategory: String] = {
        let applianceIcon = "washer"
        return [
            .residentialHousing: "house",
            .automobile:         "car",
            .appliance:          applianceIcon,
            .refrigerator:       applianceIcon,
            .clothWasher:        applianceIcon,
            .hvac:               applianceIcon,
            .range:              applianceIcon,
            .clothDryer:         applianceIcon,
        ]
    }()

    /// Keyed by SystemCategory; value is the ordered list of property definitions.
    static let categoryTemplates: [SystemCategory: [PropertyDefinition]] = {
        let applianceBase = applianceBaseDefinitions
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
