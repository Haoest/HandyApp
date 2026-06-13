import Foundation
import UIKit
import Vision
import CoreImage

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

/// Runs Apple Vision on-device document detection + text recognition over an
/// in-memory image. No networking, no permissions.
enum ReceiptScanner {

    /// Reused across scans — allocating a `CIContext` per call is expensive.
    private static let ciContext = CIContext()

    static func analyze(_ imageData: Data) async -> ReceiptAnalysis? {
        guard let image = UIImage(data: imageData) else { return nil }

        // Stage 1 — detect & crop the receipt; fall back to the whole image.
        let normalized = normalizedUp(image)
        guard let cgImage = normalized.cgImage else { return nil }
        let cropped = croppedReceipt(from: cgImage) ?? cgImage

        // Stage 2 — OCR the cropped image, keeping bounding boxes.
        let tokens: [OCRToken] = await recognizeTokens(in: cropped)
        guard !tokens.isEmpty else { return nil }

        let blocks = ReceiptParser.detectBlocks(from: tokens)
        return ReceiptAnalysis(image: UIImage(cgImage: cropped), blocks: blocks, allTokens: tokens)
    }

    // MARK: Stage 1

    /// Redraw with `.up` orientation so EXIF rotation can't corrupt corner
    /// mapping or box coordinates downstream.
    private static func normalizedUp(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }

    /// Perspective-correct + crop the dominant document rectangle. Returns `nil`
    /// when no confident rectangle is found or the render fails.
    private static func croppedReceipt(from cgImage: CGImage) -> CGImage? {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first as? VNRectangleObservation,
              observation.confidence > 0.5 else {
            return nil
        }

        // Vision and CIImage both use a bottom-left, normalized origin.
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: extent.origin.x + p.x * extent.width,
                    y: extent.origin.y + p.y * extent.height)
        }
        let corrected = ciImage.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": CIVector(cgPoint: point(observation.topLeft)),
            "inputTopRight": CIVector(cgPoint: point(observation.topRight)),
            "inputBottomLeft": CIVector(cgPoint: point(observation.bottomLeft)),
            "inputBottomRight": CIVector(cgPoint: point(observation.bottomRight))
        ])
        return ciContext.createCGImage(corrected, from: corrected.extent)
    }

    // MARK: Stage 2

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
