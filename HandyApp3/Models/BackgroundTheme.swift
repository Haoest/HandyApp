import Foundation

/// User-selectable app backdrop. Each case is a calm, light, geometric gradient; the
/// choice lives on `AssetStore.backgroundTheme` and persists as the raw value.
///
/// Nothing renders this any more: the Baron palette follows the system light/dark setting, so
/// the gradient backdrops and their picker are gone. The type stays because the choice is
/// persisted and synced per device, and dropping it would mean a migration for a setting a
/// future theme picker could still use.
enum BackgroundTheme: String, CaseIterable, Identifiable {
    case mist, sand, facets

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mist: return "Mist"
        case .sand: return "Sand"
        case .facets: return "Facets"
        }
    }
}
