import SwiftUI

/// One capsule in a category filter row: a category and how many things sit in it, or the
/// leading "All" chip whose `id` is nil.
struct CategoryFilterChip: Identifiable {
    /// The category's id; `nil` for the "All" chip.
    let id: UUID?
    let name: String
    let count: Int

    /// "All" followed by every category holding at least one of `assets`, by name.
    ///
    /// Derived from the assets themselves rather than from `AssetStore.allCategories`, which
    /// is `Dictionary.values` and therefore in no particular order — two launches would chip
    /// the same library differently. A category with no things can't appear here by
    /// construction, so nothing needs filtering afterwards.
    static func chips(for assets: [Asset]) -> [CategoryFilterChip] {
        var countByID: [UUID: (name: String, count: Int)] = [:]
        for asset in assets {
            let category = asset.category
            countByID[category.id, default: (BuiltInTypes.localizedSeedName(id: category.id, currentName: category.name), 0)].count += 1
        }
        let all = CategoryFilterChip(id: nil, name: String(localized: "All", bundle: .appPreferred, locale: .appPreferred), count: assets.count)
        let byCategory = countByID
            .map { CategoryFilterChip(id: $0.key, name: $0.value.name, count: $0.value.count) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        return [all] + byCategory
    }
}

/// Horizontal row of category filter capsules, shared by the Things tab and the quick-log
/// thing picker so both filter the same way and look the same doing it.
///
/// Counts are over the whole list the chips were built from, not over whatever the search box
/// has narrowed it to — a chip reading "Vehicles 3" while showing one row is telling you what
/// clearing the search would get you.
struct CategoryFilterChips: View {
    let chips: [CategoryFilterChip]
    @Binding var selection: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(chips) { chip in
                    let selected = chip.id == selection
                    Button { selection = chip.id } label: {
                        HStack(spacing: 5) {
                            Text(chip.name)
                            Text("\(chip.count)").opacity(0.55)
                        }
                        .font(Baron.body(12.5, .medium))
                        .foregroundStyle(selected ? Color.white : Baron.text)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(selected ? Baron.fill : Baron.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(selected ? Color.clear : Baron.neutral300,
                                                        lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
            .padding(.bottom, 4)
        }
        .scrollClipDisabled()
    }
}
