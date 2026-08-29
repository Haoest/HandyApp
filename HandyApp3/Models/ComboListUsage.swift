import Foundation

/// One field that is typed on a given pick list. Powers the editor's "Used by" section, which
/// is what tells the user why renaming an option is consequential.
struct ComboListReference: Identifiable, Equatable {
    /// The template's or property's own id.
    let id: UUID
    /// The category or thing the field belongs to.
    let ownerID: UUID
    let ownerName: String
    let fieldName: String
    /// True for a category template, false for a field on one thing.
    let isTemplate: Bool
}

/// Who points at a pick list, and how heavily each of its options is used.
///
/// Only *top-level* fields are counted. A composite type can hold a combo-list sub-field, but a
/// sub-field has no id of its own to navigate to, so folding those in would produce references
/// that can't be opened. They stay out rather than being listed and dead.
enum ComboListUsage {

    static func references(toComboListID listID: UUID,
                           categories: [AssetCategory],
                           assets: [Asset]) -> [ComboListReference] {
        var result: [ComboListReference] = []
        for category in categories.sorted(by: { $0.name.localizedCompare($1.name) == .orderedAscending }) {
            for template in category.liveTemplates where isTyped(template, on: listID) {
                result.append(ComboListReference(
                    id: template.id, ownerID: category.id, ownerName: category.name,
                    fieldName: template.definition.name, isTemplate: true
                ))
            }
        }
        for asset in assets.sorted(by: { $0.name.localizedCompare($1.name) == .orderedAscending }) {
            // Base properties are per-asset copies of a template that is already listed above;
            // only the asset's *own* custom fields are a distinct reference.
            for property in asset.liveCustomProperties where isTyped(property, on: listID) {
                result.append(ComboListReference(
                    id: property.id, ownerID: asset.id, ownerName: asset.name,
                    fieldName: property.definition.name, isTemplate: false
                ))
            }
        }
        return result
    }

    /// How many stored values across every thing currently hold `option`. Counts base and
    /// custom properties alike — here we want what would actually change, not what is
    /// navigable, so an asset's copy of a template field does count.
    static func storedValueCount(of option: String, listID: UUID, assets: [Asset]) -> Int {
        var count = 0
        for asset in assets {
            for property in asset.liveBaseProperties + asset.liveCustomProperties {
                guard isTyped(property, on: listID), case .text(let value) = property.value else { continue }
                if value == option { count += 1 }
            }
        }
        return count
    }

    private static func isTyped(_ property: AssetProperty, on listID: UUID) -> Bool {
        guard case .comboList(let list) = property.definition.type else { return false }
        return list.id == listID
    }
}
