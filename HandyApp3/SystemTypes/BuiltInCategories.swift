import Foundation

// MARK: - Built-in AssetCategory factories

extension BuiltInTypes {

    /// Shared appliance fields in display order.
    static let applianceBaseDefinitions: [PropertyDefinition] = [
        PropertyDefinition(id: deterministicID("field.appliance.Type"),          name: "Type",          type: .comboList(applianceTypeComboList()), isRequired: true),
        PropertyDefinition(id: deterministicID("field.appliance.Power source"),  name: "Power source",   type: .comboList(powerSourceComboList()), isRequired: false),
        PropertyDefinition(id: deterministicID("field.appliance.Make"),          name: "Make",          type: .basic(.text),          isRequired: true),
        PropertyDefinition(id: deterministicID("field.appliance.Purchase date"), name: "Purchase date", type: .basic(.date),          isRequired: false),
        PropertyDefinition(id: deterministicID("field.appliance.Price"),         name: "Price",         type: .basic(.currency),      isRequired: false),
        PropertyDefinition(id: deterministicID("field.appliance.Size"),          name: "Size",          type: .composite(size3D()),   isRequired: false),
        PropertyDefinition(id: deterministicID("field.appliance.Warranty"),      name: "Warranty",      type: .basic(.text),          isRequired: false),
        PropertyDefinition(id: deterministicID("field.appliance.Retailer.comboList"), name: "Retailer", type: .comboList(retailerComboList()), isRequired: false),
        PropertyDefinition(id: deterministicID("field.appliance.Notes"),         name: "Notes",         type: .basic(.text),          isRequired: false),
    ]

    /// Field ids retired by a template change, keyed by the category that carried them —
    /// e.g. Appliance's old free-text "Retailer" field, superseded by a combo-list-typed
    /// field under a new id (`field.appliance.Retailer.comboList` above) rather than an
    /// in-place type change. The upgrade phase tombstones these on installs that still carry
    /// them; the replacement field is then picked up by the normal "missing canonical field"
    /// pass, since it lives under a different id. See `AssetStore.upgradeBuiltInCategories`.
    static let retiredFieldIDs: [SystemCategory: [UUID]] = [
        .appliance: [deterministicID("field.appliance.Retailer")],
    ]

    /// SF Symbol name for each system category.
    static let categoryIcons: [SystemCategory: String] = {
        let applianceIcon = "washer"
        return [
            .residentialHousing: "house",
            .rentalHome:         "house.and.flag",
            .automobile:         "car",
            .appliance:          applianceIcon,
            .noCategory:         "tray",
        ]
    }()

    /// Keyed by SystemCategory; value is the ordered list of property definitions.
    static let categoryTemplates: [SystemCategory: [PropertyDefinition]] = {
        let applianceBase = applianceBaseDefinitions
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
                PropertyDefinition(id: deterministicID("field.automobile.Trim"),          name: "Trim",          type: .basic(.text),   isRequired: false),
                PropertyDefinition(id: deterministicID("field.automobile.Year"),          name: "Year",          type: .basic(.number), isRequired: false),
                PropertyDefinition(id: deterministicID("field.automobile.License Plate"), name: "License Plate", type: .basic(.text),   isRequired: false),
                PropertyDefinition(id: deterministicID("field.automobile.Registration Number"), name: "Registration Number", type: .basic(.text), isRequired: false),
                PropertyDefinition(id: deterministicID("field.automobile.VIN"),           name: "VIN",           type: .basic(.text),   isRequired: false),
                PropertyDefinition(id: deterministicID("field.automobile.Engine Oil"),    name: "Engine Oil",    type: .basic(.text),   isRequired: false),
                PropertyDefinition(id: deterministicID("field.automobile.Oil Filter"),    name: "Oil Filter",    type: .basic(.text),   isRequired: false),
            ],
            .appliance:    applianceBase,
            .noCategory: [
                PropertyDefinition(id: deterministicID("field.noCategory.Notes"), name: "Notes", type: .basic(.text), isRequired: false),
            ],
        ]
    }()
}
