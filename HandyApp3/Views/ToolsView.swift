import SwiftUI
import Contacts

// MARK: - Tools tab

struct ToolsTab: View {
    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                List {
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
                }
                .scrollContentBackground(.hidden)
                .environment(\.colorScheme, .light)
            }
            .navigationTitle("Tools")
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Deleted assets

struct DeletedAssetsView: View {
    @Environment(AssetStore.self) private var store

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
