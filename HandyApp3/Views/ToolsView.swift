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
