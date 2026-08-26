import Foundation

/// Fixed, non-user-configurable character bounds for entity text fields — as opposed to
/// `PropertyDefinition.maxLength`, which is per-property and user-set. Applied both as a store-side
/// clamp (`AssetStore`) and as a view-side `.limitLength(...)` so typing simply stops at the bound.
enum TextLimits {
    static let assetName = 40
    static let categoryName = 40
    static let propertyName = 40
    static let comboListName = 40
    static let comboListOption = 60
    static let compositeTypeName = 40
    static let eventTitle = 40
    static let eventNotes = 1000
    static let transactionDetails = 40
    static let transactionNotes = 1000
    static let photoCaption = 200

    /// Clamps to `limit`, counting `Character`s (grapheme clusters).
    static func clamp(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit))
    }
}
