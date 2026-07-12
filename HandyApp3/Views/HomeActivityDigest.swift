import Foundation

/// One rendered line on the Home screen: either a single activity entry, or a
/// count-summary collapsing 3+ same-type entries logged to one asset in a day.
enum HomeRow: Identifiable {
    case single(ActivityLogEntry)
    /// 3+ entries of `kind` logged to `owningAssetID` on the same day. `latest` is
    /// the newest entry's timestamp, used only for ordering.
    case summary(kind: LoggedRecordKind, owningAssetID: UUID, count: Int, latest: Date)

    var id: String {
        switch self {
        case .single(let entry):
            return "single-\(entry.id.uuidString)"
        case .summary(let kind, let assetID, _, _):
            return "summary-\(kind.rawValue)-\(assetID.uuidString)"
        }
    }
}

/// A day's worth of Home rows, already grouped and summarized.
struct HomeDay {
    let day: Date
    let rows: [HomeRow]
}

/// Builds the Home screen's grouped/summarized view of the activity log. Pure and
/// deterministic so it can be unit-tested without the store or SwiftUI.
enum HomeActivityDigest {

    /// Number of most-recent active days surfaced per page on Home.
    static let pageSize = 3

    /// Threshold at which same-type, same-asset, same-day entries collapse into a
    /// single counted summary line.
    private static let summaryThreshold = 3

    /// Within-day ordering of the type buckets. Asset-creation lines come first;
    /// the rest follow the order the user reads the types.
    private static func typeRank(_ kind: LoggedRecordKind) -> Int {
        switch kind {
        case .asset: return 0
        case .photo: return 1
        case .event: return 2
        case .transaction: return 3
        }
    }

    static func build(from entries: [ActivityLogEntry], dayLimit: Int = pageSize, calendar: Calendar = .current) -> [HomeDay] {
        let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.timestamp) }
        let recentDays = byDay.keys.sorted(by: >).prefix(dayLimit)
        return recentDays.map { day in
            HomeDay(day: day, rows: rows(for: byDay[day] ?? []))
        }
    }

    /// Total number of distinct active days represented in `entries`, used to
    /// decide whether a "more" page is available beyond the current `dayLimit`.
    static func activeDayCount(in entries: [ActivityLogEntry], calendar: Calendar = .current) -> Int {
        Set(entries.map { calendar.startOfDay(for: $0.timestamp) }).count
    }

    /// Bucket a single day's entries by `(kind, owningAssetID)`, collapsing 3+
    /// photo/event/transaction entries on one asset into a summary. Asset-creation
    /// entries are never summarized.
    private static func rows(for entries: [ActivityLogEntry]) -> [HomeRow] {
        // Group key: nil owner (or asset-creation) stays per-entry; everything else
        // groups by (kind, owner).
        struct Bucket { var entries: [ActivityLogEntry] }
        var buckets: [String: Bucket] = [:]
        var order: [String] = []

        func append(_ key: String, _ entry: ActivityLogEntry) {
            if buckets[key] == nil { buckets[key] = Bucket(entries: []); order.append(key) }
            buckets[key]!.entries.append(entry)
        }

        for entry in entries {
            if entry.kind != .asset, let owner = entry.owningAssetID {
                append("\(entry.kind.rawValue)-\(owner.uuidString)", entry)
            } else {
                // Asset-creation, or a defensive nil-owner record: never grouped.
                append("single-\(entry.id.uuidString)", entry)
            }
        }

        var rows: [(row: HomeRow, rank: Int, latest: Date)] = []
        for key in order {
            let group = buckets[key]!.entries.sorted { $0.timestamp > $1.timestamp }
            guard let first = group.first else { continue }
            let latest = first.timestamp
            if group.count >= summaryThreshold,
               first.kind != .asset,
               let owner = first.owningAssetID {
                rows.append((.summary(kind: first.kind, owningAssetID: owner, count: group.count, latest: latest),
                             typeRank(first.kind), latest))
            } else {
                for entry in group {
                    rows.append((.single(entry), typeRank(entry.kind), entry.timestamp))
                }
            }
        }

        // Type buckets in fixed order; within a type, newest activity first.
        return rows
            .sorted { lhs, rhs in
                lhs.rank != rhs.rank ? lhs.rank < rhs.rank : lhs.latest > rhs.latest
            }
            .map(\.row)
    }
}
