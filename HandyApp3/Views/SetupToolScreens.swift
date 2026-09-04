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
    @State private var contactsAccessDenied = false
    @State private var messageText = ""
    @State private var selectedMethods: [UUID: ContactMethod] = [:]
    @State private var sendQueue: OutboundMessageQueue?
    @State private var openFailed = false
    @State private var isOpeningMessage = false
    @State private var preparationError: String?

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
                Group {
                    if let sendQueue {
                        queueCard(sendQueue)
                    } else {
                        sendButton
                    }
                }
                .padding(.top, 18)
            }
        }
        .task { await loadContacts() }
        .alert("Couldn't prepare message", isPresented: Binding(
            get: { preparationError != nil },
            set: { if !$0 { preparationError = nil } }
        )) {
            Button("OK", role: .cancel) { preparationError = nil }
        } message: {
            Text(preparationError ?? "")
        }
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
        } else if contactsAccessDenied {
            VStack(spacing: 14) {
                Text("Contacts access is needed to find phone numbers and email addresses.")
                    .font(Baron.body(13))
                    .foregroundStyle(Baron.neutral600)
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .font(Baron.body(13, .medium))
                .foregroundStyle(Baron.accent800)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .padding(.horizontal, 20)
            .baronCard(radius: 16, elevation: .low)
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
                Text(name ?? String(localized: "(not in your contacts)", bundle: .appPreferred, locale: .appPreferred))
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
            Button { beginSending() } label: {
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
            Text("Your phone opens one message at a time. Come back here after sending each one.")
                .font(Baron.body(11.5))
                .foregroundStyle(Baron.neutral500)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func queueCard(_ queue: OutboundMessageQueue) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let current = queue.current {
                Text("MESSAGE \(queue.currentIndex + 1) OF \(queue.messages.count)")
                    .font(Baron.body(10.5, .medium))
                    .tracking(0.9)
                    .foregroundStyle(Baron.neutral500)
                Text(current.recipientName)
                    .font(Baron.body(16, .medium))
                    .foregroundStyle(Baron.text)
                Text(current.method.label)
                    .font(Baron.body(12))
                    .foregroundStyle(Baron.neutral600)

                if openFailed {
                    Text("That message app couldn't be opened. You can retry or skip this recipient.")
                        .font(Baron.body(11.5))
                        .foregroundStyle(Baron.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Button {
                        openCurrentMessage()
                    } label: {
                        if isOpeningMessage {
                            ProgressView().tint(.white)
                        } else {
                            Text(openFailed ? "Retry" : (queue.currentIndex == 0 ? "Open message" : "Open next"))
                        }
                    }
                    .font(Baron.body(12, .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Baron.fill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .disabled(isOpeningMessage)
                    if openFailed {
                        Button("Skip") { advanceQueue() }
                            .font(Baron.body(12, .medium))
                            .foregroundStyle(Baron.neutral700)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Baron.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Baron.neutral300, lineWidth: 1))
                    }
                }
                Button("Cancel remaining messages") {
                    sendQueue = nil
                    openFailed = false
                    isOpeningMessage = false
                }
                .font(Baron.body(11.5, .medium))
                .foregroundStyle(Baron.neutral600)
            } else {
                Text("All messages opened")
                    .font(Baron.body(16, .medium))
                    .foregroundStyle(Baron.text)
                Text("Each message was handed to its app for your review. Baron Book never sends on your behalf.")
                    .font(Baron.body(11.5))
                    .foregroundStyle(Baron.neutral600)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Done") {
                    sendQueue = nil
                    openFailed = false
                    isOpeningMessage = false
                }
                .font(Baron.body(12, .medium))
                .foregroundStyle(Baron.accent800)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .baronCard(radius: 15, elevation: .low)
    }

    private func loadContacts() async {
        let granted = (try? await ContactResolver.shared.requestAccess()) ?? false
        guard granted else {
            contactsAccessDenied = true
            isLoading = false
            return
        }

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
                    propertyName: BuiltInTypes.localizedSeedName(id: prop.definition.id, currentName: prop.definition.name),
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

    private func beginSending() {
        var messages: [OutboundMessage] = []
        for row in rows {
            guard let method = selectedMethods[row.id], let contact = row.contact else { continue }
            let destination: String
            switch method {
            case .sms, .whatsapp:
                destination = contact.phoneNumbers.first?.value.stringValue ?? ""
            case .email:
                destination = contact.emailAddresses.first.map { $0.value as String } ?? ""
            }
            do {
                let url = try CommunicationURLBuilder.makeURL(
                    method: method, destination: destination, message: messageText
                )
                let name = ContactResolver.shared.displayName(for: row.identifier)
                    ?? String(localized: "(not in your contacts)", bundle: .appPreferred, locale: .appPreferred)
                messages.append(OutboundMessage(id: row.id, recipientName: name, method: method, url: url))
            } catch {
                preparationError = String(localized: "One selected contact doesn't have a valid destination for \(method.label). Change that selection and try again.", bundle: .appPreferred, locale: .appPreferred)
                return
            }
        }
        guard !messages.isEmpty else { return }
        openFailed = false
        isOpeningMessage = false
        sendQueue = OutboundMessageQueue(messages: messages)
    }

    private func openCurrentMessage() {
        guard !isOpeningMessage, let current = sendQueue?.current else { return }
        openFailed = false
        isOpeningMessage = true
        UIApplication.shared.open(current.url, options: [:]) { accepted in
            DispatchQueue.main.async {
                isOpeningMessage = false
                if accepted {
                    advanceQueue()
                } else {
                    openFailed = true
                }
            }
        }
    }

    private func advanceQueue() {
        _ = sendQueue?.advance()
        openFailed = false
        isOpeningMessage = false
    }
}

// MARK: - Helpers

private extension Array where Element: Identifiable {
    func uniqued() -> [Element] {
        var seen = Set<Element.ID>()
        return filter { seen.insert($0.id).inserted }
    }
}
