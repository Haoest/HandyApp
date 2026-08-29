import SwiftUI

// MARK: - Shared chrome

/// Back button, breadcrumb, optional trailing action — the header every Setup sub-screen wears.
struct SetupScreenHeader<Trailing: View>: View {
    @Environment(\.dismiss) private var dismiss
    let breadcrumb: LocalizedStringKey
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(Baron.heading(15))
                    .foregroundStyle(Baron.accent800)
                    .frame(width: 36, height: 36)
                    .background(Baron.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Baron.neutral300, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Text(breadcrumb)
                .font(Baron.body(11.5, .medium))
                .tracking(0.55)
                .foregroundStyle(Baron.neutral600)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.top, 8)
    }
}

extension SetupScreenHeader where Trailing == EmptyView {
    init(breadcrumb: LocalizedStringKey) {
        self.init(breadcrumb: breadcrumb) { EmptyView() }
    }
}

/// The filled "+ New" pill the list screens put in their header.
struct SetupNewButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("+ New")
                .font(Baron.heading(11.5))
                .tracking(0.85)
                .textCase(.uppercase)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Baron.fill, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Title + explanatory line, shared by the list screens.
struct SetupScreenTitle: View {
    let title: LocalizedStringKey
    let blurb: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Baron.heading(30))
                .foregroundStyle(Baron.text)
            Text(blurb)
                .font(Baron.body(13))
                .foregroundStyle(Baron.neutral600)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 16)
    }
}

/// Screen scaffold: Baron ground, hidden nav bar, page insets.
struct SetupScreenBody<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Baron.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(.horizontal, Baron.pageInset)
                    .padding(.bottom, 28)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Categories

