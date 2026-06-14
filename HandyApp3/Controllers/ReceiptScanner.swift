import Foundation
import UIKit
import Vision

/// Result of analyzing a receipt photo: the cropped/deskewed image to show, the
/// visual text blocks the user can pick from, and every OCR token (kept so
/// merchant/kind can be read from the whole receipt even when the user only
/// selects the items block).
struct ReceiptAnalysis: Identifiable {
    let id = UUID()
    let image: UIImage
    let blocks: [TextBlock]
    let allTokens: [OCRToken]
}

// MARK: - Analyzer (thin I/O wrapper, untested)

/// Runs Apple Vision on-device text recognition over an in-memory image and
/// groups the tokens into selectable blocks. No networking, no permissions.
enum ReceiptScanner {

    static func analyze(_ imageData: Data) async -> ReceiptAnalysis? {
        guard let image = UIImage(data: imageData) else { return nil }

        // OCR the orientation-normalized full image, keeping bounding boxes. We
        // deliberately do NOT perspective-crop to a detected document rectangle:
        // VNDetectDocumentSegmentationRequest is unreliable on hand-held receipts
        // against cluttered backgrounds and warms up between calls, so a second
        // scan of the same photo could return a spurious quad that cropped the
        // image down to a strip (a partial photo with a single misplaced block).
        // The block-selection UI already lets the user focus on the relevant text.
        let normalized = normalizedUp(image)
        guard let cgImage = normalized.cgImage else { return nil }

        let tokens: [OCRToken] = await recognizeTokens(in: cgImage)
        guard !tokens.isEmpty else { return nil }

        let blocks = ReceiptParser.detectBlocks(from: tokens)
        return ReceiptAnalysis(image: UIImage(cgImage: cgImage), blocks: blocks, allTokens: tokens)
    }

    /// Redraw with `.up` orientation so EXIF rotation can't corrupt the box
    /// coordinates downstream.
    private static func normalizedUp(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }

    // MARK: OCR

    private static func recognizeTokens(in cgImage: CGImage) async -> [OCRToken] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let tokens: [OCRToken] = observations.compactMap { observation in
                    guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else {
                        return nil
                    }
                    // Vision's box is bottom-left normalized; flip y to top-left.
                    let b = observation.boundingBox
                    let box = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
                    return OCRToken(text: text, box: box)
                }
                continuation.resume(returning: tokens)
            }
            request.recognitionLevel = .accurate
            // Keep digits/prices verbatim — language correction mangles amounts.
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
}
