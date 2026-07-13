import SwiftUI

// MARK: - Category tab

private enum CategoryDest: Hashable {
    case propertyDefs(UUID)
}

struct CategoryTab: View {
    @Environment(AssetStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var navigationPath = NavigationPath()
    @State private var expandedCategoryID: UUID?
    @State private var newCategoryPresented = false
    @State private var categoryToDuplicate: AssetCategory?
    @State private var assetToEdit: Asset?
    @State private var paywallPresented = false

    private var sortedCategories: [AssetCategory] {
        store.allCategories.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                AppBackground()
                Group {
                    if store.allCategories.isEmpty {
                        ContentUnavailableView(
                            "No Categories",
                            systemImage: "folder",
                            description: Text("Tap + to create your first category.")
                        )
                    } else {
                        List(sortedCategories) { category in
                            CategoryRow(
                                category: category,
                                isExpanded: expandedCategoryID == category.id,
                                onToggle: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedCategoryID = expandedCategoryID == category.id ? nil : category.id
                                    }
                                },
                                onNewAsset: {
                                    guard store.hasAssetCapacity else { paywallPresented = true; return }
                                    let count = (try? store.assets(ofCategoryID: category.id))?.count ?? 0
                                    let defaultName = "\(category.name) \(count + 1)"
                                    if let asset = try? store.createAsset(name: defaultName, categoryID: category.id) {
                                        assetToEdit = asset
                                    }
                                },
                                onViewAssets: {
                                    router.focusedCategoryID = category.id
                                    router.selectedTab = .assets
                                },
                                onViewDefs: { navigationPath = .init(); navigationPath.append(CategoryDest.propertyDefs(category.id)) },
                                onDuplicate: { categoryToDuplicate = category },
                                onChangeIcon: { newIcon in
                                    try? store.updateCategoryIcon(id: category.id, iconName: newIcon)
                                }
                            )
                            .listRowBackground(Color.white.opacity(0.5))
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
                .environment(\.colorScheme, .light)
            }
            .navigationTitle("Categories")
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newCategoryPresented = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: CategoryDest.self) { dest in
                switch dest {
                case .propertyDefs(let id):
                    if let cat = store.categories[id] { CategoryPropertyDefsView(category: cat) }
                }
            }
            .sheet(isPresented: $newCategoryPresented) { CategoryNewView() }
            .sheet(item: $categoryToDuplicate) { category in CategoryNewView(duplicating: category) }
            .sheet(item: $assetToEdit) { asset in NavigationStack { AssetEditView(asset: asset) } }
            .sheet(isPresented: $paywallPresented) { PaywallView() }
        }
    }
}

// MARK: - Category row

private struct CategoryRow: View {
    let category: AssetCategory
    let isExpanded: Bool
    let onToggle: () -> Void
    let onNewAsset: () -> Void
    let onViewAssets: () -> Void
    let onViewDefs: () -> Void
    let onDuplicate: () -> Void
    let onChangeIcon: (String) -> Void

    @State private var iconPickerPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { iconPickerPresented = true } label: {
                    Image(systemName: category.iconName)
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Button(action: onToggle) {
                    Text(category.name)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button(action: onNewAsset) {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.large)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                HStack(spacing: 32) {
                    Button(action: onViewAssets) {
                        VStack(spacing: 4) {
                            Image(systemName: "shippingbox")
                                .imageScale(.large)
                            Text("Assets")
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                    Button(action: onViewDefs) {
                        VStack(spacing: 4) {
                            Image(systemName: "list.bullet.clipboard")
                                .imageScale(.large)
                            Text("Definitions")
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                    Button(action: onDuplicate) {
                        VStack(spacing: 4) {
                            Image(systemName: "plus.square.on.square")
                                .imageScale(.large)
                            Text("Duplicate")
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $iconPickerPresented) {
            IconPickerView(current: category.iconName) { newIcon in
                onChangeIcon(newIcon)
                iconPickerPresented = false
            }
        }
    }
}
