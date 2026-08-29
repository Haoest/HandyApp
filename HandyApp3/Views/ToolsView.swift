import SwiftUI
import Contacts
import UniformTypeIdentifiers

// MARK: - JSON export document

/// Wraps the store's JSON export for `fileExporter`. Internal so Setup can present it.
struct JSONExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let d = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = d
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Tools tab

struct ToolsTab: View {
    @Environment(AssetStore.self) private var store
    @Environment(PurchaseManager.self) private var purchases
    @Environment(AppRouter.self) private var router
    @State private var showingExporter = false
    @State private var exportDocument: JSONExportDocument?
    @State private var showingImportConfirm = false
    @State private var showingImporter = false
    @State private var showingImportDone = false
    @State private var importError: String?
    @State private var showingResetAlert = false
    @State private var resetConfirmText = ""
    @State private var showingResetDone = false
    @State private var isRestoringPurchases = false
    @State private var restoreResultMessage: String?
    @AppStorage(AppPreference.languageKey)
    private var languageCode: String = ""

    private var exportFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "BaronBook-\(formatter.string(from: Date()))"
    }

    private func runExport() {
        if let data = store.exportJSON() {
            exportDocument = JSONExportDocument(data: data)
            showingExporter = true
        }
    }

    /// Coarse, read-only sync status — no live probing, just what the store already knows.
    private var iCloudStatusText: String {
        guard AssetStore.iCloudSyncEnabled else { return "Not enabled" }
        guard FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil else { return "iCloud unavailable" }
        if store.storeRequiresNewerApp { return "App update required" }
        if store.savesSuspended { return "Waiting for iCloud…" }
        guard let lastSync = store.lastSyncDate else { return "On" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Synced \(formatter.localizedString(for: lastSync, relativeTo: Date()))"
    }

    var body: some View {
        @Bindable var store = store
        return NavigationStack {
            ZStack {
                AppBackground()
                List {
                    Section("Help") {
                        NavigationLink(destination: QuickStartGuideView()) {
                            Label("Quick Start Guide", systemImage: "questionmark.circle")
                        }
                        .listRowBackground(Color.white.opacity(0.5))
                    }

                    Section("Data") {
                        Button {
                            runExport()
                        } label: {
                            Label("Export Data", systemImage: "square.and.arrow.up")
                        }
                        .listRowBackground(Color.white.opacity(0.5))
                        Button {
                            showingImportConfirm = true
                        } label: {
                            Label("Import Data", systemImage: "square.and.arrow.down")
                        }
                        .listRowBackground(Color.white.opacity(0.5))
                        NavigationLink(destination: DeletedAssetsView()) {
                            Label("Deleted Assets", systemImage: "trash.slash")
                        }
                        .listRowBackground(Color.white.opacity(0.5))
                        NavigationLink(destination: DeletedCategoriesView()) {
                            Label("Deleted Categories", systemImage: "folder.badge.minus")
                        }
                        .listRowBackground(Color.white.opacity(0.5))
                        NavigationLink(destination: DeletedComboListsView()) {
                            Label("Deleted Combo Lists", systemImage: "list.bullet.rectangle")
                        }
                        .listRowBackground(Color.white.opacity(0.5))
                    }

                    Section("Communication") {
                        NavigationLink(destination: BulkCommunicationView()) {
                            Label("Bulk Communication", systemImage: "bubble.left.and.bubble.right")
                        }
                        .listRowBackground(Color.white.opacity(0.5))
                    }

                    Section("Preference") {
                        Picker("Background", selection: $store.backgroundTheme) {
                            ForEach(BackgroundTheme.allCases) { theme in
                                Text(theme.displayName).tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.white.opacity(0.5))
                        Picker("Language", selection: $languageCode) {
                            ForEach(AppPreference.supportedLanguages, id: \.code) { lang in
                                Text(lang.label).tag(lang.code)
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.5))
                    }

                    Section("System") {
                        LabeledContent("iCloud Sync", value: iCloudStatusText)
                            .listRowBackground(Color.white.opacity(0.5))
                        Button {
                            restorePurchases()
                        } label: {
                            if isRestoringPurchases {
                                HStack {
                                    Label("Restore Purchases", systemImage: "arrow.clockwise")
                                    Spacer()
                                    ProgressView()
                                }
                            } else {
                                Label("Restore Purchases", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(isRestoringPurchases)
                        .listRowBackground(Color.white.opacity(0.5))
                        Button(role: .destructive) {
                            resetConfirmText = ""
                            showingResetAlert = true
                        } label: {
                            Label("Factory Reset", systemImage: "exclamationmark.triangle")
                        }
                        .listRowBackground(Color.white.opacity(0.5))
                    }
                }
                .scrollContentBackground(.hidden)
                .environment(\.colorScheme, .light)
            }
            .navigationTitle("Tools")
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .onChange(of: router.pendingToolsAction, initial: true) { _, action in
                if action == .export {
                    router.pendingToolsAction = nil
                    runExport()
                }
            }
            .alert("Factory Reset", isPresented: $showingResetAlert) {
                TextField("Type \"reset\" to confirm", text: $resetConfirmText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Reset", role: .destructive) {
                    if resetConfirmText.lowercased() == "reset" {
                        store.factoryReset()
                        showingResetDone = true
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all data on this device and in iCloud. Consider exporting your data first. Type \"reset\" to confirm.")
            }
            .alert("Reset Complete", isPresented: $showingResetDone) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("All data has been cleared and the app has been restored to its initial state.")
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: exportFilename
            ) { _ in }
            .alert("Import Data", isPresented: $showingImportConfirm) {
                Button("Choose File") { showingImporter = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Data from the file you choose will be merged into what's already on this device. Nothing is deleted or overwritten — categories, assets, properties, events, transactions and photos that already exist are left as they are, and anything new is added.")
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        try store.importJSON(data: data)
                        showingImportDone = true
                    } catch {
                        importError = error.localizedDescription
                    }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .alert("Import Complete", isPresented: $showingImportDone) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The imported file has been merged into your data. Existing records were left unchanged; anything new was added.")
            }
            .alert("Import Failed", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .alert("Restore Purchases", isPresented: Binding(
                get: { restoreResultMessage != nil },
                set: { if !$0 { restoreResultMessage = nil } }
            )) {
                Button("OK", role: .cancel) { restoreResultMessage = nil }
            } message: {
                Text(restoreResultMessage ?? "")
            }
        }
    }

    private func restorePurchases() {
        isRestoringPurchases = true
        Task {
            await purchases.restore()
            isRestoringPurchases = false
            restoreResultMessage = purchases.isFullVersion
                ? "Full Version restored."
                : "No previous purchase was found for this Apple ID."
        }
    }
}

// MARK: - Deleted assets

struct DeletedAssetsView: View {
    @Environment(AssetStore.self) private var store
    @State private var paywallPresented = false

    // Only the roots of deleted families — descendants stay linked internally and are excluded.
    private var sorted: [Asset] {
        store.deletedAssets
            .filter { $0.isRoot }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if sorted.isEmpty {
                ContentUnavailableView("No Deleted Assets", systemImage: "trash.slash")
            } else {
                List {
                    ForEach(sorted) { asset in
                        DeletedAssetRow(asset: asset, paywallPresented: $paywallPresented)
                    }
                    Section {
                        Text("Swipe on any row for actions")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .navigationTitle("Deleted Assets")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $paywallPresented) { PaywallView() }
    }
}

private struct DeletedAssetRow: View {
    @Environment(AssetStore.self) private var store
    let asset: Asset
    @Binding var paywallPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(asset.name)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            if asset.isProtectedFromAutoPurge {
                Label("Edited after deletion — won't be auto-purged", systemImage: "shield")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                try? store.hardDeleteAsset(id: asset.id)
            } label: {
                Label("Delete now", systemImage: "trash")
            }
            Button {
                let subtreeCount = 1 + asset.descendants.count
                guard store.hasCapacity(forAdditional: subtreeCount) else {
                    paywallPresented = true
                    return
                }
                try? store.restoreAsset(id: asset.id)
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.green)
        }
    }

    private var subtitle: LocalizedStringKey {
        // A protected asset won't age out on its own — "Purge in N days" would be misleading
        // (implying an eventual auto-purge that the gate is specifically refusing to do).
        guard !asset.isProtectedFromAutoPurge else { return "Kept until restored or deleted" }
        let elapsed = Calendar.current.dateComponents(
            [.day], from: asset.deletedAt ?? Date(), to: Date()
        ).day ?? 0
        let remaining = max(0, AppPreference.DaysToRetainDeletedItems - elapsed)
        return "Purge in ^[\(remaining) day](inflect: true)"
    }
}

// MARK: - Deleted categories

struct DeletedCategoriesView: View {
    @Environment(AssetStore.self) private var store

    private var sorted: [AssetCategory] {
        store.deletedCategories.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if sorted.isEmpty {
                ContentUnavailableView("No Deleted Categories", systemImage: "folder.badge.minus")
            } else {
                List {
                    ForEach(sorted) { cat in
                        DeletedCategoryRow(category: cat)
                    }
                    Section {
                        Text("Swipe on any row for actions")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .navigationTitle("Deleted Categories")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DeletedCategoryRow: View {
    @Environment(AssetStore.self) private var store
    let category: AssetCategory

    var body: some View {
        let count = store.associatedAssetCount(categoryID: category.id)
        VStack(alignment: .leading, spacing: 2) {
            Label(category.name, systemImage: category.iconName)
            Text(subtitle(count: count))
                .font(.caption)
                .foregroundStyle(.secondary)
            if count == 0 && category.isProtectedFromAutoPurge {
                Label("Edited after deletion — won't be auto-purged", systemImage: "shield")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .swipeActions(edge: .trailing) {
            if count == 0 {
                Button(role: .destructive) {
                    try? store.hardDeleteCategory(id: category.id)
                } label: {
                    Label("Delete now", systemImage: "trash")
                }
            }
            Button {
                try? store.restoreCategory(id: category.id)
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.green)
        }
    }

    private func subtitle(count: Int) -> LocalizedStringKey {
        if count > 0 {
            return "Associated with ^[\(count) asset](inflect: true)"
        }
        // A protected category won't age out on its own — "Purge in N days" would be
        // misleading (implying an eventual auto-purge that the gate is specifically refusing).
        guard !category.isProtectedFromAutoPurge else { return "Kept until restored or deleted" }
        let elapsed = Calendar.current.dateComponents(
            [.day], from: category.deletedAt ?? Date(), to: Date()
        ).day ?? 0
        let remaining = max(0, AppPreference.DaysToRetainDeletedItems - elapsed)
        return "Purge in ^[\(remaining) day](inflect: true)"
    }
}

// MARK: - Deleted combo lists

struct DeletedComboListsView: View {
    @Environment(AssetStore.self) private var store

    private var sorted: [ComboListDefinition] {
        store.deletedComboListDefinitions.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if sorted.isEmpty {
                ContentUnavailableView("No Deleted Combo Lists", systemImage: "list.bullet.rectangle")
            } else {
                List {
                    ForEach(sorted) { list in
                        DeletedComboListRow(list: list)
                    }
                    Section {
                        Text("Swipe on any row for actions")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .navigationTitle("Deleted Combo Lists")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DeletedComboListRow: View {
    @Environment(AssetStore.self) private var store
    let list: ComboListDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(list.name)
            Text("Kept until restored — ^[\(list.allOptions.count) option](inflect: true)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        // No "Delete now": a combo list has no sync-safe hard-delete path (unlike assets/
        // categories) — removing it from the store outright resurrects on the next sync and
        // silently drops any property still typed on it. Restore only.
        .swipeActions(edge: .trailing) {
            Button {
                try? store.restoreComboList(id: list.id)
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.green)
        }
    }
}

// MARK: - Bulk communication

private struct ContactRow: Identifiable {
    let id: UUID
    let asset: Asset
    let propertyName: String
    let contact: CNContact
    let availableMethods: [ContactMethod]
}

private enum ContactMethod: String, CaseIterable, Identifiable {
    case sms, email, whatsapp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sms: return "SMS"
        case .email: return "Email"
        case .whatsapp: return "WhatsApp"
        }
    }
}

struct BulkCommunicationView: View {
    @Environment(AssetStore.self) private var store

    @State private var rows: [ContactRow] = []
    @State private var isLoading = true
    @State private var messageText = ""
    @State private var selectedMethods: [UUID: ContactMethod] = [:]

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespaces).isEmpty && !selectedMethods.isEmpty
    }

    var body: some View {
        Form {
            Section("Message") {
                TextField("Type a message…", text: $messageText, axis: .vertical)
                    .lineLimit(3...6)
            }

            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if rows.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Contacts Found",
                        systemImage: "person.slash",
                        description: Text("No top-level assets have a linked contact.")
                    )
                }
            } else {
                let grouped = Dictionary(grouping: rows) { $0.asset.id }
                let assets = rows.map(\.asset).uniqued()
                ForEach(assets) { asset in
                    Section(asset.name) {
                        ForEach(grouped[asset.id] ?? []) { row in
                            contactRowView(row)
                        }
                    }
                }
            }
        }
        .navigationTitle("Bulk Communication")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Send All") { sendAll() }
                    .disabled(!canSend)
            }
        }
        .task {
            await loadContacts()
        }
    }

    @ViewBuilder
    private func contactRowView(_ row: ContactRow) -> some View {
        let name = ContactResolver.shared.displayName(for: row.contact.identifier) ?? row.contact.identifier
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                    Text(row.propertyName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Picker("", selection: methodBinding(for: row.id, methods: row.availableMethods)) {
                Text("None").tag(Optional<ContactMethod>.none)
                ForEach(row.availableMethods) { method in
                    Text(method.label).tag(Optional(method))
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 2)
    }

    private func methodBinding(for id: UUID, methods: [ContactMethod]) -> Binding<ContactMethod?> {
        Binding(
            get: { selectedMethods[id] },
            set: { selectedMethods[id] = $0 }
        )
    }

    private func loadContacts() async {
        var built: [ContactRow] = []
        let rootAssets = store.allAssets.filter(\.isRoot).sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        for asset in rootAssets {
            for prop in asset.liveBaseProperties + asset.liveCustomProperties {
                guard case .basic(.contact) = prop.definition.type,
                      case .contact(let identifier) = prop.value,
                      let contact = try? ContactResolver.shared.contact(for: identifier)
                else { continue }
                let methods = availableMethods(for: contact)
                guard !methods.isEmpty else { continue }
                built.append(ContactRow(
                    id: UUID(),
                    asset: asset,
                    propertyName: prop.definition.name,
                    contact: contact,
                    availableMethods: methods
                ))
            }
        }
        rows = built
        isLoading = false
    }

    private func availableMethods(for contact: CNContact) -> [ContactMethod] {
        var methods: [ContactMethod] = []
        if !contact.phoneNumbers.isEmpty { methods.append(.sms) }
        if !contact.emailAddresses.isEmpty { methods.append(.email) }
        let hasWhatsApp = contact.instantMessageAddresses.contains {
            $0.value.service.lowercased() == "whatsapp"
        }
        if hasWhatsApp && !contact.phoneNumbers.isEmpty { methods.append(.whatsapp) }
        return methods
    }

    private func sendAll() {
        let encoded = messageText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        for row in rows {
            guard let method = selectedMethods[row.id] else { continue }
            let urlString: String
            switch method {
            case .sms:
                let phone = row.contact.phoneNumbers.first?.value.stringValue ?? ""
                let clean = phone.filter { $0.isNumber || $0 == "+" }
                urlString = "sms:\(clean)?&body=\(encoded)"
            case .email:
                let email = row.contact.emailAddresses.first.map { $0.value as String } ?? ""
                urlString = "mailto:\(email)?body=\(encoded)"
            case .whatsapp:
                let phone = row.contact.phoneNumbers.first?.value.stringValue ?? ""
                let clean = phone.filter { $0.isNumber || $0 == "+" }
                urlString = "whatsapp://send?phone=\(clean)&text=\(encoded)"
            }
            guard let url = URL(string: urlString) else { continue }
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Quick start guide

private struct SiriCommand: Identifiable {
    let id = UUID()
    let phrases: [String]
    let description: String
}

struct QuickStartGuideView: View {
    private let commands: [SiriCommand] = [
        SiriCommand(
            phrases: [
                "\"Open asset [name] in Baron Book\"",
                "\"Show [name] in Baron Book\"",
                "\"Open an asset in Baron Book\""
            ],
            description: "Jump straight to an asset's detail screen."
        ),
        SiriCommand(
            phrases: [
                "\"Add asset in Baron Book\"",
                "\"Create new asset in Baron Book\""
            ],
            description: "Start creating a new asset."
        ),
        SiriCommand(
            phrases: [
                "\"Add new named asset in Baron Book\"",
                "\"Create new named asset in Baron Book\""
            ],
            description: "Start creating a new asset with the name you say."
        ),
        SiriCommand(
            phrases: [
                "\"Add transaction to [asset] in Baron Book\"",
                "\"Record transaction to [asset] in Baron Book\""
            ],
            description: "Start recording a transaction for an asset."
        ),
        SiriCommand(
            phrases: [
                "\"Add expense to [asset] in Baron Book\"",
                "\"Record expense to [asset] in Baron Book\""
            ],
            description: "Start recording an expense for an asset."
        ),
        SiriCommand(
            phrases: [
                "\"Add income to [asset] in Baron Book\"",
                "\"Record income to [asset] in Baron Book\""
            ],
            description: "Start recording income for an asset."
        )
    ]

    var body: some View {
        List {
            Section {
                Text("You can use these Siri commands anywhere on your device — just say \"Hey Siri\" followed by one of the phrases below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Siri Commands") {
                ForEach(commands) { command in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(command.phrases, id: \.self) { phrase in
                            Text(phrase)
                                .font(.body.weight(.medium))
                        }
                        Text(command.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Quick Start Guide")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Helpers

private extension Array where Element: Identifiable {
    func uniqued() -> [Element] {
        var seen = Set<Element.ID>()
        return filter { seen.insert($0.id).inserted }
    }
}
