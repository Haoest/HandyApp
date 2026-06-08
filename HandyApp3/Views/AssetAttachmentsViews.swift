import SwiftUI
import UIKit
import Contacts

// MARK: - Image scaling

enum ImageScaling {
    static func scaled(_ image: UIImage, maxDimension: CGFloat, jpegQuality: CGFloat) -> Data? {
        let size = image.size
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: jpegQuality)
    }

    static func imageData(from image: UIImage) -> Data? {
        scaled(image, maxDimension: 1600, jpegQuality: 0.8)
    }

    static func thumbnailData(from image: UIImage) -> Data? {
        scaled(image, maxDimension: 300, jpegQuality: 0.7)
    }
}

// MARK: - Photos section

struct PhotosSection: View {
    @Environment(AssetStore.self) private var store
    let asset: Asset
    @State private var selectedPhoto: Photo?

    private var sorted: [Photo] { asset.photos.sorted { $0.addedDate > $1.addedDate } }

    var body: some View {
        Section("Photos") {
            if asset.photos.isEmpty {
                Text("None").foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(sorted) { photo in
                            thumbnailCell(photo)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .sheet(item: $selectedPhoto) { photo in
            PhotoViewerSheet(asset: asset, photo: photo)
        }
    }

    @ViewBuilder
    private func thumbnailCell(_ photo: Photo) -> some View {
        let img = UIImage(data: photo.thumbnailData) ?? UIImage()
        Button { selectedPhoto = photo } label: {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Photo viewer sheet

struct PhotoViewerSheet: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let asset: Asset
    let photo: Photo
    @State private var caption: String

    init(asset: Asset, photo: Photo) {
        self.asset = asset
        self.photo = photo
        _caption = State(initialValue: photo.caption)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let img = UIImage(data: photo.imageData) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal)
                    }
                    TextField("Caption", text: $caption, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                        .onSubmit { saveCaption() }
                }
                .padding(.vertical)
            }
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        saveCaption()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        try? store.removePhoto(id: photo.id, fromAssetID: asset.id)
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }

    private func saveCaption() {
        let trimmed = caption.trimmingCharacters(in: .whitespaces)
        guard trimmed != photo.caption else { return }
        try? store.updatePhotoCaption(trimmed, forPhotoID: photo.id, onAssetID: asset.id)
    }
}

// MARK: - Events section

struct EventsSection: View {
    @Environment(AssetStore.self) private var store
    let asset: Asset
    @State private var eventToEdit: Event?

    private var sorted: [Event] { asset.events.sorted { $0.date > $1.date } }

    var body: some View {
        Section("Events") {
            if asset.events.isEmpty {
                Text("None").foregroundStyle(.secondary)
            } else {
                ForEach(sorted) { event in
                    EventRow(event: event)
                        .contentShape(Rectangle())
                        .onTapGesture { eventToEdit = event }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                try? store.removeEvent(id: event.id, fromAssetID: asset.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .sheet(item: $eventToEdit) { event in
            EventEditView(existing: event) { title, date, notes in
                try? store.updateEvent(id: event.id, onAssetID: asset.id, title: title, date: date, notes: notes)
            }
        }
    }
}

private struct EventRow: View {
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.title)
                .fontWeight(.medium)
            Text(event.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !event.notes.isEmpty {
                Text(event.notes)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Event edit sheet

struct EventEditView: View {
    @Environment(\.dismiss) private var dismiss
    let existing: Event?
    let onSave: (String, Date, String) -> Void

    @State private var title: String
    @State private var date: Date
    @State private var notes: String

    init(existing: Event? = nil, onSave: @escaping (String, Date, String) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _title = State(initialValue: existing?.title ?? "")
        _date = State(initialValue: existing?.date ?? Date())
        _notes = State(initialValue: existing?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Event title", text: $title)
                }
                Section("Date") {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...)
                }
            }
            .navigationTitle(existing == nil ? "New Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title.trimmingCharacters(in: .whitespaces), date, notes.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Transactions section

struct TransactionsSection: View {
    @Environment(AssetStore.self) private var store
    let asset: Asset
    @State private var transactionToEdit: Transaction?

    private var sorted: [Transaction] { asset.transactions.sorted { $0.date > $1.date } }

    var body: some View {
        Section("Transactions") {
            if asset.transactions.isEmpty {
                Text("None").foregroundStyle(.secondary)
            } else {
                ForEach(sorted) { txn in
                    TransactionRow(transaction: txn)
                        .contentShape(Rectangle())
                        .onTapGesture { transactionToEdit = txn }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                try? store.removeTransaction(id: txn.id, fromAssetID: asset.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .sheet(item: $transactionToEdit) { txn in
            TransactionEditView(existing: txn) { details, amount, date, kind, payeeID, notes in
                try? store.updateTransaction(id: txn.id, onAssetID: asset.id, details: details, amount: amount, date: date, kind: kind, payeeContactID: payeeID, notes: notes)
            }
        }
    }
}

private struct TransactionRow: View {
    let transaction: Transaction

    private var amountText: String {
        let sign = transaction.kind == .expense ? "-" : "+"
        let formatted = transaction.amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
        return "\(sign)\(formatted)"
    }

    private var amountColor: Color {
        transaction.kind == .expense ? .red : .green
    }

    private var payeeName: String? {
        guard let id = transaction.payeeContactID else { return nil }
        return ContactResolver.shared.displayName(for: id)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.details)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let name = payeeName {
                        Text("· \(name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !transaction.notes.isEmpty {
                    Text(transaction.notes)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(amountText)
                .fontWeight(.semibold)
                .foregroundStyle(amountColor)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Transaction edit sheet

struct TransactionEditView: View {
    @Environment(\.dismiss) private var dismiss
    let existing: Transaction?
    let onSave: (String, Decimal, Date, TransactionKind, String?, String) -> Void

    @State private var details: String
    @State private var amountText: String
    @State private var date: Date
    @State private var kind: TransactionKind
    @State private var payeeContactID: String?
    @State private var payeeName: String
    @State private var notes: String
    @State private var contactPickerPresented = false

    init(existing: Transaction? = nil, onSave: @escaping (String, Decimal, Date, TransactionKind, String?, String) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _details = State(initialValue: existing?.details ?? "")
        _amountText = State(initialValue: existing.map { "\($0.amount)" } ?? "")
        _date = State(initialValue: existing?.date ?? Date())
        _kind = State(initialValue: existing?.kind ?? .expense)
        _payeeContactID = State(initialValue: existing?.payeeContactID)
        _notes = State(initialValue: existing?.notes ?? "")
        let resolvedName: String
        if let id = existing?.payeeContactID {
            resolvedName = ContactResolver.shared.displayName(for: id) ?? ""
        } else {
            resolvedName = ""
        }
        _payeeName = State(initialValue: resolvedName)
    }

    private var parsedAmount: Decimal? { Decimal(string: amountText) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Description") {
                    TextField("Description", text: $details)
                }
                Section("Amount") {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                    Picker("Type", selection: $kind) {
                        ForEach(TransactionKind.allCases, id: \.self) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Date") {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...)
                }
                Section("Contact") {
                    if payeeContactID != nil {
                        HStack {
                            Text(payeeName.isEmpty ? "(not found)" : payeeName)
                                .foregroundStyle(payeeName.isEmpty ? .tertiary : .primary)
                            Spacer()
                            Button { contactPickerPresented = true } label: {
                                Image(systemName: "person.crop.circle")
                            }
                            .buttonStyle(.borderless)
                            Button {
                                payeeContactID = nil
                                payeeName = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                    } else {
                        Button { contactPickerPresented = true } label: {
                            Label("Choose Contact", systemImage: "person.crop.circle")
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Transaction" : "Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let amount = parsedAmount ?? 0
                        onSave(details.trimmingCharacters(in: .whitespaces), amount, date, kind, payeeContactID, notes.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                    .disabled(details.trimmingCharacters(in: .whitespaces).isEmpty || parsedAmount == nil)
                }
            }
            .background(
                ContactPicker(isPresented: $contactPickerPresented) { id, name in
                    payeeContactID = id
                    payeeName = name
                }
            )
        }
    }
}
