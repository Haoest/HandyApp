import Foundation

/// User-selectable app backdrop. Each case is a calm, light, geometric gradient; the
/// choice lives on `AssetStore.backgroundTheme` and persists as the raw value.
///
/// The colors themselves are a view concern — see `BackgroundTheme.palette` in
/// `Views/AppBackground.swift`. Only the identity of a theme belongs here, so the
/// store and the persistence layer don't have to reach into the view layer.
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
