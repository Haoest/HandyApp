import Foundation

extension BuiltInTypes {

    static func powerSourceComboList() -> ComboListDefinition {
        ComboListDefinition(
            id: deterministicID("comboList.powerSource"),
            name: "Power Source",
            systemOptions: [
                "Electricity",
                "Natural Gas",
            ],
            isUserExtensible: true
        )
    }
}
