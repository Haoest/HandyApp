import Foundation

// MARK: - UnitCategory

/// Top-level grouping for units (e.g. shown as section headers in a picker).
enum UnitCategory: String, CaseIterable, Equatable, Hashable {
    case length
    case weight

    var displayName: String { rawValue.capitalized }
}

// MARK: - UnitDefinition

/// A single, immutable unit entry in the index.
/// `id` is a stable dot-namespaced string (e.g. "length.inch") safe to persist.
struct UnitDefinition: Identifiable, Equatable, Hashable {
    /// Stable string identifier — safe to store and compare across launches.
    let id: String
    /// Human-readable name, e.g. "Inch".
    let name: String
    /// Short symbol shown inline, e.g. "in".
    let symbol: String
    let category: UnitCategory

    /// Convenience display string: "Inch (in)"
    var displayName: String { "\(name) (\(symbol))" }
}

// MARK: - UnitIndex

/// Central catalog of known units.
/// To add a new unit: declare a `static let`, then append it to `all`. Nothing else changes.
enum UnitIndex {

    // MARK: Length

    static let inch       = UnitDefinition(id: "length.inch",       name: "Inch",       symbol: "in", category: .length)
    static let feet       = UnitDefinition(id: "length.feet",       name: "Feet",       symbol: "ft", category: .length)
    static let yard       = UnitDefinition(id: "length.yard",       name: "Yard",       symbol: "yd", category: .length)
    static let mile       = UnitDefinition(id: "length.mile",       name: "Mile",       symbol: "mi", category: .length)
    static let centimeter = UnitDefinition(id: "length.centimeter", name: "Centimeter", symbol: "cm", category: .length)
    static let meter      = UnitDefinition(id: "length.meter",      name: "Meter",      symbol: "m",  category: .length)

    // MARK: Weight

    static let pound      = UnitDefinition(id: "weight.pound",      name: "Pound",      symbol: "lb", category: .weight)
    static let ounce      = UnitDefinition(id: "weight.ounce",      name: "Ounce",      symbol: "oz", category: .weight)
    static let kilogram   = UnitDefinition(id: "weight.kilogram",   name: "Kilogram",   symbol: "kg", category: .weight)
    static let gram       = UnitDefinition(id: "weight.gram",       name: "Gram",       symbol: "g",  category: .weight)

    // MARK: - Catalog

    /// Every known unit, in display order.
    static let all: [UnitDefinition] = [
        inch, feet, yard, mile, centimeter, meter,
        pound, ounce, kilogram, gram,
    ]

    /// Returns all units belonging to the given category, preserving display order.
    static func units(for category: UnitCategory) -> [UnitDefinition] {
        all.filter { $0.category == category }
    }

    /// Look up a unit by its stable id. Returns `nil` for unknown ids.
    static func unit(id: String) -> UnitDefinition? {
        all.first { $0.id == id }
    }

    /// Look up a unit by its symbol (case-sensitive). Returns `nil` if not found.
    static func unit(symbol: String) -> UnitDefinition? {
        all.first { $0.symbol == symbol }
    }
}
