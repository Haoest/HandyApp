import SwiftUI
import UniformTypeIdentifiers

/// Setup — the redesign's third and last tab. Merges the old Categories and Tools tabs, which
/// the design treats as one place: templates, app preferences, data, extras, and a fenced-off
/// "Careful" group. The original audit's complaint about Tools was that a cosmetic theme picker
/// and an irreversible factory reset were styled identically; grouping them apart is the answer.
struct SetupTab: View {
    @Environment(AssetStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(PurchaseManager.self) private var purchases

    @State private var path = NavigationPath()

    @State private var paywallPresented = false
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

    @AppStorage(AppPreference.languageKey) private var languageCode: String = ""

    private var plan: PlanSummary {
        SetupDigest.plan(
            isFullVersion: purchases.isFullVersion,
            assetCount: store.allAssets.count,
            assetLimit: PurchaseManager.freeAssetLimit,
            eventLimit: PurchaseManager.freeEventLimit,
            transactionLimit: PurchaseManager.freeTransactionLimit
        )
    }

    private var binCount: Int {
        store.deletedAssets.filter(\.isRoot).count
            + store.deletedCategories.count
            + store.deletedComboListDefinitions.count
    }

    /// Coarse, read-only sync status — no live probing, just what the store already knows.
    private var iCloudStatusText: String {
        guard AssetStore.iCloudSyncEnabled else { return String(localized: "Not enabled") }
        guard FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil else {
            return String(localized: "iCloud unavailable")
        }
        if store.storeRequiresNewerApp { return String(localized: "App update required") }
        if store.savesSuspended { return String(localized: "Waiting for iCloud…") }
        guard let lastSync = store.lastSyncDate else { return String(localized: "On") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return String(localized: "Synced \(formatter.localizedString(for: lastSync, relativeTo: Date()))")
    }

    private var languageLabel: String {
        AppPreference.supportedLanguages.first { $0.code == languageCode }?.label
            ?? AppPreference.supportedLanguages[0].label
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Baron.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Setup")
                            .font(Baron.heading(32))
                            .foregroundStyle(Baron.text)
                            .padding(.top, 12)
                        Text(iCloudStatusText)
                            .font(Baron.body(13))
                            .foregroundStyle(Baron.neutral600)
                            .padding(.top, 7)
                        planCard.padding(.top, 18)
                        templatesGroup
                        appGroup
                        dataGroup
                        extrasGroup
                        carefulGroup
                        versionLine
                    }
                    .padding(.horizontal, Baron.pageInset)
                    .padding(.bottom, 28)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SetupDestination.self) { destination in
                switch destination {
                case .categories: CategoriesListView()
                case .pickLists: PickListsView()
                case .appearance: AppearanceView()
                case .deletedItems: DeletedItemsView()
                case .quickStart: QuickStartGuideView()
                case .bulkMessage: BulkCommunicationView()
                }
            }
            .modifier(SetupDataActions(
                showingExporter: $showingExporter,
                exportDocument: $exportDocument,
                showingImportConfirm: $showingImportConfirm,
                showingImporter: $showingImporter,
                showingImportDone: $showingImportDone,
                importError: $importError,
                showingResetAlert: $showingResetAlert,
                resetConfirmText: $resetConfirmText,
                showingResetDone: $showingResetDone,
                restoreResultMessage: $restoreResultMessage
            ))
            .sheet(isPresented: $paywallPresented) { PaywallView() }
            .onChange(of: router.pendingToolsAction, initial: true) { _, action in
                if action == .export {
                    router.pendingToolsAction = nil
                    runExport()
                }
            }
        }
    }

    // MARK: - Plan card

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(plan.kicker)
                .font(Baron.body(10.5, .medium))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.7))
            Text(plan.title)
                .font(Baron.heading(23))
                .foregroundStyle(.white)
                .padding(.top, 9)
            Text(plan.body)
                .font(Baron.body(13))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)
            Button {
                if plan.offersUpgrade { paywallPresented = true } else { restorePurchases() }
            } label: {
                HStack(spacing: 8) {
                    Text(plan.callToAction)
                    if isRestoringPurchases { ProgressView().controlSize(.mini) }
                }
                .font(Baron.heading(12))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundStyle(Baron.accent900)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Baron.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isRestoringPurchases)
            .padding(.top, 14)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Baron.accent900, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Groups

    private var templatesGroup: some View {
        SetupGroup("Templates") {
            SetupRow(name: "Categories", sub: "Fields and icon copied into each new thing",
                     value: "\(store.allCategories.count)") { path.append(SetupDestination.categories) }
            SetupRow(name: "Pick lists", sub: "Reusable choices like fuel type",
                     value: "\(store.allComboListDefinitions.count)", isLast: true) {
                path.append(SetupDestination.pickLists)
            }
        }
    }

    private var appGroup: some View {
        SetupGroup("App") {
            SetupRow(name: "Language", sub: languageLabel, value: "") {
                path.append(SetupDestination.appearance)
            }
            SetupRow(name: "Quick start guide", sub: "What you can say to Siri",
                     value: "", isLast: true) { path.append(SetupDestination.quickStart) }
        }
    }

    private var dataGroup: some View {
        SetupGroup("Data") {
            SetupRow(name: "Export", sub: "One JSON file, everything in it", value: "", caret: "") {
                runExport()
            }
            SetupRow(name: "Import", sub: "Merges into the current library", value: "", caret: "") {
                showingImportConfirm = true
            }
            SetupRow(name: "Deleted items",
                     sub: "Restore anything deleted in the last \(AppPreference.DaysToRetainDeletedItems) days",
                     value: "\(binCount)", isLast: true) { path.append(SetupDestination.deletedItems) }
        }
    }

    private var extrasGroup: some View {
        SetupGroup("Extras") {
            SetupRow(name: "Bulk message", sub: "One message to every linked contact",
                     value: "", isLast: true) { path.append(SetupDestination.bulkMessage) }
        }
    }

    private var carefulGroup: some View {
        SetupGroup("Careful") {
            SetupRow(name: "Factory reset", sub: "Erases this device and iCloud",
                     value: "", caret: "!", tint: Baron.danger, isLast: true) {
                resetConfirmText = ""
                showingResetAlert = true
            }
        }
    }

    private var versionLine: some View {
        Text("Baron Book \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · \(purchases.isFullVersion ? String(localized: "Full version") : String(localized: "Free tier"))")
            .font(Baron.body(11))
            .foregroundStyle(Baron.neutral500)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
    }

    // MARK: - Actions

    private func runExport() {
        guard let data = store.exportJSON() else { return }
        exportDocument = JSONExportDocument(data: data)
        showingExporter = true
    }

    private func restorePurchases() {
        isRestoringPurchases = true
        Task {
            await purchases.restore()
            isRestoringPurchases = false
            restoreResultMessage = purchases.isFullVersion
                ? String(localized: "Full Version restored.")
                : String(localized: "No previous purchase was found for this Apple ID.")
        }
    }
}

