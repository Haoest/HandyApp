import Foundation

extension BuiltInTypes {

    static func applianceTypeComboList() -> ComboListDefinition {
        ComboListDefinition(
            id: deterministicID("comboList.applianceType"),
            name: "Appliance Type",
            userOptions: [
                "Range",
                "Refrigerator",
                "Oven",
                "Cloth Washer",
                "Cloth Dryer",
                "HVAC",
                "Dish washer",
            ],
            isUserExtensible: true
        )
    }
}
