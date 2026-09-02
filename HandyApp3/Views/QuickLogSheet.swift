import SwiftUI

// MARK: - Quick log

/// Two-step quick-log flow: pick the thing, then the kind. The third step is the existing
/// event/transaction edit sheet.
///
/// Shared by two entry points. The Timeline's "+ Log" starts at `pickThing`, since it has no
/// thing in hand; a Things row's "+" already knows which thing it is and presents
/// `pickKind` directly, skipping step one.
enum QuickLogStep: Identifiable {
    case pickThing
    case pickKind(assetID: UUID)

    var id: String {
        switch self {
        case .pickThing: return "pickThing"
        case .pickKind(let id): return "pickKind-\(id.uuidString)"
        }
    }
}

struct QuickLogSheet: View {
    let step: QuickLogStep
    let assets: [Asset]
    /// Called with the chosen thing and kind once both steps are done.
    let onPickKind: (UUID, Bool) -> Void
    let onPickThing: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var categoryFilter: UUID?

    private var matches: [Asset] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        return assets.filter { asset in
            guard categoryFilter == nil || asset.category.id == categoryFilter else { return false }
            return trimmed.isEmpty || asset.name.lowercased().contains(trimmed)
        }
    }

    /// Built from every asset, not from `matches`, so the counts don't shrink as you type.
    private var chips: [CategoryFilterChip] { CategoryFilterChip.chips(for: assets) }

    var body: some View {
        NavigationStack {
            ZStack {
                Baron.background.ignoresSafeArea()
                switch step {
                case .pickThing: thingPicker
                case .pickKind(let assetID): kindPicker(assetID: assetID)
                }
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case .pickThing: return String(localized: "Log something", bundle: .appPreferred, locale: .appPreferred)
        case .pickKind: return String(localized: "What kind?", bundle: .appPreferred, locale: .appPreferred)
        }
    }

    private var thingPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Step 1 of 2 — which thing is this for?")
                    .font(Baron.body(12.5))
                    .foregroundStyle(Baron.neutral600)
                TextField("Search things", text: $query)
                    .font(Baron.body(14))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .baronCard(radius: Baron.Radius.field, elevation: .low)
                // Only worth showing once there is more than one category to choose between:
                // a single-category library would render "All" beside its one twin.
                if chips.count > 2 {
                    CategoryFilterChips(chips: chips, selection: $categoryFilter)
                }
                if matches.isEmpty {
                    Text("No things match. Clear the search or pick another category.")
                        .font(Baron.body(13))
                        .foregroundStyle(Baron.neutral600)
                        .padding(.top, 4)
                }
                VStack(spacing: 9) {
                    ForEach(matches) { asset in
                        Button { onPickThing(asset.id) } label: {
                            HStack(spacing: 11) {
                                Text(asset.name)
                                    .font(Baron.body(15, .medium))
                                    .foregroundStyle(Baron.text)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.footnote)
                                    .foregroundStyle(Baron.neutral400)
                            }
                            .padding(.horizontal, 13)
                            .padding(.vertical, 14)
                            .baronCard(radius: 16, elevation: .low)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private func kindPicker(assetID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Step 2 of 2 — one-off by default; you can switch on repeats in the next step.")
                .font(Baron.body(12.5))
                .foregroundStyle(Baron.neutral600)
            kindCard(mark: "$", name: "Money", sub: "An expense or income",
                     tint: Baron.accent100, markColor: Baron.accent800) { onPickKind(assetID, false) }
            kindCard(mark: "◷", name: "Event", sub: "Something you did, or plan to do",
                     tint: Baron.neutral200, markColor: Baron.neutral700) { onPickKind(assetID, true) }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func kindCard(mark: String, name: String, sub: String, tint: Color, markColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(mark)
                    .font(Baron.heading(14))
                    .foregroundStyle(markColor)
                    .frame(width: 40, height: 40)
                    .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(Baron.heading(17)).foregroundStyle(Baron.text)
                    Text(sub).font(Baron.body(12.5)).foregroundStyle(Baron.neutral600)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(Baron.neutral400)
            }
            .padding(15)
            .baronCard(elevation: .low)
        }
        .buttonStyle(.plain)
    }
}

