import SwiftUI
import Contacts
import UniformTypeIdentifiers

// MARK: - JSON export document

private struct JSONExportDocument: FileDocument {
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
    @State private var showingExporter = false
    @State private var exportDocument: JSONExportDocument?
    @State private var showingImportConfirm = false
    @State private var importConfirmText = ""
    @State private var showingImporter = false
    @State private var showingImportDone = false
    @State private var importError: String?
    @State private var showingResetAlert = false
    @State private var resetConfirmText = ""
    @State private var showingResetDone = false
    @State private var isRestoringPurchases = false
    @State private var restoreResultMessage: String?

    private var exportFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "Geeloo-\(formatter.string(from: Date()))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                List {
                    Button {
                        if let data = store.exportJSON() {
                            exportDocument = JSONExportDocument(data: data)
                            showingExporter = true
                        }
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }
                    .listRowBackground(Color.white.opacity(0.5))
                    Button {
                        importConfirmText = ""
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
                    NavigationLink(destination: BulkCommunicationView()) {
                        Label("Bulk Communication", systemImage: "bubble.left.and.bubble.right")
                    }
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
                .scrollContentBackground(.hidden)
                .environment(\.colorScheme, .light)
            }
            .navigationTitle("Tools")
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
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
                TextField("Type \"import\" to confirm", text: $importConfirmText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Import", role: .destructive) {
                    if importConfirmText.lowercased() == "import" {
                        showingImporter = true
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All existing data on this device will be permanently deleted and replaced with the contents of the imported file. Type \"import\" to continue.")
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
                Text("Your data has been replaced with the imported file.")
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

    private var sorted: [Asset] {
        store.deletedAssets.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if sorted.isEmpty {
                ContentUnavailableView("No Deleted Assets", systemImage: "trash.slash")
            } else {
                List(sorted) { asset in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.name)
                        Text(asset.category.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            guard store.hasAssetCapacity else { paywallPresented = true; return }
                            try? store.restoreAsset(id: asset.id)
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.green)
                    }
                }
            }
        }
        .navigationTitle("Deleted Assets")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $paywallPresented) { PaywallView() }
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
                List(sorted) { cat in
                    Label(cat.name, systemImage: cat.iconName)
                        .swipeActions(edge: .leading) {
                            Button {
                                try? store.restoreCategory(id: cat.id)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.green)
                        }
                }
            }
        }
        .navigationTitle("Deleted Categories")
        .navigationBarTitleDisplayMode(.inline)
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
            for prop in asset.baseProperties + asset.customProperties {
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

// MARK: - Helpers

private extension Array where Element: Identifiable {
    func uniqued() -> [Element] {
        var seen = Set<Element.ID>()
        return filter { seen.insert($0.id).inserted }
    }
}
