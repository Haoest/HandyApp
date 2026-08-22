import Foundation

/// Fixed, non-user-configurable character bounds for entity text fields — as opposed to
/// `PropertyDefinition.maxLength`, which is per-property and user-set. Applied both as a store-side
/// clamp (`AssetStore`) and as a view-side `.limitLength(...)` so typing simply stops at the bound.
enum TextLimits {
    static let assetName = 100
    static let categoryName = 60
    static let propertyName = 60
    static let comboListName = 60
    static let comboListOption = 60
    static let compositeTypeName = 60
    static let eventTitle = 120
    static let eventNotes = 1000
    static let transactionDetails = 120
    static let transactionNotes = 1000
    static let photoCaption = 200

    /// Clamps to `limit`, counting `Character`s (grapheme clusters).
    static func clamp(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit))
    }
}
