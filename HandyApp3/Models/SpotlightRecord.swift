import Foundation

/// One asset as it appears in the system Spotlight index.
///
/// Pure and Foundation-only so it compiles into the `swift test` package target and can be
/// unit-tested without CoreSpotlight; `SpotlightIndexer` owns the actual indexing I/O.
///
/// Only the name and its category are indexed — deliberately not property values, notes, or
/// photo captions. Those would put considerably more of the user's data into a system-wide
/// index, and would force a reindex on every property edit.
struct SpotlightRecord: Equatable {
    let id: UUID
    let name: String
    let categoryName: String

    /// Build records for the assets that should be findable.
    ///
    /// Pass `AssetStore.allAssets`, which already excludes soft-deleted and purged assets;
    /// this additionally drops blank names, which would index as an untappable empty row.
    static func records(from assets: [Asset]) -> [SpotlightRecord] {
        assets.compactMap { asset in
            let name = asset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return SpotlightRecord(
                id: asset.id,
                name: name,
                categoryName: asset.category.name.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}
