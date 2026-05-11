import Foundation

// MARK: - Image JPG System Type

extension BuiltInTypes {

    /// A JPEG image composed of a format label and raw binary data.
    ///
    /// Fields:
    ///   • imageType — Text  (optional, expected value: "JPG")
    ///   • imageData — Data  (required, raw JPEG bytes)
    static func imageJPG() -> CompositeTypeDefinition {
        CompositeTypeDefinition(
            name: "Image JPG",
            fields: [
                PropertyDefinition(name: "imageType", type: .basic(.text), isRequired: false),
                PropertyDefinition(name: "imageData", type: .basic(.data), isRequired: true),
            ]
        )
    }
}
