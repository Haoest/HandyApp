import Foundation

// MARK: - Built-in AssetCategory factories

extension BuiltInTypes {

    /// One property template as declared in `categoryTemplates`: a definition paired with the
    /// explicit `sortOrder` it seeds onto the `AssetProperty` wrapping it (see
    /// `AssetStore.seedBuiltInCategories`/`upgradeBuiltInCategories`). Spelled out here, at the
    /// declaration site, rather than derived from array position at seed time — so the display
    /// order a category was shipped with stays legible straight from this list, and inserting a
    /// field between two existing ones doesn't require renumbering everything after it.
    struct BuiltInField {
        let definition: PropertyDefinition
        let sortOrder: Double

        init(_ definition: PropertyDefinition, sortOrder: Double) {
            self.definition = definition
            self.sortOrder = sortOrder
        }
    }

    /// Shared appliance fields in display order.
    static let applianceBaseDefinitions: [BuiltInField] = [
        BuiltInField(PropertyDefinition(id: deterministicID("field.appliance.Type"),          name: "Type",          type: .comboList(applianceTypeComboList()), isRequired: true,  maxLength: 40), sortOrder: 0),
        BuiltInField(PropertyDefinition(id: deterministicID("field.appliance.Make"),          name: "Make",          type: .basic(.text),          isRequired: true,                maxLength: 60), sortOrder: 10),
        BuiltInField(PropertyDefinition(id: deterministicID("field.appliance.Purchase date"), name: "Purchase date", type: .basic(.date),          isRequired: false),                              sortOrder: 20),
        BuiltInField(PropertyDefinition(id: deterministicID("field.appliance.Price"),         name: "Price",         type: .basic(.currency),      isRequired: false),                              sortOrder: 30),
        BuiltInField(PropertyDefinition(id: deterministicID("field.appliance.Power source"),  name: "Power source",   type: .comboList(powerSourceComboList()), isRequired: false, maxLength: 40),  sortOrder: 40),
        BuiltInField(PropertyDefinition(id: deterministicID("field.appliance.Size"),          name: "Size",          type: .composite(size3D()),   isRequired: false),                              sortOrder: 50),
        BuiltInField(PropertyDefinition(id: deterministicID("field.appliance.Warranty"),      name: "Warranty",      type: .basic(.text),          isRequired: false,               maxLength: 200), sortOrder: 60),
        BuiltInField(PropertyDefinition(id: deterministicID("field.appliance.Retailer.comboList"), name: "Retailer", type: .comboList(retailerComboList()), isRequired: false,       maxLength: 60), sortOrder: 70),
        BuiltInField(PropertyDefinition(id: deterministicID("field.appliance.Notes"),         name: "Notes",         type: .basic(.text),          isRequired: false,               maxLength: 500), sortOrder: 80),
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

    /// Keyed by SystemCategory; value is the ordered list of property templates, each carrying
    /// the explicit `sortOrder` it seeds onto the asset's `AssetProperty` — see `BuiltInField`.
    static let categoryTemplates: [SystemCategory: [BuiltInField]] = {
        let applianceBase = applianceBaseDefinitions
        return [
            .residentialHousing: [
                BuiltInField(PropertyDefinition(id: deterministicID("field.residentialHousing.Address"),       name: "Address",       type: .basic(.text),    isRequired: true,  maxLength: 200), sortOrder: 0),
                BuiltInField(PropertyDefinition(id: deterministicID("field.residentialHousing.Purchase date"), name: "Purchase date", type: .basic(.date),    isRequired: false), sortOrder: 10),
                BuiltInField(PropertyDefinition(id: deterministicID("field.residentialHousing.HOA Contact"),   name: "HOA Contact",   type: .basic(.contact), isRequired: false), sortOrder: 20),
                BuiltInField(PropertyDefinition(id: deterministicID("field.residentialHousing.Lot Size"),           name: "Lot Size",           type: .basic(.text),   isRequired: false, maxLength: 40),  sortOrder: 30),
                BuiltInField(PropertyDefinition(id: deterministicID("field.residentialHousing.Year Built"),         name: "Year Built",         type: .basic(.number), isRequired: false), sortOrder: 40),
                BuiltInField(PropertyDefinition(id: deterministicID("field.residentialHousing.Gas Provider"),       name: "Gas Provider",       type: .basic(.text),   isRequired: false, maxLength: 80),  sortOrder: 50),
                BuiltInField(PropertyDefinition(id: deterministicID("field.residentialHousing.Water Provider"),     name: "Water Provider",     type: .basic(.text),   isRequired: false, maxLength: 80),  sortOrder: 60),
                BuiltInField(PropertyDefinition(id: deterministicID("field.residentialHousing.Electricity Provider"), name: "Electricity Provider", type: .basic(.text), isRequired: false, maxLength: 80), sortOrder: 70),
                BuiltInField(PropertyDefinition(id: deterministicID("field.residentialHousing.Roof"),               name: "Roof (material, year, expected lifespan)", type: .basic(.text), isRequired: false, maxLength: 200), sortOrder: 80),
                BuiltInField(PropertyDefinition(id: deterministicID("field.residentialHousing.Home Insurance"),     name: "Home Insurance",     type: .basic(.text),   isRequired: false, maxLength: 120), sortOrder: 90),
                BuiltInField(PropertyDefinition(id: deterministicID("field.residentialHousing.Mortgage Lender"),    name: "Mortgage Lender",    type: .basic(.text),   isRequired: false, maxLength: 120), sortOrder: 100),
                BuiltInField(PropertyDefinition(id: deterministicID("field.residentialHousing.Tax ID"),             name: "Tax ID",             type: .basic(.text),   isRequired: false, maxLength: 40),  sortOrder: 110),
            ],
            .rentalHome: [
                BuiltInField(PropertyDefinition(id: deterministicID("field.rentalHome.Address"),       name: "Address",       type: .basic(.text),    isRequired: true,  maxLength: 200), sortOrder: 0),
                BuiltInField(PropertyDefinition(id: deterministicID("field.rentalHome.Tenant"),        name: "Tenant",        type: .basic(.contact), isRequired: false), sortOrder: 10),
                BuiltInField(PropertyDefinition(id: deterministicID("field.rentalHome.Gas Provider"),       name: "Gas Provider",       type: .basic(.text),    isRequired: false, maxLength: 80),  sortOrder: 20),
                BuiltInField(PropertyDefinition(id: deterministicID("field.rentalHome.Water Provider"),     name: "Water Provider",     type: .basic(.text),    isRequired: false, maxLength: 80),  sortOrder: 30),
                BuiltInField(PropertyDefinition(id: deterministicID("field.rentalHome.Electricity Provider"), name: "Electricity Provider", type: .basic(.text), isRequired: false, maxLength: 80), sortOrder: 40),
                BuiltInField(PropertyDefinition(id: deterministicID("field.rentalHome.Rental License"),     name: "Rental License",     type: .basic(.text),    isRequired: false, maxLength: 60),  sortOrder: 50),
                BuiltInField(PropertyDefinition(id: deterministicID("field.rentalHome.Purchase date"), name: "Purchase date", type: .basic(.date),    isRequired: false), sortOrder: 60),
                BuiltInField(PropertyDefinition(id: deterministicID("field.rentalHome.Roof"),               name: "Roof (material, year, expected lifespan)", type: .basic(.text), isRequired: false, maxLength: 200), sortOrder: 70),
                BuiltInField(PropertyDefinition(id: deterministicID("field.rentalHome.Landlord Insurance"), name: "Landlord Insurance", type: .basic(.text),    isRequired: false, maxLength: 120), sortOrder: 80),
                BuiltInField(PropertyDefinition(id: deterministicID("field.rentalHome.Mortgage Lender"),    name: "Mortgage Lender",    type: .basic(.text),    isRequired: false, maxLength: 120), sortOrder: 90),
                BuiltInField(PropertyDefinition(id: deterministicID("field.rentalHome.Smoke Detector"),     name: "Smoke Detector",     type: .basic(.text),    isRequired: false, maxLength: 120), sortOrder: 100),
                BuiltInField(PropertyDefinition(id: deterministicID("field.rentalHome.Property Manager"),   name: "Property Manager",   type: .basic(.contact), isRequired: false), sortOrder: 110),
                BuiltInField(PropertyDefinition(id: deterministicID("field.rentalHome.Lot Size"),           name: "Lot Size",           type: .basic(.text),    isRequired: false, maxLength: 40),  sortOrder: 120),
                BuiltInField(PropertyDefinition(id: deterministicID("field.rentalHome.Year Built"),         name: "Year Built",         type: .basic(.number),  isRequired: false), sortOrder: 130),
                BuiltInField(PropertyDefinition(id: deterministicID("field.rentalHome.Tax ID"),             name: "Tax ID",             type: .basic(.text),    isRequired: false, maxLength: 40),  sortOrder: 140),
            ],
            .automobile: [
                BuiltInField(PropertyDefinition(id: deterministicID("field.automobile.Make"),          name: "Make",          type: .basic(.text),   isRequired: true,  maxLength: 40), sortOrder: 0),
                BuiltInField(PropertyDefinition(id: deterministicID("field.automobile.Model"),         name: "Model",         type: .basic(.text),   isRequired: true,  maxLength: 60), sortOrder: 10),
                BuiltInField(PropertyDefinition(id: deterministicID("field.automobile.Trim"),          name: "Trim",          type: .basic(.text),   isRequired: false, maxLength: 60), sortOrder: 20),
                BuiltInField(PropertyDefinition(id: deterministicID("field.automobile.Year"),          name: "Year",          type: .basic(.number), isRequired: false), sortOrder: 30),
                BuiltInField(PropertyDefinition(id: deterministicID("field.automobile.License Plate"), name: "License Plate", type: .basic(.text),   isRequired: false, maxLength: 12), sortOrder: 40),
                BuiltInField(PropertyDefinition(id: deterministicID("field.automobile.Registration Number"), name: "Registration Number", type: .basic(.text), isRequired: false, maxLength: 40), sortOrder: 50),
                BuiltInField(PropertyDefinition(id: deterministicID("field.automobile.VIN"),           name: "VIN",           type: .basic(.text),   isRequired: false, maxLength: 17), sortOrder: 60),
                BuiltInField(PropertyDefinition(id: deterministicID("field.automobile.Engine Oil"),    name: "Engine Oil",    type: .basic(.text),   isRequired: false, maxLength: 60), sortOrder: 70),
                BuiltInField(PropertyDefinition(id: deterministicID("field.automobile.Oil Filter"),    name: "Oil Filter",    type: .basic(.text),   isRequired: false, maxLength: 60), sortOrder: 80),
            ],
            .appliance:    applianceBase,
            .noCategory: [
                BuiltInField(PropertyDefinition(id: deterministicID("field.noCategory.Notes"), name: "Notes", type: .basic(.text), isRequired: false, maxLength: 500), sortOrder: 0),
            ],
        ]
    }()
}
