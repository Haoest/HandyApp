import SwiftUI

struct ReportTab: View {
    @Environment(AssetStore.self) private var store

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var direction: ReportDirection = .all
    @State private var includesAllThings = true
    @State private var selectedThingIDs: Set<UUID> = []
    @State private var thingPickerPresented = false

    init(calendar: Calendar = .current, now: Date = Date()) {
        let interval = calendar.dateInterval(of: .year, for: now)
        let start = interval?.start ?? calendar.startOfDay(for: now)
        let end = interval.flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) }
            ?? calendar.startOfDay(for: now)
        _startDate = State(initialValue: start)
        _endDate = State(initialValue: end)
    }

    private var assets: [Asset] {
        store.allAssets.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var sources: [ReportSource] {
        assets.map { ReportSource(thingID: $0.id, thingName: $0.name, transactions: $0.liveTransactions) }
    }

    private var result: ReportResult {
        ReportDigest.build(
            sources: sources,
            startDate: startDate,
            endDate: endDate,
            selectedThingIDs: includesAllThings ? nil : selectedThingIDs,
            direction: direction
        )
    }

    private var liveThingIDs: Set<UUID> { Set(assets.map(\.id)) }

    var body: some View {
        NavigationStack {
            ZStack {
                Baron.background.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        header
                        filters
                        totals
                        results
                    }
                    .padding(.horizontal, Baron.pageInset)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $thingPickerPresented) {
                ReportThingPickerSheet(
                    assets: assets,
                    includesAllThings: $includesAllThings,
                    selectedThingIDs: $selectedThingIDs
                )
            }
            .onChange(of: startDate) { _, newValue in
                if newValue > endDate { endDate = newValue }
            }
            .onChange(of: endDate) { _, newValue in
                if newValue < startDate { startDate = newValue }
            }
            .onChange(of: liveThingIDs) { _, ids in
                selectedThingIDs.formIntersection(ids)
            }
        }
    }

    private var header: some View {
        Text("Report")
            .font(Baron.heading(32))
            .foregroundStyle(Baron.text)
            .padding(.top, 12)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Date range")
                .font(Baron.heading(13))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Baron.neutral700)

            HStack(spacing: 10) {
                dateField("From", selection: $startDate)
                dateField("To", selection: $endDate)
            }

            Button { thingPickerPresented = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(Baron.accent800)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Things")
                            .font(Baron.body(11.5, .medium))
                            .foregroundStyle(Baron.neutral600)
                        Text(thingSelectionLabel)
                            .font(Baron.body(14.5, .medium))
                            .foregroundStyle(Baron.text)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(Baron.neutral400)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(Baron.inset, in: RoundedRectangle(cornerRadius: Baron.Radius.control, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(spacing: 7) {
                directionButton("All", value: .all)
                directionButton("Money in", value: .income)
                directionButton("Money out", value: .expense)
            }
        }
        .padding(15)
        .baronCard(elevation: .low)
    }

    private func dateField(_ title: LocalizedStringKey, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Baron.body(11.5, .medium))
                .foregroundStyle(Baron.neutral600)
            DatePicker("", selection: selection, displayedComponents: .date)
                .labelsHidden()
                .font(Baron.body(13))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Baron.inset, in: RoundedRectangle(cornerRadius: Baron.Radius.control, style: .continuous))
    }

    private func directionButton(_ title: LocalizedStringKey, value: ReportDirection) -> some View {
        let selected = direction == value
        return Button { direction = value } label: {
            Text(title)
                .font(Baron.body(12.5, .medium))
                .foregroundStyle(selected ? Color.white : Baron.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(selected ? Baron.fill : Baron.inset,
                            in: RoundedRectangle(cornerRadius: Baron.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var thingSelectionLabel: String {
        if includesAllThings {
            return String(localized: "All Things", bundle: .appPreferred, locale: .appPreferred)
        }
        if selectedThingIDs.isEmpty {
            return String(localized: "No Things selected", bundle: .appPreferred, locale: .appPreferred)
        }
        return String.localizedStringWithFormat(
            String(localized: "%lld Things selected", bundle: .appPreferred, locale: .appPreferred),
            selectedThingIDs.count
        )
    }

    private var totals: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 9) {
                totalCard("Money in", amount: result.moneyIn, color: Baron.good)
                totalCard("Money out", amount: result.moneyOut, color: Baron.danger)
                totalCard("Grand total", amount: result.grandTotal,
                          color: result.grandTotal < 0 ? Baron.danger : Baron.text)
            }
            Text("Money in − Money out")
                .font(Baron.body(11.5))
                .foregroundStyle(Baron.neutral600)
        }
    }

    private func totalCard(_ title: LocalizedStringKey, amount: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Baron.heading(11))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Baron.neutral600)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(Self.money(amount))
                .font(Baron.heading(19))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(12)
        .baronCard(elevation: .low)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var results: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Transactions")
                    .font(Baron.heading(19))
                    .foregroundStyle(Baron.text)
                Spacer(minLength: 0)
                Text(result.entries.count, format: .number)
                    .font(Baron.body(12.5))
                    .foregroundStyle(Baron.neutral600)
            }

            if result.entries.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 27, weight: .light))
                        .foregroundStyle(Baron.neutral500)
                    Text("No transactions found")
                        .font(Baron.heading(18))
                        .foregroundStyle(Baron.text)
                    Text("Try changing the date range, Things, or money direction.")
                        .font(Baron.body(13))
                        .foregroundStyle(Baron.neutral600)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 34)
                .baronCard(elevation: .low)
            } else {
                LazyVStack(spacing: 9) {
                    ForEach(result.entries) { entry in
                        reportRow(entry)
                    }
                }
            }
        }
    }

    private func reportRow(_ entry: ReportEntry) -> some View {
        HStack(spacing: 11) {
            Image(systemName: entry.kind == .income ? "arrow.down.left" : "arrow.up.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(entry.kind == .income ? Baron.good : Baron.danger)
                .frame(width: 34, height: 34)
                .background(entry.kind == .income ? Baron.goodBackground : Baron.dangerBackground,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.details)
                    .font(Baron.body(14.5, .medium))
                    .foregroundStyle(Baron.text)
                    .lineLimit(1)
                Text("\(entry.thingName) · \(Self.rowDateFormatter.string(from: entry.date))")
                    .font(Baron.body(12))
                    .foregroundStyle(Baron.neutral600)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(Self.signedMoney(entry.signedAmount))
                .font(Baron.body(14, .semibold))
                .foregroundStyle(entry.kind == .income ? Baron.good : Baron.danger)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .baronCard(radius: Baron.Radius.field, elevation: .low)
    }

    private static func money(_ amount: Decimal) -> String {
        let code = Locale.current.currency?.identifier ?? "USD"
        return amount.formatted(.currency(code: code).precision(.fractionLength(0...2)))
    }

    private static func signedMoney(_ amount: Decimal) -> String {
        let magnitude = money(abs(amount))
        return amount < 0 ? "−\(magnitude)" : "+\(magnitude)"
    }

    private static let rowDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .appPreferred
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct ReportThingPickerSheet: View {
    let assets: [Asset]
    @Binding var includesAllThings: Bool
    @Binding var selectedThingIDs: Set<UUID>

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var categoryFilter: UUID?

    private var chips: [CategoryFilterChip] { CategoryFilterChip.chips(for: assets) }

    private var matches: [Asset] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return assets.filter { asset in
            guard categoryFilter == nil || asset.category.id == categoryFilter else { return false }
            guard !needle.isEmpty else { return true }
            let category = BuiltInTypes.localizedSeedName(id: asset.category.id, currentName: asset.category.name)
            let ancestors = asset.ancestors.map(\.name).joined(separator: " ")
            return asset.name.lowercased().contains(needle)
                || category.lowercased().contains(needle)
                || ancestors.lowercased().contains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Baron.background.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        searchField
                        CategoryFilterChips(chips: chips, selection: $categoryFilter)
                        allThingsRow
                        if matches.isEmpty {
                            Text("No things match. Clear the search or pick another category.")
                                .font(Baron.body(13))
                                .foregroundStyle(Baron.neutral600)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 28)
                        } else {
                            ForEach(matches) { asset in thingRow(asset) }
                        }
                    }
                    .padding(.horizontal, Baron.pageInset)
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("Select Things")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        includesAllThings = false
                        selectedThingIDs.removeAll()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.footnote)
                .foregroundStyle(Baron.neutral500)
            TextField("Search things", text: $query)
                .font(Baron.body(14))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Baron.neutral400)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .baronCard(radius: Baron.Radius.field, elevation: .low)
    }

    private var allThingsRow: some View {
        Button {
            includesAllThings = true
            selectedThingIDs.removeAll()
        } label: {
            selectionRow(title: String(localized: "All Things", bundle: .appPreferred, locale: .appPreferred),
                         subtitle: String(localized: "Include every Thing", bundle: .appPreferred, locale: .appPreferred),
                         selected: includesAllThings)
        }
        .buttonStyle(.plain)
    }

    private func thingRow(_ asset: Asset) -> some View {
        let selected = !includesAllThings && selectedThingIDs.contains(asset.id)
        return Button {
            if includesAllThings {
                includesAllThings = false
                selectedThingIDs = [asset.id]
            } else if selected {
                selectedThingIDs.remove(asset.id)
            } else {
                selectedThingIDs.insert(asset.id)
            }
        } label: {
            selectionRow(title: asset.name, subtitle: context(for: asset), selected: selected)
        }
        .buttonStyle(.plain)
    }

    private func selectionRow(title: String, subtitle: String, selected: Bool) -> some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Baron.body(14.5, .medium))
                    .foregroundStyle(Baron.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Baron.body(12))
                    .foregroundStyle(Baron.neutral600)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(selected ? Baron.accent800 : Baron.neutral400)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .baronCard(radius: Baron.Radius.field, elevation: .low)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func context(for asset: Asset) -> String {
        let category = BuiltInTypes.localizedSeedName(id: asset.category.id, currentName: asset.category.name)
        let path = asset.ancestors.map(\.name).joined(separator: " / ")
        return path.isEmpty ? category : "\(category) · \(path)"
    }
}
