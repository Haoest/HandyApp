import Foundation

/// Ranks assets by how well their name matches a spoken/typed query, for resolving
/// Siri's `[name]` parameter. Exact matches sort first, then prefix, then substring,
/// then whole-word token matches; equal-rank results sort by name for a stable order.
enum AssetNameMatcher {
    static func match(_ query: String, in assets: [Asset]) -> [Asset] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let queryTokens = Set(tokens(of: trimmed))

        func rank(_ asset: Asset) -> Int? {
            let name = asset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                return 0
            }
            if name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil {
                return 1
            }
            if name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                return 2
            }
            let nameTokens = tokens(of: name)
            if !nameTokens.isEmpty, !queryTokens.isDisjoint(with: nameTokens) {
                return 3
            }
            return nil
        }

        let ranked: [(asset: Asset, rank: Int)] = assets.compactMap { asset in
            guard let r = rank(asset) else { return nil }
            return (asset, r)
        }

        let sorted = ranked.sorted { lhs, rhs -> Bool in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.asset.name.localizedCaseInsensitiveCompare(rhs.asset.name) == .orderedAscending
        }

        return sorted.map { $0.asset }
    }

    private static func tokens(of string: String) -> Set<String> {
        Set(
            string
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .components(separatedBy: .alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
    }
}
