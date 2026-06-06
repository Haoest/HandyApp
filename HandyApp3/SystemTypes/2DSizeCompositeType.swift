import Foundation

// MARK: - 2D Size System Type

extension BuiltInTypes {

    /// Width × Length composite with an optional Unit label.
    ///
    /// Typical use cases: lot size, floor plan area, carpet/flooring measurements.
    ///
    /// Fields:
    ///   • Width  — Number   (required)
    ///   • Length — Number   (required)
    ///   • Unit   — Text     (optional, e.g. UnitIndex.feet.symbol → "ft")
    static func size2D() -> CompositeTypeDefinition {
        CompositeTypeDefinition(
            name: "2D Size",
            fields: [
                PropertyDefinition(name: "Width",  type: .basic(.number), isRequired: true),
                PropertyDefinition(name: "Length", type: .basic(.number), isRequired: true),
                PropertyDefinition(name: "Unit",   type: .basic(.text),   isRequired: false),
            ],
            labelHint: "WxL"
        )
    }
}
