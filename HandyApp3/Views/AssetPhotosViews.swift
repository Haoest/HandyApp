import SwiftUI
import UIKit

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

// MARK: - Decoded-image cache

/// Decoded thumbnails, keyed by photo id.
///
/// `UIImage(data:)` is a JPEG decode. Doing it inline in a view body meant every
/// re-evaluation of the asset detail form — one per store mutation, and one per frame of the
/// keyboard's presentation animation — re-decoded every visible thumbnail on the main thread.
/// The cached images are also pre-decoded (`preparingForDisplay`), so Core Animation doesn't
/// repeat the work lazily at draw time either.
enum ThumbnailCache {
    private final class Entry {
        let image: UIImage
        /// Guards against a stale hit if the photo's bytes are replaced under the same id.
        let byteCount: Int
        init(image: UIImage, byteCount: Int) {
            self.image = image
            self.byteCount = byteCount
        }
    }

    private static let cache: NSCache<NSUUID, Entry> = {
        let cache = NSCache<NSUUID, Entry>()
        cache.countLimit = 300
        return cache
    }()

    /// The photo's thumbnail, decoded once and reused. Nil until its bytes have been
    /// loaded from disk (see the `.task` in `PhotosSection.thumbnailCell`).
    static func image(for photo: Photo) -> UIImage? {
        guard let data = photo.thumbnailData else { return nil }
        let key = photo.id as NSUUID
        if let hit = cache.object(forKey: key), hit.byteCount == data.count { return hit.image }
        guard let decoded = UIImage(data: data) else { return nil }
        let image = decoded.preparingForDisplay() ?? decoded
        cache.setObject(Entry(image: image, byteCount: data.count), forKey: key)
        return image
    }
}

// MARK: - Photos section

struct PhotosSection: View {
    @Environment(AssetStore.self) private var store
    let asset: Asset
    // Selection is owned by the parent Form (not this Section) so re-evaluating the
    // section's body during presentation can't cancel the first present — same reason
    // the event/transaction sheets live at the Form level.
    @Binding var selectedPhoto: Photo?
    let onAdd: () -> Void

    private var sorted: [Photo] { asset.livePhotos.sorted { $0.addedDate > $1.addedDate } }

    var body: some View {
        Section {
            if sorted.isEmpty {
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
                .pagingExcludedRow(id: "photos")
            }
        } header: {
            AddSectionHeader(title: "Photos", action: onAdd)
        }
    }

    @ViewBuilder
    private func thumbnailCell(_ photo: Photo) -> some View {
        Button { selectedPhoto = photo } label: {
            Group {
                if let img = ThumbnailCache.image(for: photo) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .task(id: photo.id) {
            guard photo.thumbnailData == nil else { return }
            for _ in 0..<10 {
                if Task.isCancelled { return }
                if let data = PhotoStorage.loadThumb(id: photo.id) {
                    photo.thumbnailData = data
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

// MARK: - Photo viewer sheet

struct PhotoViewerSheet: View {
    @Environment(AssetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let asset: Asset
    let photo: Photo
    @State private var caption: String
    @FocusState private var captionFocused: Bool
    /// The full-size image, loaded and decoded once off the main thread. Held here rather
    /// than decoded in `body`: the caption field re-evaluates this body on every keystroke,
    /// and reading the JPEG back off disk and decoding it each time made typing crawl.
    @State private var fullImage: UIImage?
    @State private var isScanning = false
    @State private var analysis: ReceiptAnalysis?
    @State private var pendingPrefill: Transaction?
    @State private var scannedPrefill: Transaction?
    @State private var showNoTotalAlert = false
    @State private var paywallPresented = false

    init(asset: Asset, photo: Photo) {
        self.asset = asset
        self.photo = photo
        _caption = State(initialValue: photo.caption)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let fullImage {
                        Image(uiImage: fullImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal)
                    }
                    TextField("Caption", text: $caption, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                        .focused($captionFocused)
                        .onSubmit { saveCaption() }
                        .commitsPendingEdit(focused: captionFocused) { saveCaption() }
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
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if store.hasTransactionCapacity(for: asset) {
                            scanReceipt()
                        } else {
                            paywallPresented = true
                        }
                    } label: {
                        Image(systemName: "doc.text.viewfinder")
                    }
                    .disabled(isScanning)
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
            .overlay {
                if isScanning {
                    ProgressView("Scanning…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("Couldn't find a receipt", isPresented: $showNoTotalAlert) {
                Button("Enter Manually") {
                    if store.hasTransactionCapacity(for: asset) {
                        scannedPrefill = Transaction(details: "", amount: 0, date: Date(), kind: .expense)
                    } else {
                        paywallPresented = true
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Open the transaction editor to enter the details yourself.")
            }
            // Present the editor only after the selection sheet has fully
            // dismissed, so the two sheets don't fight at the same level.
            .sheet(item: $analysis, onDismiss: {
                if let pendingPrefill {
                    scannedPrefill = pendingPrefill
                    self.pendingPrefill = nil
                }
            }) { analysis in
                ReceiptBlockSelectionView(analysis: analysis) { tokens in
                    let parsed = ReceiptParser.parse(selectedTokens: tokens, allTokens: analysis.allTokens)
                    pendingPrefill = Transaction(details: parsed.details, amount: parsed.total ?? 0, date: Date(), kind: parsed.kind, notes: parsed.notesText)
                }
            }
            .sheet(item: $scannedPrefill) { prefill in
                TransactionEditView(prefill: prefill, assetName: asset.name, assetID: asset.id) { details, amount, date, kind, payeeID, notes, recurrence, due in
                    try? store.addTransaction(details: details, amount: amount, date: date, kind: kind, payeeContactID: payeeID, notes: notes, recurrence: recurrence, due: due, toAssetID: asset.id)
                }
            }
            .sheet(isPresented: $paywallPresented) {
                PaywallView(reason: .transactions)
            }
            .task(id: photo.id) {
                // Photos load lazily from disk; a freshly synced one may not have arrived yet,
                // hence the retry loop. Decoding happens off the main thread and the result is
                // held in `fullImage` so re-rendering the caption field never repeats it.
                for _ in 0..<10 {
                    if Task.isCancelled { return }
                    if let data = photo.imageData ?? PhotoStorage.loadFull(id: photo.id) {
                        photo.imageData = data
                        let decoded = await Task.detached(priority: .userInitiated) {
                            UIImage(data: data)?.preparingForDisplay()
                        }.value
                        if Task.isCancelled { return }
                        fullImage = decoded
                        return
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    private func scanReceipt() {
        guard let imageData = photo.imageData ?? PhotoStorage.loadFull(id: photo.id) else {
            showNoTotalAlert = true
            return
        }
        isScanning = true
        Task {
            let result = await ReceiptScanner.analyze(imageData)
            isScanning = false
            if let result, !result.blocks.isEmpty {
                analysis = result
            } else {
                showNoTotalAlert = true
            }
        }
    }

    private func saveCaption() {
        let trimmed = caption.trimmingCharacters(in: .whitespaces)
        guard trimmed != photo.caption else { return }
        try? store.updatePhotoCaption(trimmed, forPhotoID: photo.id, onAssetID: asset.id)
    }
}
