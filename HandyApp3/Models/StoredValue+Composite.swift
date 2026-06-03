import Foundation

// MARK: - Composite value helpers

extension StoredValue {

    /// The sub-value stored for `name` if this is a composite, else nil.
    func compositeField(_ name: String) -> StoredValue? {
        guard case .composite(let dict) = self else { return nil }
        return dict[name]
    }

    /// Returns `current` with `field` set to `sub` (or removed when `sub` is nil),
    /// collapsing to `nil` once the composite has no fields left — mirroring how the
    /// basic edit rows null out an empty value.
    static func updatingComposite(
        _ current: StoredValue?,
        field: String,
        to sub: StoredValue?
    ) -> StoredValue? {
        var dict: [String: StoredValue]
        if case .composite(let existing) = current { dict = existing } else { dict = [:] }
        if let sub { dict[field] = sub } else { dict.removeValue(forKey: field) }
        return dict.isEmpty ? nil : .composite(dict)
    }

    /// A compact, human-readable rendering of a single value.
    var shortDisplay: String {
        switch self {
        case .text(let s):     return s
        case .number(let d):   return Self.numberFormatter.string(from: d as NSNumber) ?? "\(d)"
        case .currency(let d): return Self.currencyFormatter.string(from: d as NSDecimalNumber) ?? "\(d)"
        case .date(let date):  return Self.dateFormatter.string(from: date)
        case .contact(let id): return id
        case .data:            return "data"
        case .composite(let dict):
            return dict.values.map(\.shortDisplay).joined(separator: " · ")
        }
    }

    /// Joins the set fields' `shortDisplay` in the definition's field order, e.g. `4 · 8 · ft`.
    /// Empty when no fields are set, so callers can show a placeholder.
    func compositeSummary(for definition: CompositeTypeDefinition) -> String {
        definition.fields
            .compactMap { compositeField($0.name)?.shortDisplay }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    // MARK: - Formatters

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 4
        return f
    }()

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}

// MARK: - Composite type display

extension CompositeTypeDefinition {

    /// First letters of each field name joined with "x", e.g. Width/Length/Unit → "WxLxU".
    /// Used as a compact hint after the property name in edit/detail rows.
    var fieldInitials: String {
        fields
            .compactMap { $0.name.first.map { String($0).uppercased() } }
            .joined(separator: "x")
    }
}
