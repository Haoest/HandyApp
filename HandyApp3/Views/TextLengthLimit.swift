import SwiftUI

/// Stops a bound `String` from growing past `maxLength` characters — the view-side half of the
/// app's character-bound feature (see `PropertyDefinition.maxLength`, `TextLimits`). Silent, no
/// error message: matches the app's existing convention for an invalid draft (see
/// `ComboListField.commit()`'s revert, and the number/currency rows' unparseable-draft `return`).
private struct TextLengthLimitModifier: ViewModifier {
    let maxLength: Int?
    @Binding var text: String

    func body(content: Content) -> some View {
        content.onChange(of: text) { _, newValue in
            guard let maxLength, newValue.count > maxLength else { return }
            text = String(newValue.prefix(maxLength))
        }
    }
}

extension View {
    /// A `nil` bound is a pass-through — the field stays unlimited.
    func limitLength(_ maxLength: Int?, text: Binding<String>) -> some View {
        modifier(TextLengthLimitModifier(maxLength: maxLength, text: text))
    }
}
