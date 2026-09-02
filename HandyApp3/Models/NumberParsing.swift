import Foundation

/// Parses user-typed numbers from a locale-aware decimal pad. `.decimalPad` shows a comma on
/// es/fr keyboards, but `Decimal(string:)` and `Double(_:)` only ever accept `.` — a plain
/// `Decimal(string: "12,50")` silently truncates to `12` rather than failing, and
/// `Double("12,50")` returns nil. Both call sites need `,` accepted as a decimal separator
/// alongside `.`, so a hardware-keyboard `.` still works regardless of the active locale.
///
/// Deliberately does not attempt to parse grouping separators ("1,234.56" / "1.234,56") — nobody
/// types thousands grouping into a phone numeric pad, and guessing which of two separators is
/// the decimal point when both appear is exactly the kind of silent-wrong-value risk this exists
/// to avoid. A string with more than one separator character is rejected rather than guessed at.
///
/// Never use this for the on-disk DTO representation, which is invariant `.` by construction —
/// only for text a person typed into a field.
enum NumberParsing {
    static func decimal(_ text: String, locale: Locale = .appPreferred) -> Decimal? {
        guard let normalized = normalize(text, locale: locale) else { return nil }
        return Decimal(string: normalized)
    }

    static func double(_ text: String, locale: Locale = .appPreferred) -> Double? {
        guard let normalized = normalize(text, locale: locale) else { return nil }
        return Double(normalized)
    }

    /// Accepts `.` or `,` as the decimal separator (whichever one appears), maps it to `.`, and
    /// rejects anything with more than one separator or non-numeric characters.
    private static func normalize(_ text: String, locale: Locale) -> String? {
        let s = text.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        let separatorCount = s.filter { $0 == "." || $0 == "," }.count
        guard separatorCount <= 1 else { return nil }

        let normalized = s.replacingOccurrences(of: ",", with: ".")
        guard normalized.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" || $0 == "+" }) else { return nil }
        guard normalized.contains(where: \.isNumber) else { return nil }
        return normalized
    }
}
