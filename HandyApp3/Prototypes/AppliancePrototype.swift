import Foundation

extension BuiltInTypes {

    /// Appliance composite type.
    ///
    /// System fields (non-removable):
    ///   • Type          — ComboList (ApplianceComboList)
    ///   • Make          — Text
    ///   • PurchaseDate  — Date
    ///   • Price         — Currency
    ///   • Retailer      — Text
    ///
    /// `isUserExtensible: true` — users may add additional fields.
    static func appliance(
        applianceComboList: ComboListDefinition,
        powerSourceComboList: ComboListDefinition,
        scope: CompositeTypeScope = .global
    ) -> CompositeTypeDefinition {
        CompositeTypeDefinition(
            name: "Appliance",
            systemFields: [
                PropertyDefinition(name: "Type",         type: .comboList(applianceComboList), isRequired: true),
                PropertyDefinition(name: "Make",         type: .basic(.text),                  isRequired: true),
                PropertyDefinition(name: "PurchaseDate", type: .basic(.date),                  isRequired: false),
                PropertyDefinition(name: "Price",        type: .basic(.currency),              isRequired: false),
                PropertyDefinition(name: "PowerSource",  type: .comboList(powerSourceComboList),     isRequired: false),
                PropertyDefinition(name: "Retailer",     type: .basic(.text),                  isRequired: false),
                PropertyDefinition(name: "Notes",        type: .basic(.text),                        isRequired: false),
                
            ],
            isUserExtensible: true,
            scope: scope
        )
    }
}
