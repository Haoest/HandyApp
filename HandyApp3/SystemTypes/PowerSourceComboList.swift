import Foundation

extension BuiltInTypes {

    static func powerSourceComboList() -> ComboListDefinition {
        ComboListDefinition(
            name: "Power Source",
            systemOptions: [
                "Electricity",
                "Natural Gas",
            ],
            isUserExtensible: true
        )
    }
}
