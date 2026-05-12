import Foundation

/// Read-only query layer over AssetStore for category lookup.
final class CategoryRegistry {
    private let store: AssetStore

    init(store: AssetStore) {
        self.store = store
    }

    var allCategories: [AssetCategory] {
        store.allCategories
    }

    func category(named name: String) -> AssetCategory? {
        store.allCategories.first { $0.name == name }
    }
}
