import Foundation
import UIKit
import Vision

/// Best-effort structured result of scanning a receipt/check photo.
/// Everything here is a guess the user reviews and edits before saving.
struct ParsedReceipt {
    /// Transaction description (the editor requires a non-empty value to save).
    var details: String
    /// Item lines (description + price), one per element.
    var lineItems: [String]
    /// Detected total, if any. `nil` means "couldn't find a total".
    var total: Decimal?
    var kind: TransactionKind

    /// What flows into the transaction's notes field.
    var notesText: String { lineItems.joined(separator: "\n") }
}

// MARK: - OCR wrapper (thin, untested)

/// Runs Apple Vision on-device text recognition over an in-memory image and
/// hands the ordered lines to `ReceiptParser`. No networking, no permissions.
enum ReceiptScanner {
    static func scan(_ imageData: Data) async -> ParsedReceipt? {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            return nil
        }

        let lines: [String] = await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                // Top→bottom so "last total wins" heuristics are reliable.
                let ordered = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                continuation.resume(returning: ordered.compactMap { $0.topCandidates(1).first?.string })
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

        return ReceiptParser.parse(lines: lines)
    }
}

// MARK: - Parser (pure heuristics, unit-tested)

enum ReceiptParser {
    static func parse(lines rawLines: [String]) -> ParsedReceipt {
        let lines = rawLines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return ParsedReceipt(
            details: detectMerchant(in: lines),
            lineItems: detectLineItems(in: lines),
            total: detectTotal(in: lines),
            kind: detectKind(in: lines)
        )
    }

    // MARK: Amount extraction

    /// `$1,234.56`, `12.34`, `1234`, `12` — optional `$`, optional thousands
    /// separators, 0–2 decimals.
    private static let amountPattern = #"\$?\s*(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,2})?"#

    private static let amountRegex = try! NSRegularExpression(pattern: amountPattern)
    private static let trailingAmountRegex = try! NSRegularExpression(pattern: amountPattern + #"\s*$"#)

    private static func decimal(from raw: String) -> Decimal? {
        let cleaned = raw
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Decimal(string: cleaned)
    }

    private static func allAmounts(in line: String) -> [Decimal] {
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        return amountRegex.matches(in: line, range: range).compactMap {
            decimal(from: ns.substring(with: $0.range))
        }
    }

    /// The amount a line ends with, e.g. the price column. `nil` if the line
    /// doesn't end in a number.
    private static func trailingAmount(in line: String) -> Decimal? {
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = trailingAmountRegex.firstMatch(in: line, range: range) else { return nil }
        return decimal(from: ns.substring(with: match.range))
    }

    // MARK: Total

    /// Most specific keywords first; the last matching line wins.
    private static let totalKeywords = ["grand total", "total due", "balance due", "amount due", "total"]

    private static func detectTotal(in lines: [String]) -> Decimal? {
        for keyword in totalKeywords {
            let matches = lines.filter {
                let lower = $0.lowercased()
                return lower.contains(keyword) && !lower.contains("subtotal")
            }
            if let last = matches.last, let amount = allAmounts(in: last).last {
                return amount
            }
        }
        // No keyword anywhere: best guess is the largest amount on the receipt.
        return lines.flatMap { allAmounts(in: $0) }.max()
    }

    // MARK: Line items

    private static let nonItemKeywords = [
        "subtotal", "total", "tax", "change", "cash", "tip",
        "pay to the order", "balance", "amount due"
    ]

    private static func detectLineItems(in lines: [String]) -> [String] {
        lines.filter { line in
            guard trailingAmount(in: line) != nil else { return false }
            guard line.contains(where: { $0.isLetter }) else { return false }
            let lower = line.lowercased()
            return !nonItemKeywords.contains { lower.contains($0) }
        }
    }

    // MARK: Merchant (description)

    private static func detectMerchant(in lines: [String]) -> String {
        // First line that reads like text rather than a priced row.
        for line in lines where line.contains(where: { $0.isLetter }) && trailingAmount(in: line) == nil {
            return line
        }
        return "Receipt"
    }

    // MARK: Expense vs income

    private static let incomePhrases = ["pay to the order of", "payroll", "deposit"]

    private static func detectKind(in lines: [String]) -> TransactionKind {
        let joined = lines.joined(separator: " ").lowercased()
        if incomePhrases.contains(where: { joined.contains($0) }) { return .income }
        // Standalone "check" (avoid matching "checkout", "checker", …).
        if joined.range(of: #"\bcheck\b"#, options: .regularExpression) != nil { return .income }
        return .expense
    }
}
