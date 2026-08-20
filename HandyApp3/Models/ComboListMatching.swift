import Foundation

extension ComboListDefinition {
    /// Options to offer for a partially-typed draft: case-insensitive substring match,
    /// capped at ten. Returns nothing once the draft exactly names the only match, so a
    /// finished entry stops showing a redundant suggestion.
    ///
    /// Pure and view-free — `ComboListField` renders whatever this returns.
    func matchingOptions(for draft: String) -> [String] {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        // Defensive: an empty option should never be stored (see AssetStore.createComboList/
        // addUserOption), but never render one as a pill if one somehow is.
        let all = allOptions.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let filtered = trimmed.isEmpty
            ? all
            : all.filter { $0.localizedCaseInsensitiveContains(trimmed) }
        if filtered.count == 1, filtered[0].caseInsensitiveCompare(trimmed) == .orderedSame {
            return []
        }
        return Array(filtered.prefix(10))
    }
}
