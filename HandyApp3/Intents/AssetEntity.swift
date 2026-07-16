import AppIntents

struct AssetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Asset"
    static let defaultQuery = AssetEntityQuery()

    let id: UUID
    let name: String
    let categoryName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(categoryName)")
    }

    @MainActor
    init(_ asset: Asset) {
        id = asset.id
        name = asset.name
        categoryName = asset.category.name
    }
}

struct AssetEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [AssetEntity] {
        let store = AppDependencies.shared.store
        return identifiers.compactMap { store.assets[$0] }
            .filter { !$0.isDeleted }
            .map(AssetEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [AssetEntity] {
        let store = AppDependencies.shared.store
        return AssetNameMatcher.match(string, in: store.allAssets).map(AssetEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [AssetEntity] {
        let store = AppDependencies.shared.store
        return store.allAssets
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .prefix(20)
            .map(AssetEntity.init)
    }
}
