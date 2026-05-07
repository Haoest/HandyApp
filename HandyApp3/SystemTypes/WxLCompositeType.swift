import Foundation

// MARK: - W × L System Type

extension BuiltInTypes {

    /// Width × Length composite with an optional Unit label.
    ///
    /// Typical use cases: lot size, floor plan area, carpet/flooring measurements.
    ///
    /// Fields:
    ///   • Width  — Number   (required)
    ///   • Length — Number   (required)
    ///   • Unit   — Text     (optional, e.g. UnitIndex.feet.symbol → "ft")
    static func widthByLength(scope: CompositeTypeScope = .global) -> CompositeTypeDefinition {
        CompositeTypeDefinition(
            name: "W × L",
            systemFields: [
                PropertyDefinition(name: "Width",  type: .basic(.number), isRequired: true),
                PropertyDefinition(name: "Length", type: .basic(.number), isRequired: true),
                PropertyDefinition(name: "Unit",   type: .basic(.text),   isRequired: false),
            ],
            isUserExtensible: false,
            scope: scope
        )
    }
}
