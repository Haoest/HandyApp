import SwiftUI

/// Shows the cropped receipt with its detected text blocks overlaid. The user
/// taps blocks to toggle them (items and totals often sit in separate blocks),
/// then confirms — the union of the selected blocks' tokens is handed back for
/// parsing.
struct ReceiptBlockSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let analysis: ReceiptAnalysis
    let onConfirm: ([OCRToken]) -> Void

    @State private var selectedBlockIDs: Set<Int> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text("Tap the blocks that contain the items and total.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                GeometryReader { geo in
                    let frame = fittedImageFrame(imageSize: analysis.image.size, in: geo.size)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: analysis.image)
                            .resizable()
                            .scaledToFit()
                        ForEach(analysis.blocks) { block in
                            blockOverlay(block, in: frame)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .navigationTitle("Select Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Selection") {
                        let tokens = analysis.blocks
                            .filter { selectedBlockIDs.contains($0.id) }
                            .flatMap { $0.tokens }
                        onConfirm(tokens)
                        dismiss()
                    }
                    .disabled(selectedBlockIDs.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func blockOverlay(_ block: TextBlock, in frame: CGRect) -> some View {
        let isSelected = selectedBlockIDs.contains(block.id)
        let rect = viewRect(for: block.rect, in: frame)
        RoundedRectangle(cornerRadius: 4)
            .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary,
                                  lineWidth: isSelected ? 2 : 1)
            )
            .frame(width: rect.width, height: rect.height)
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelected { selectedBlockIDs.remove(block.id) }
                else { selectedBlockIDs.insert(block.id) }
            }
            // `.position` (center-based) moves both the rendering AND the hit-test frame;
            // `.offset` would move only the rendering, leaving the tap target at the
            // overlay's un-offset layout origin (the ZStack's top-leading corner).
            .position(x: rect.midX, y: rect.midY)
    }

    /// The letterboxed rect the `.scaledToFit()` image actually occupies within
    /// `container`.
    private func fittedImageFrame(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: (container.width - size.width) / 2,
                             y: (container.height - size.height) / 2)
        return CGRect(origin: origin, size: size)
    }

    /// Map a normalized (top-left origin) block rect into view coordinates.
    private func viewRect(for normalized: CGRect, in frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + normalized.minX * frame.width,
               y: frame.minY + normalized.minY * frame.height,
               width: normalized.width * frame.width,
               height: normalized.height * frame.height)
    }
}
