import Foundation
import CoreGraphics

// MARK: - Result

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

// MARK: - Geometry value types

/// A single OCR token (Vision returns a description and its price as separate
/// tokens). `box` is normalized 0–1 with a **top-left** origin relative to the
/// cropped receipt image, so smaller `y` is higher on the page.
struct OCRToken {
    let text: String
    let box: CGRect
}

/// A visual block of text — a contiguous run of rows separated from its
/// neighbours by a larger-than-normal vertical gap (header, items, totals,
/// footer). Selectable on `ReceiptBlockSelectionView`.
struct TextBlock: Identifiable {
    let id: Int
    /// Union of the member tokens' boxes (normalized, top-left origin).
    let rect: CGRect
    let tokens: [OCRToken]
    /// First couple of reconstructed lines, shown as a hint on the overlay.
    let previewText: String
}

// MARK: - Parser (pure heuristics, unit-tested)

enum ReceiptParser {

    // MARK: Row grouping

    /// One reconstructed line: the tokens sitting on a single baseline, joined
    /// left→right.
    private struct Row {
        let tokens: [OCRToken]
        let rect: CGRect
        let text: String
    }

    /// Median height of the token boxes; the unit for "same row" and
    /// "block boundary" decisions. Falls back to a small constant when empty.
    private static func medianHeight(_ tokens: [OCRToken]) -> CGFloat {
        let heights = tokens.map { $0.box.height }.sorted()
        guard !heights.isEmpty else { return 0.02 }
        return heights[heights.count / 2]
    }

    /// Group tokens into baseline rows, top→bottom, each joined left→right.
    private static func rows(from tokens: [OCRToken]) -> [Row] {
        let ordered = tokens.sorted { $0.box.midY < $1.box.midY }
        guard !ordered.isEmpty else { return [] }
        let threshold = medianHeight(ordered) * 0.5

        var rows: [[OCRToken]] = []
        var current: [OCRToken] = [ordered[0]]
        var referenceMidY = ordered[0].box.midY
        for token in ordered.dropFirst() {
            if abs(token.box.midY - referenceMidY) <= threshold {
                current.append(token)
            } else {
                rows.append(current)
                current = [token]
                referenceMidY = token.box.midY
            }
        }
        rows.append(current)

        return rows.map { rowTokens in
            let sorted = rowTokens.sorted { $0.box.minX < $1.box.minX }
            let rect = sorted.dropFirst().reduce(sorted[0].box) { $0.union($1.box) }
            let text = sorted.map { $0.text }.joined(separator: " ")
            return Row(tokens: sorted, rect: rect, text: text)
        }
    }

    /// Reconstruct text lines from loose tokens — `"Milk"` + `"3.99"` → `"Milk 3.99"`.
    static func reconstructLines(_ tokens: [OCRToken]) -> [String] {
        rows(from: tokens).map { $0.text }
    }

    // MARK: Block detection

    /// Split tokens into visual blocks: consecutive rows whose vertical gap
    /// exceeds a full blank line are treated as separate blocks.
    static func detectBlocks(from tokens: [OCRToken]) -> [TextBlock] {
        let rows = rows(from: tokens)
        guard !rows.isEmpty else { return [] }
        let gapThreshold = medianHeight(tokens)

        var groups: [[Row]] = []
        var current: [Row] = [rows[0]]
        for row in rows.dropFirst() {
            let gap = row.rect.minY - current[current.count - 1].rect.maxY
            if gap > gapThreshold {
                groups.append(current)
                current = [row]
            } else {
                current.append(row)
            }
        }
        groups.append(current)

        return groups.enumerated().map { index, rows in
            let rect = rows.dropFirst().reduce(rows[0].rect) { $0.union($1.rect) }
            let preview = rows.prefix(2).map { $0.text }.joined(separator: "\n")
            return TextBlock(id: index, rect: rect, tokens: rows.flatMap { $0.tokens }, previewText: preview)
        }
    }

    // MARK: Money matching (adaptive $ rule)

    /// `$`-anchored amount: `$12`, `$1,234.56`, `$ 9.99`.
    private static let dollarPattern = #"\$\s*\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?"#
    /// Decimal-cents amount with no `$`: `42.50`, `1,234.56` — never a bare integer.
    private static let centsPattern = #"\d{1,3}(?:,\d{3})*\.\d{1,2}"#

