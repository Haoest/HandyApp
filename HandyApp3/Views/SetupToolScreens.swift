import SwiftUI
import Contacts
import UIKit

// MARK: - Message everyone

private struct ContactRow: Identifiable {
    let id: UUID
    let asset: Asset
    let propertyName: String
    let identifier: String
    /// Nil when the identifier no longer resolves — the card says so rather than vanishing.
    let contact: CNContact?
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

/// Writes one message and sends it to the contacts attached to your things — the plumber on the
/// boiler, the mechanic on the car.
///
/// Each row's method is a set of chips including an explicit "Don't send", rather than a
/// segmented control whose "None" was the leftmost segment and easy to read as a fourth channel.
///
/// Everything with a contact on it is listed. The old screen walked only root things, so a
/// contact on anything filed inside another thing was silently absent; and it dropped any
/// contact with no phone or email, which looked the same as not finding it at all. Both now
/// appear, the second as a card that says why it can't be messaged.
struct BulkCommunicationView: View {
    @Environment(AssetStore.self) private var store

    @State private var rows: [ContactRow] = []
    @State private var isLoading = true
    @State private var messageText = ""
    @State private var selectedMethods: [UUID: ContactMethod] = [:]

    private var recipientCount: Int {
        selectedMethods.values.count
    }

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespaces).isEmpty && recipientCount > 0
    }

    var body: some View {
        SetupScreenBody {
            SetupScreenHeader(breadcrumb: "Setup")
            SetupScreenTitle(
                title: "Message everyone",
                blurb: "Write once, then pick who hears it. Each message opens in its own app so you can read it before it goes."
            )
            messageCard.padding(.top, 18)
            content.padding(.top, 20)
            if !rows.isEmpty {
                sendButton.padding(.top, 18)
            }
        }
        .task { await loadContacts() }
    }

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            RecordFieldLabel(text: "Message")
            TextField("Type a message…", text: $messageText, axis: .vertical)
                .lineLimit(3...6)
                .recordInput()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if rows.isEmpty {
            Text("No contacts yet. Give a thing a contact field — an owner, a plumber, a landlord — and they'll show up here.")
                .font(Baron.body(13))
                .foregroundStyle(Baron.neutral600)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
                .padding(.horizontal, 20)
                .baronCard(radius: 16, elevation: .low)
        } else {
            let grouped = Dictionary(grouping: rows) { $0.asset.id }
            VStack(alignment: .leading, spacing: 16) {
                ForEach(rows.map(\.asset).uniqued()) { asset in
                    VStack(alignment: .leading, spacing: 9) {
                        // The thing's own name, so it can't go through LocalizedStringKey.
                        Text(asset.name)
                            .font(Baron.body(10.5, .medium))
                            .tracking(0.9)
                            .textCase(.uppercase)
                            .foregroundStyle(Baron.neutral500)
                        VStack(spacing: 8) {
                            ForEach(grouped[asset.id] ?? []) { row in
                                contactCard(row)
                            }
                        }
                    }
                }
            }
        }
    }

    private func contactCard(_ row: ContactRow) -> some View {
        let name = ContactResolver.shared.displayName(for: row.identifier)
        let chosen = selectedMethods[row.id]
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name ?? String(localized: "(not in your contacts)", locale: .appPreferred))
                    .font(Baron.body(15, .medium))
                    .foregroundStyle(name == nil ? Baron.neutral500 : Baron.text)
                Text(row.propertyName)
                    .font(Baron.body(11.5))
                    .foregroundStyle(Baron.neutral600)
            }
            if row.availableMethods.isEmpty {
                Text(row.contact == nil
                     ? "This contact isn't on the phone any more, so there's nothing to send to."
                     : "No phone number or email on this contact.")
                    .font(Baron.body(11.5))
                    .foregroundStyle(Baron.neutral500)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                FlowLayout(spacing: 6) {
                    chip(title: "Don't send", selected: chosen == nil) { selectedMethods[row.id] = nil }
                    ForEach(row.availableMethods) { method in
                        chip(title: method.label, selected: chosen == method) { selectedMethods[row.id] = method }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .baronCard(radius: 15, elevation: .low)
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Baron.body(12, .medium))
                .foregroundStyle(selected ? Color.white : Baron.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? Baron.fill : Baron.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Color.clear : Baron.neutral300, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var sendButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { sendAll() } label: {
                Text(recipientCount == 0 ? "Send" : "Send to ^[\(recipientCount) contact](inflect: true)")
                    .font(Baron.heading(12))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Baron.fill, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .opacity(canSend ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            // Worth saying plainly: iOS hands each URL to another app, and only the first one
            // gets to open. This has always been the behaviour — the old screen just didn't
            // mention it.
            Text("Your phone opens one message at a time. Come back here after sending each one.")
                .font(Baron.body(11.5))
                .foregroundStyle(Baron.neutral500)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func loadContacts() async {
        var built: [ContactRow] = []
        // Every live thing, not just the roots — a contact on something filed inside another
        // thing (the boiler in the house) is exactly as messageable as one at the top.
        let things = store.allAssets.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        for asset in things {
            for prop in asset.liveBaseProperties + asset.liveCustomProperties {
                guard case .basic(.contact) = prop.definition.type,
                      case .contact(let identifier) = prop.value else { continue }
                let contact = try? ContactResolver.shared.contact(for: identifier)
                built.append(ContactRow(
                    id: UUID(),
                    asset: asset,
                    propertyName: prop.definition.name,
                    identifier: identifier,
                    contact: contact,
                    availableMethods: contact.map(availableMethods) ?? []
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
            guard let method = selectedMethods[row.id], let contact = row.contact else { continue }
            let urlString: String
            switch method {
            case .sms:
                let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
                let clean = phone.filter { $0.isNumber || $0 == "+" }
                urlString = "sms:\(clean)?&body=\(encoded)"
            case .email:
                let email = contact.emailAddresses.first.map { $0.value as String } ?? ""
                urlString = "mailto:\(email)?body=\(encoded)"
            case .whatsapp:
                let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
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
                "Open [name] in Baron Book",
                "Show [name] in Baron Book",
                "Open a thing in Baron Book"
            ],
            description: "Jump straight to a thing."
        ),
        SiriCommand(
            phrases: [
                "Add thing in Baron Book",
                "Create new thing in Baron Book"
            ],
            description: "Start adding a thing."
        ),
        SiriCommand(
            phrases: [
                "Add new named thing in Baron Book",
                "Create new named thing in Baron Book"
            ],
            description: "Start adding a thing with the name you say."
        ),
        SiriCommand(
            phrases: [
                "Add transaction to [thing] in Baron Book",
                "Record transaction to [thing] in Baron Book"
            ],
            description: "Start a transaction on a thing."
        ),
        SiriCommand(
            phrases: [
                "Add expense to [thing] in Baron Book",
                "Record expense to [thing] in Baron Book"
            ],
            description: "Start recording money out."
        ),
        SiriCommand(
            phrases: [
                "Add income to [thing] in Baron Book",
                "Record income to [thing] in Baron Book"
            ],
            description: "Start recording money in."
        )
    ]

    var body: some View {
        SetupScreenBody {
            SetupScreenHeader(breadcrumb: "Setup")
            SetupScreenTitle(
                title: "Ask Siri",
                blurb: "Say \"Hey Siri\" followed by any of these, anywhere on your device."
            )
            VStack(spacing: 9) {
                ForEach(commands) { command in
                    card(command)
                }
            }
            .padding(.top, 18)
        }
    }

    private func card(_ command: SiriCommand) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(command.phrases, id: \.self) { phrase in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 9))
                            .foregroundStyle(Baron.neutral400)
                        Text(phrase)
                            .font(Baron.body(14, .medium))
                            .foregroundStyle(Baron.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text(command.description)
                .font(Baron.body(11.5))
                .foregroundStyle(Baron.neutral600)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .baronCard(radius: 15, elevation: .low)
    }
}

// MARK: - Helpers

private extension Array where Element: Identifiable {
    func uniqued() -> [Element] {
        var seen = Set<Element.ID>()
        return filter { seen.insert($0.id).inserted }
    }
}