/// The category list. The old tab's per-row expand/collapse with three tiny icon buttons
/// (Assets / Definitions / Duplicate) is gone — the audit read that strip as a mini tab bar
/// pretending to be one. A row now just opens its category; the three actions live inside.
struct CategoriesListView: View {
    @Environment(AssetStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var newCategoryPresented = false
    @State private var categoryToDuplicate: AssetCategory?
    @State private var openCategoryID: UUID?

    private var sorted: [AssetCategory] {
        store.allCategories.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private func thingCount(_ category: AssetCategory) -> Int {
        store.allAssets.filter { $0.category.id == category.id }.count
    }

    var body: some View {
        SetupScreenBody {
            SetupScreenHeader(breadcrumb: "Setup") {
                SetupNewButton { newCategoryPresented = true }
            }
            SetupScreenTitle(
                title: "Categories",
                blurb: "A category is a template. Its fields and its icon are copied into every thing you file under it."
            )
            if sorted.isEmpty {
                Text("Tap + New to create your first category.")
                    .font(Baron.body(13))
                    .foregroundStyle(Baron.neutral600)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .baronCard(radius: 16, elevation: .low)
                    .padding(.top, 18)
            } else {
                VStack(spacing: 10) {
                    ForEach(sorted) { category in
                        Button { openCategoryID = category.id } label: {
                            HStack(spacing: 12) {
                                Image(systemName: category.iconName)
                                    .font(.system(size: 21, weight: .light))
                                    .foregroundStyle(Baron.accent800)
                                    .frame(width: 46, height: 46)
                                    .background(Baron.accent100, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(category.name)
                                        .font(Baron.heading(17))
                                        .foregroundStyle(Baron.text)
                                        .lineLimit(1)
                                    // Inflection markup only resolves against the app bundle,
                                    // so these lines are composed here rather than in a model.
                                    HStack(spacing: 4) {
                                        Text("^[\(category.liveTemplates.count) field](inflect: true)")
                                        Text("·")
                                        Text("^[\(thingCount(category)) thing](inflect: true)")
                                    }
                                    .font(Baron.body(12.5))
                                    .foregroundStyle(Baron.neutral600)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text("›")
                                    .font(Baron.body(13, .medium))
                                    .foregroundStyle(Baron.neutral400)
                            }
                            .padding(13)
                            .baronCard()
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                router.focusedCategoryID = category.id
                                router.selectedTab = .assets
                            } label: { Label("Show things", systemImage: "shippingbox") }
                            Button { categoryToDuplicate = category } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                        }
                    }
                }
                .padding(.top, 18)
                Text("Editing a category changes the template only. Existing things stay as they are until you push the change across from the category screen.")
                    .font(Baron.body(12))
                    .foregroundStyle(Baron.neutral500)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
            }
        }
        .navigationDestination(item: $openCategoryID) { id in
            if let category = store.categories[id], !category.isDeleted {
                CategoryEditorView(category: category)
            } else {
                ContentUnavailableView("Category Not Found", systemImage: "folder",
                                       description: Text("This category no longer exists."))
            }
        }
        .sheet(isPresented: $newCategoryPresented) { CategoryNewView() }
        .sheet(item: $categoryToDuplicate) { category in CategoryNewView(duplicating: category) }
    }
}

// MARK: - Pick lists

/// "Combo lists" are called pick lists throughout the redesign — the internal type names are
/// unchanged, only what the user reads.
struct PickListsView: View {
    @Environment(AssetStore.self) private var store

    @State private var newListPresented = false
    @State private var openListID: UUID?

    private var sorted: [ComboListDefinition] {
        store.allComboListDefinitions.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        SetupScreenBody {
            SetupScreenHeader(breadcrumb: "Setup") {
                SetupNewButton { newListPresented = true }
            }
            SetupScreenTitle(
                title: "Pick lists",
                blurb: "One set of choices, reused by any field. Edit a value here and every thing using it follows."
            )
            if sorted.isEmpty {
                Text("Tap + New to create a list of reusable choices.")
                    .font(Baron.body(13))
                    .foregroundStyle(Baron.neutral600)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .baronCard(radius: 16, elevation: .low)
                    .padding(.top, 18)
            } else {
                VStack(spacing: 10) {
                    ForEach(sorted) { list in
                        Button { openListID = list.id } label: {
                            VStack(alignment: .leading, spacing: 11) {
                                HStack(spacing: 10) {
                                    Text(list.name)
                                        .font(Baron.heading(17))
                                        .foregroundStyle(Baron.text)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Group {
                                        if list.systemOptions.isEmpty {
                                            Text("^[\(list.allOptions.count) option](inflect: true)")
                                        } else {
                                            Text("^[\(list.allOptions.count) option](inflect: true) · \(list.systemOptions.count) built in")
                                        }
                                    }
                                    .font(Baron.body(11.5))
                                    .foregroundStyle(Baron.neutral600)
                                    Text("›")
                                        .font(Baron.body(13, .medium))
                                        .foregroundStyle(Baron.neutral400)
                                }
                                if !list.allOptions.isEmpty {
                                    FlowLayout(spacing: 6) {
                                        ForEach(list.allOptions.prefix(4), id: \.self) { option in
                                            Text(option)
                                                .font(Baron.body(11.5, .medium))
                                                .foregroundStyle(Baron.neutral700)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Baron.inset, in: Capsule())
                                        }
                                        if list.allOptions.count > 4 {
                                            Text("+\(list.allOptions.count - 4)")
                                                .font(Baron.body(11.5, .medium))
                                                .foregroundStyle(Baron.neutral500)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                        }
                                    }
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .baronCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 18)
            }
        }
        .navigationDestination(item: $openListID) { id in
            if let list = store.comboListDefinitions[id], !list.isDeleted {
                PickListEditorView(list: list)
            } else {
                ContentUnavailableView("Pick List Not Found", systemImage: "list.bullet.rectangle",
                                       description: Text("This pick list no longer exists."))
            }
        }
        .sheet(isPresented: $newListPresented) { ComboListNewView() }
    }
}

// MARK: - Appearance & language

struct AppearanceView: View {
    @Environment(AssetStore.self) private var store
    @AppStorage(AppPreference.languageKey) private var languageCode: String = ""

    var body: some View {
        @Bindable var store = store
        SetupScreenBody {
            SetupScreenHeader(breadcrumb: "Setup")
            SetupScreenTitle(
                title: "Appearance & language",
                blurb: "The theme tints the paywall and the screens that haven't moved to the new look yet. Light and dark follow the system setting."
            )
            VStack(alignment: .leading, spacing: 10) {
                Text("Theme")
                    .font(Baron.body(10.5, .medium))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(Baron.neutral500)
                HStack(spacing: 7) {
                    ForEach(BackgroundTheme.allCases) { theme in
                        let selected = theme == store.backgroundTheme
                        Button { store.backgroundTheme = theme } label: {
                            Text(theme.displayName)
                                .font(Baron.body(13, .medium))
                                .foregroundStyle(selected ? Color.white : Baron.text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(selected ? Baron.fill : Baron.surface,
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(selected ? Color.clear : Baron.neutral300, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 22)

            VStack(alignment: .leading, spacing: 10) {
                Text("Language")
                    .font(Baron.body(10.5, .medium))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(Baron.neutral500)
                VStack(spacing: 0) {
                    ForEach(Array(AppPreference.supportedLanguages.enumerated()), id: \.element.code) { index, language in
                        Button { languageCode = language.code } label: {
                            VStack(spacing: 0) {
                                HStack {
                                    Text(language.label)
                                        .font(Baron.body(14.5, .medium))
                                        .foregroundStyle(Baron.text)
                                    Spacer(minLength: 0)
                                    if language.code == languageCode {
                                        Image(systemName: "checkmark")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(Baron.accent800)
                                    }
                                }
                                .padding(.horizontal, 15)
                                .padding(.vertical, 13)
                                if index < AppPreference.supportedLanguages.count - 1 {
                                    Baron.line.frame(height: 1).padding(.leading, 15)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .baronCard(elevation: .low)
            }
            .padding(.top, 22)
        }
    }
}

// MARK: - Deleted items

/// One bin with a segmented switch, replacing the three separate Tools rows (Deleted Assets /
/// Categories / Combo Lists). The row lists themselves are the existing `List`-based screens —
/// their swipe-to-restore is the interaction, and rebuilding that in a Baron card would have
/// meant reimplementing swipe actions from scratch for no functional gain.
struct DeletedItemsView: View {
    @Environment(AssetStore.self) private var store

    private enum Bin: String, CaseIterable, Identifiable {
        case things, categories, pickLists
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .things: return "Things"
            case .categories: return "Categories"
            case .pickLists: return "Pick lists"
            }
        }
    }

    @State private var bin: Bin = .things

    private func count(_ bin: Bin) -> Int {
        switch bin {
        case .things: return store.deletedAssets.filter(\.isRoot).count
        case .categories: return store.deletedCategories.count
        case .pickLists: return store.deletedComboListDefinitions.count
        }
    }

    var body: some View {
        ZStack {
            Baron.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                SetupScreenHeader(breadcrumb: "Setup")
                SetupScreenTitle(
                    title: "Deleted items",
                    blurb: "Swipe any row to restore it. Anything still here after \(AppPreference.DaysToRetainDeletedItems) days is removed for good."
                )
                HStack(spacing: 7) {
                    ForEach(Bin.allCases) { option in
                        let selected = option == bin
                        Button { bin = option } label: {
                            HStack(spacing: 5) {
                                Text(option.title)
                                Text("\(count(option))").opacity(0.55)
                            }
                            .font(Baron.heading(11.5))
                            .tracking(0.55)
                            .foregroundStyle(selected ? Color.white : Baron.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(selected ? Baron.fill : Baron.surface,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(selected ? Color.clear : Baron.neutral300, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 18)

                Group {
                    switch bin {
                    case .things: DeletedAssetsView()
                    case .categories: DeletedCategoriesView()
                    case .pickLists: DeletedComboListsView()
                    }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, Baron.pageInset)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
