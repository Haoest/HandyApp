import Foundation

extension BuiltInTypes {

    static func retailerComboList() -> ComboListDefinition {
        ComboListDefinition(
            id: deterministicID("comboList.retailer"),
            name: "Retailer",
            // Home Depot and Lowes are seeded as user options, not system options, so they
            // stay writable — the user can rename or remove them like anything else they add.
            userOptions: [
                "Home Depot",
                "Lowes",
            ],
            isUserExtensible: true
        )
    }
}
