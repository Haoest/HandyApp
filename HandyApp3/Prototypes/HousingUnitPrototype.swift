import Foundation

extension BuiltInTypes {

    static func housingUnit(
        applianceType: CompositeTypeDefinition,
        scope: CompositeTypeScope = .global
    ) -> CompositeTypeDefinition {
        CompositeTypeDefinition(
            name: "HousingUnit",
            systemFields: [
                PropertyDefinition(name: "Address",      type: .basic(.text),           isRequired: true),
                PropertyDefinition(name: "Address2",     type: .basic(.text),           isRequired: false),
                PropertyDefinition(name: "City",         type: .basic(.text),           isRequired: false),
                PropertyDefinition(name: "State",        type: .basic(.text),           isRequired: false),
                PropertyDefinition(name: "Zip",          type: .basic(.text),           isRequired: false),
                PropertyDefinition(name: "Purchase date", type: .basic(.date),           isRequired: false),
                PropertyDefinition(name: "Range",        type: .composite(applianceType), isRequired: false),
                PropertyDefinition(name: "Refrigerator", type: .composite(applianceType), isRequired: false),
            ],
            isUserExtensible: true,
            scope: scope
        )
    }
}