// MARK: - Destinations

enum SetupDestination: Hashable {
    case categories, pickLists, appearance, deletedItems, quickStart, bulkMessage
}

// MARK: - Group and row

/// A titled card holding `SetupRow`s, hairline-separated.
struct SetupGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Baron.body(10.5, .medium))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Baron.neutral500)
            VStack(spacing: 0) { content }
                .baronCard(elevation: .low)
        }
        .padding(.top, 20)
    }
}

struct SetupRow: View {
    let name: LocalizedStringKey
    let sub: String
    let value: String
    var caret: String = "›"
    var tint: Color = Baron.text
    var isLast: Bool = false
    let action: () -> Void

    init(name: LocalizedStringKey, sub: String, value: String, caret: String = "›",
         tint: Color = Baron.text, isLast: Bool = false, action: @escaping () -> Void) {
        self.name = name
        self.sub = sub
        self.value = value
        self.caret = caret
        self.tint = tint
        self.isLast = isLast
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(Baron.body(14.5, .medium))
                            .foregroundStyle(tint)
                        Text(sub)
                            .font(Baron.body(12))
                            .foregroundStyle(Baron.neutral600)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !value.isEmpty {
                        Text(value)
                            .font(Baron.body(12, .medium))
                            .foregroundStyle(Baron.neutral500)
                    }
                    if !caret.isEmpty {
                        Text(caret)
                            .font(Baron.body(13, .medium))
                            .foregroundStyle(tint == Baron.text ? Baron.neutral400 : tint)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                if !isLast {
                    Baron.line.frame(height: 1).padding(.leading, 15)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Data actions

/// Export/import/reset/restore chrome, lifted out of `SetupTab.body` for readability. All of it
/// is carried over unchanged from the old Tools tab, including the factory-reset dialog's
/// type-the-word-"reset" friction.
private struct SetupDataActions: ViewModifier {
    @Environment(AssetStore.self) private var store

    @Binding var showingExporter: Bool
    @Binding var exportDocument: JSONExportDocument?
    @Binding var showingImportConfirm: Bool
    @Binding var showingImporter: Bool
    @Binding var showingImportDone: Bool
    @Binding var importError: String?
    @Binding var showingResetAlert: Bool
    @Binding var resetConfirmText: String
    @Binding var showingResetDone: Bool
    @Binding var restoreResultMessage: String?

    private var exportFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "BaronBook-\(formatter.string(from: Date()))"
    }

    func body(content: Content) -> some View {
        content
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
