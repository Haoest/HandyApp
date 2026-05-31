import SwiftUI

struct AssetTab: View {
    @Environment(AssetStore.self) private var store
    @State private var newAssetPresented = false

    private var groupedAssets: [(category: AssetCategory, assets: [Asset])] {
        let grouped = Dictionary(grouping: store.allAssets) { $0.category.id }
        return grouped
            .compactMap { catID, assets -> (AssetCategory, [Asset])? in
                guard let cat = store.categories[catID] else { return nil }
                return (cat, assets.sorted { $0.name.localizedCompare($1.name) == .orderedAscending })
            }
            .sorted { $0.0.name.localizedCompare($1.0.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.allAssets.isEmpty {
                    ContentUnavailableView(
                        "No Assets",
                        systemImage: "shippingbox",
                        description: Text("Tap + to add your first asset.")
                    )
                } else {
                    List {
                        ForEach(groupedAssets, id: \.category.id) { group in
                            Section(header: Label(group.category.name, systemImage: group.category.iconName)) {
                                ForEach(group.assets) { asset in
                                    NavigationLink(destination: AssetDetailView(asset: asset)) {
                                        AssetRow(asset: asset)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Assets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newAssetPresented = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $newAssetPresented) {
                NewAssetSheet()
            }
        }
    }
}

private struct AssetRow: View {
    let asset: Asset

    var body: some View {
        HStack {
            Text(asset.name)
            Spacer()
            Text(asset.modifiedDate, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
