import Foundation

// MARK: - Built-in AssetCategory factories

extension BuiltInTypes {

    /// Shared appliance fields in display order. Shared verbatim across Appliance,
    /// Refrigerator and HVAC (see `categoryTemplates` below), so these ids are also what
    /// keeps those three categories' fields identical to each other, not just stable
    /// across launches.
    static let applianceBaseDefinitions: [PropertyDefinition] = [
        PropertyDefinition(id: deterministicID("field.appliance.Make"),          name: "Make",          type: .basic(.text),          isRequired: true),
        PropertyDefinition(id: deterministicID("field.appliance.Purchase date"), name: "Purchase date", type: .basic(.date),          isRequired: false),
        PropertyDefinition(id: deterministicID("field.appliance.Price"),         name: "Price",         type: .basic(.currency),      isRequired: false),
        PropertyDefinition(id: deterministicID("field.appliance.Size"),          name: "Size",          type: .composite(size3D()),   isRequired: false),
        PropertyDefinition(id: deterministicID("field.appliance.Warranty"),      name: "Warranty",      type: .basic(.text),          isRequired: false),
        PropertyDefinition(id: deterministicID("field.appliance.Retailer"),      name: "Retailer",      type: .basic(.text),          isRequired: false),
        PropertyDefinition(id: deterministicID("field.appliance.Notes"),         name: "Notes",         type: .basic(.text),          isRequired: false),
    ]

    /// SF Symbol name for each system category. Appliance descendants share the appliance icon.
    static let categoryIcons: [SystemCategory: String] = {
        let applianceIcon = "washer"
        return [
            .residentialHousing: "house",
            .rentalHome:         "house.and.flag",
            .automobile:         "car",
            .appliance:          applianceIcon,
            .refrigerator:       applianceIcon,
            .hvac:               applianceIcon,
            .range:              applianceIcon,
            .noCategory:         "tray",
        ]
    }()

    /// Keyed by SystemCategory; value is the ordered list of property definitions.
    static let categoryTemplates: [SystemCategory: [PropertyDefinition]] = {
        let applianceBase = applianceBaseDefinitions
        let powerSourceField = PropertyDefinition(id: deterministicID("field.range.Power source"), name: "Power source", type: .comboList(powerSourceComboList()), isRequired: true)
        return [
            .residentialHousing: [
                PropertyDefinition(id: deterministicID("field.residentialHousing.Address"),       name: "Address",       type: .basic(.text),    isRequired: true),
                PropertyDefinition(id: deterministicID("field.residentialHousing.Purchase date"), name: "Purchase date", type: .basic(.date),    isRequired: false),
                PropertyDefinition(id: deterministicID("field.residentialHousing.HOA Contact"),   name: "HOA Contact",   type: .basic(.contact), isRequired: false),
            ],
            .rentalHome: [
                PropertyDefinition(id: deterministicID("field.rentalHome.Address"),       name: "Address",       type: .basic(.text),    isRequired: true),
                PropertyDefinition(id: deterministicID("field.rentalHome.Purchase date"), name: "Purchase date", type: .basic(.date),    isRequired: false),
                PropertyDefinition(id: deterministicID("field.rentalHome.Tenant"),        name: "Tenant",        type: .basic(.contact), isRequired: false),
            ],
            .automobile: [
                PropertyDefinition(id: deterministicID("field.automobile.Make"),          name: "Make",          type: .basic(.text),   isRequired: true),
                PropertyDefinition(id: deterministicID("field.automobile.Model"),         name: "Model",         type: .basic(.text),   isRequired: true),
                PropertyDefinition(id: deterministicID("field.automobile.Year"),          name: "Year",          type: .basic(.number), isRequired: false),
                PropertyDefinition(id: deterministicID("field.automobile.License Plate"), name: "License Plate", type: .basic(.text),   isRequired: false),
                PropertyDefinition(id: deterministicID("field.automobile.VIN"),           name: "VIN",           type: .basic(.text),   isRequired: false),
                PropertyDefinition(id: deterministicID("field.automobile.Engine Oil"),    name: "Engine Oil",    type: .basic(.text),   isRequired: false),
                PropertyDefinition(id: deterministicID("field.automobile.Oil Filter"),    name: "Oil Filter",    type: .basic(.text),   isRequired: false),
            ],
            .appliance:    applianceBase,
            .refrigerator: applianceBase,
            .hvac:         applianceBase,
            .range:      applianceBase + [powerSourceField],
            .noCategory: [
                PropertyDefinition(id: deterministicID("field.noCategory.Notes"), name: "Notes", type: .basic(.text), isRequired: false),
            ],
        ]
    }()
}
