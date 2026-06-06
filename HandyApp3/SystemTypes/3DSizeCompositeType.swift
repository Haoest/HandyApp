import Foundation

// MARK: - 3D Size System Type

extension BuiltInTypes {

    /// Width × Length × Height composite with an optional Unit label.
    ///
    /// Typical use cases: room dimensions, furniture size, box/storage volume.
    ///
    /// Fields:
    ///   • Width  — Number   (required)
    ///   • Length — Number   (required)
    ///   • Height — Number   (required)
    ///   • Unit   — Text     (optional, e.g. UnitIndex.feet.symbol → "ft")
    static func size3D() -> CompositeTypeDefinition {
        CompositeTypeDefinition(
            name: "3D Size",
            fields: [
                PropertyDefinition(name: "Width",  type: .basic(.number), isRequired: true),
                PropertyDefinition(name: "Length", type: .basic(.number), isRequired: true),
                PropertyDefinition(name: "Height", type: .basic(.number), isRequired: true),
                PropertyDefinition(name: "Unit",   type: .basic(.text),   isRequired: false),
            ],
            labelHint: "WxLxH"
        )
    }
}
