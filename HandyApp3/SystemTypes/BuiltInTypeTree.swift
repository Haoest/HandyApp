import Foundation

// MARK: - Built-in TypeNode tree

extension AssetStore {

    /// Seeds the built-in IS-A type tree:
    /// ```
    /// Appliance (abstract)
    ///   ├─ Refrigerator
    ///   ├─ Range            [+ Power source]
    ///   ├─ Cloth Washer
    ///   ├─ Cloth Dryer      [+ Power source]
    ///   └─ HVAC
    /// Automobile
    /// HousingUnit
    /// ```
    /// Idempotent — skips any root whose name already exists at the top level.
    /// Calls `seedBuiltInComboLists()` first since `Range` and `Cloth Dryer`
    /// reference the Power Source combo list.
    func seedBuiltInTypeTree() throws {
        seedBuiltInComboLists()

        let powerSource = comboListDefinitions.values.first { $0.name == "PowerSourceComboList" }
                          ?? BuiltInTypes.powerSourceComboList()

        // --- Appliance branch -----------------------------------------------
        if !typeRoots.contains(where: { $0.name == "Appliance" }) {
            let appliance = try createTypeNode(
                name: "Appliance",
                localFields: [
                    PropertyDefinition(name: "Make",          type: .basic(.text),     isRequired: true),
                    PropertyDefinition(name: "Purchase date", type: .basic(.date),     isRequired: false),
                    PropertyDefinition(name: "Price",         type: .basic(.currency), isRequired: false),
                    PropertyDefinition(name: "Warranty",      type: .basic(.text),     isRequired: false),
                    PropertyDefinition(name: "Retailer",      type: .basic(.text),     isRequired: false),
                    PropertyDefinition(name: "Notes",         type: .basic(.text),     isRequired: false),
                ],
                isAbstract: true
            )
            try createTypeNode(name: "Refrigerator", parentID: appliance.id)
            try createTypeNode(
                name: "Range",
                parentID: appliance.id,
                localFields: [
                    PropertyDefinition(name: "Power source", type: .comboList(powerSource), isRequired: true)
                ]
            )
            try createTypeNode(name: "Cloth Washer", parentID: appliance.id)
            try createTypeNode(
                name: "Cloth Dryer",
                parentID: appliance.id,
                localFields: [
                    PropertyDefinition(name: "Power source", type: .comboList(powerSource), isRequired: true)
                ]
            )
            try createTypeNode(name: "HVAC", parentID: appliance.id)
        }

        // --- Automobile -----------------------------------------------------
        if !typeRoots.contains(where: { $0.name == "Automobile" }) {
            try createTypeNode(
                name: "Automobile",
                localFields: [
                    PropertyDefinition(name: "Make",          type: .basic(.text),   isRequired: true),
                    PropertyDefinition(name: "Model",         type: .basic(.text),   isRequired: true),
                    PropertyDefinition(name: "Year",          type: .basic(.number), isRequired: false),
                    PropertyDefinition(name: "License Plate", type: .basic(.text),   isRequired: false),
                    PropertyDefinition(name: "Engine Oil",    type: .basic(.text),   isRequired: false),
                    PropertyDefinition(name: "Oil Filter",    type: .basic(.text),   isRequired: false),
                ]
            )
        }

        // --- HousingUnit ----------------------------------------------------
        // Contained appliances are now expressed via the asset hierarchy
        // (Asset.parent / children) rather than embedded composite fields.
        if !typeRoots.contains(where: { $0.name == "HousingUnit" }) {
            try createTypeNode(
                name: "HousingUnit",
                localFields: [
                    PropertyDefinition(name: "Address",       type: .basic(.text), isRequired: true),
                    PropertyDefinition(name: "Address2",      type: .basic(.text), isRequired: false),
                    PropertyDefinition(name: "City",          type: .basic(.text), isRequired: false),
                    PropertyDefinition(name: "State",         type: .basic(.text), isRequired: false),
                    PropertyDefinition(name: "Zip",           type: .basic(.text), isRequired: false),
                    PropertyDefinition(name: "Purchase date", type: .basic(.date), isRequired: false),
                ]
            )
        }
    }
}
