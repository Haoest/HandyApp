import Foundation

// MARK: - Appliance Combo List

extension BuiltInTypes {

    /// A predefined combo list of common household appliances.
    ///
    /// System options (non-removable):
    ///   • Refrigerator
    ///   • Range
    ///   • Cloth Washer
    ///   • Cloth Dryer
    static func applianceComboList() -> ComboListDefinition {
        ComboListDefinition(
            name: "ApplianceComboList",
            systemOptions: [
                "Refrigerator",
                "Range",
                "Cloth Washer",
                "Cloth Dryer",
                "HVAC"
            ],
            isUserExtensible: true
        )
    }
}