    /// Decides, for one region of text, whether the dollar sign is in use and
    /// classifies numbers accordingly: when `$` appears anywhere a number must
    /// carry it; otherwise decimal cents are required. Either way a bare integer
    /// (zip/phone/quantity) is never an amount.
    private struct MoneyMatcher {
        private let regex: NSRegularExpression
        private let trailingRegex: NSRegularExpression

        init(lines: [String]) {
            let dollar = try! NSRegularExpression(pattern: ReceiptParser.dollarPattern)
            let dollarInUse = lines.contains { line in
                let ns = line as NSString
                return dollar.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil
            }
            let pattern = dollarInUse ? ReceiptParser.dollarPattern : ReceiptParser.centsPattern
            regex = try! NSRegularExpression(pattern: pattern)
            trailingRegex = try! NSRegularExpression(pattern: pattern + #"\s*$"#)
        }

        func amounts(in line: String) -> [Decimal] {
            let ns = line as NSString
            return regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
                .compactMap { ReceiptParser.decimal(from: ns.substring(with: $0.range)) }
        }

        /// The amount a line ends with (the price column). `nil` if it doesn't.
        func trailing(in line: String) -> Decimal? {
            let ns = line as NSString
            guard let match = trailingRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
                return nil
            }
            return ReceiptParser.decimal(from: ns.substring(with: match.range))
        }
    }

    private static func decimal(from raw: String) -> Decimal? {
        let cleaned = raw
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Decimal(string: cleaned)
    }

    // MARK: Entry points

    /// Parse with separate inputs for the purchase region (items + total) and
    /// the wider context (merchant + kind). The interactive flow passes the
    /// user-selected tokens as the items and the whole receipt as context.
    static func parse(itemLines rawItems: [String], contextLines rawContext: [String]) -> ParsedReceipt {
        let items = clean(rawItems)
        let context = clean(rawContext)
        let itemMoney = MoneyMatcher(lines: items)
        let contextMoney = MoneyMatcher(lines: context)
        return ParsedReceipt(
            details: detectMerchant(in: context, money: contextMoney),
            lineItems: detectLineItems(in: items, money: itemMoney),
            total: detectTotal(in: items, money: itemMoney),
            kind: detectKind(in: context)
        )
    }

    /// Convenience for flat-text callers/tests: context and items are the same.
    static func parse(lines: [String]) -> ParsedReceipt {
        parse(itemLines: lines, contextLines: lines)
    }

    /// Interactive entry point: items/total from the user's selection, merchant
    /// and kind from the whole receipt.
    static func parse(selectedTokens: [OCRToken], allTokens: [OCRToken]) -> ParsedReceipt {
        parse(itemLines: reconstructLines(selectedTokens), contextLines: reconstructLines(allTokens))
    }

    private static func clean(_ lines: [String]) -> [String] {
        lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // MARK: Total

    /// Most specific keywords first; the bottom-most matching line wins.
    private static let totalKeywords = ["grand total", "total due", "balance due", "amount due", "total"]

    private static func detectTotal(in lines: [String], money: MoneyMatcher) -> Decimal? {
        for keyword in totalKeywords {
            let matches = lines.filter {
                let lower = $0.lowercased()
                return lower.contains(keyword) && !lower.contains("subtotal")
            }
            if let last = matches.last, let amount = money.amounts(in: last).last {
                return amount
            }
        }
        // No keyword anywhere: best guess is the largest amount in the region.
        return lines.flatMap { money.amounts(in: $0) }.max()
    }

    // MARK: Line items

    private static let nonItemKeywords = [
        "subtotal", "total", "tax", "change", "cash", "tip",
        "pay to the order", "balance", "amount due"
    ]

    private static func detectLineItems(in lines: [String], money: MoneyMatcher) -> [String] {
        lines.filter { line in
            guard money.trailing(in: line) != nil else { return false }
            guard line.contains(where: { $0.isLetter }) else { return false }
            let lower = line.lowercased()
            return !nonItemKeywords.contains { lower.contains($0) }
        }
    }

    // MARK: Merchant (description)

    private static func detectMerchant(in lines: [String], money: MoneyMatcher) -> String {
        // First line that reads like text rather than a priced row.
        for line in lines where line.contains(where: { $0.isLetter }) && money.trailing(in: line) == nil {
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
