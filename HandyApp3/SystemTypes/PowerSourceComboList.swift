import Foundation

extension BuiltInTypes {

    static func powerSourceComboList() -> ComboListDefinition {
        ComboListDefinition(
            name: "PowerSourceComboList",
            systemOptions: [
                "Electricity",
                "Natural Gas",
            ],
            isUserExtensible: true
        )
    }
}
