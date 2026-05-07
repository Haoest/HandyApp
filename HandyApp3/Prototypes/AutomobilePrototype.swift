import Foundation

extension BuiltInTypes {

    static func automobile(scope: CompositeTypeScope = .global) -> CompositeTypeDefinition {
        CompositeTypeDefinition(
            name: "Automobile",
            systemFields: [
                PropertyDefinition(name: "Name",          type: .basic(.text),   isRequired: true),
                PropertyDefinition(name: "Make",          type: .basic(.text),   isRequired: true),
                PropertyDefinition(name: "Model",         type: .basic(.text),   isRequired: true),
                PropertyDefinition(name: "Year",          type: .basic(.number), isRequired: false),
                PropertyDefinition(name: "License Plate", type: .basic(.text),   isRequired: false),
                PropertyDefinition(name: "Engine Oil",    type: .basic(.text),   isRequired: false),
                PropertyDefinition(name: "Oil Filter",    type: .basic(.text),   isRequired: false),
            ],
            isUserExtensible: true,
            scope: scope
        )
    }
}
