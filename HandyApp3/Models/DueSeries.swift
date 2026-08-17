import Foundation

enum DueDefaults {
    /// Full range of the due-window and device-notification sliders, in days.
    static let sliderRange = 1...60
    /// Days marked with a tick on those sliders; dragging near one snaps to it.
    static let sliderTickDays = [1, 2, 3, 7, 14, 30, 60]
    static let messageDaysBefore = 7
    static let messageDaysAfter = 7
    static let notifyDaysBefore = 7
}

/// Bundles the due-date-related fields shared by Event and Transaction, so edit-view
/// onSave closures and store mutators take one parameter instead of five.
struct DueSettings: Equatable {
    var dueDate: Date? = nil
    var messageDaysBefore: Int = DueDefaults.messageDaysBefore
    var messageDaysAfter: Int = DueDefaults.messageDaysAfter
    var deviceNotificationOn: Bool = false
    var deviceNotificationDaysBefore: Int = DueDefaults.notifyDaysBefore
}

/// Common surface of Event/Transaction needed by `SeriesLogic`, so series/due-window/title
/// logic is written once and unit-tested without a store.
protocol SeriesRecord: AnyObject, Identifiable where ID == UUID {
    var id: UUID { get }
    var seriesID: UUID? { get }
    var createdAt: Date { get }
    var dueDate: Date? { get }
    var recurrence: RecurrenceInterval? { get }
    var messageDaysBefore: Int { get }
    var messageDaysAfter: Int { get }
    var deviceNotificationOn: Bool { get }
    var deviceNotificationDaysBefore: Int { get }
}

enum SeriesLogic {
    private static let yyyyMMPattern = try! NSRegularExpression(pattern: #"\b\d{4}-(0[1-9]|1[0-2])\b"#)
    private static let trailingCountSuffixPattern = try! NSRegularExpression(pattern: #"\s*\(\d+\)$"#)
    private static let trailingCountCapturePattern = try! NSRegularExpression(pattern: #"\((\d+)\)$"#)

    /// `createdAt` truncated to whole seconds, matching the persisted whole-second ISO-8601
    /// precision — so in-memory ordering agrees with ordering after a save/decode round-trip.
    private static func truncated(_ date: Date) -> TimeInterval {
        date.timeIntervalSince1970.rounded(.down)
    }

    /// All members of `record`'s series (including `record`), newest-created first. `all` must
    /// be the owning asset's *live* records (e.g. `liveEvents`) — tombstones are not filtered
    /// here. A record with no series is a singleton series of itself.
    static func members<R: SeriesRecord>(of record: R, in all: [R]) -> [R] {
        guard let seriesID = record.seriesID else { return [record] }
        return all
            .filter { $0.seriesID == seriesID }
            .sorted { lhs, rhs in
                let l = truncated(lhs.createdAt)
                let r = truncated(rhs.createdAt)
                if l != r { return l > r }
                return lhs.id.uuidString > rhs.id.uuidString
            }
    }

    /// The newest-created member of `record`'s series (itself, if not in a series).
    static func newest<R: SeriesRecord>(of record: R, in all: [R]) -> R {
        members(of: record, in: all).first ?? record
    }

    /// A `createdAt` for a new member of `source`'s series, guaranteed to sort strictly newer
    /// than every existing live series member (including `source` itself) — used when
    /// duplicating a recurring event/transaction. `members`/`newest` compare `createdAt`
    /// truncated to whole seconds (matching what survives an ISO-8601 round trip through
    /// persistence), so two records created within the same wall-clock second — routine for a
    /// duplicate created back-to-back with its source — would otherwise tie and fall back to
    /// comparing `id` strings, an ordering unrelated to which one was actually created later.
    /// The freshly duplicated record must always win that comparison, since it's the one meant
    /// to carry the series' recurring reminders forward (`NotificationPlanner.plan` only plans
    /// them for `SeriesLogic.newest`); bumps forward by a whole second — anything finer
    /// wouldn't survive the round trip either — when `now` doesn't already clear the series'
    /// current high-water mark.
    static func createdAtForNewSeriesMember<R: SeriesRecord>(after source: R, in siblings: [R], now: Date = Date()) -> Date {
        let seriesMembers = source.seriesID.map { id in siblings.filter { $0.seriesID == id } } ?? [source]
        let latest = seriesMembers.map { truncated($0.createdAt) }.max() ?? truncated(source.createdAt)
        return truncated(now) > latest ? now : Date(timeIntervalSince1970: latest + 1)
    }

    /// True while `record`'s due-window is active: from `messageDaysBefore` days before the due
    /// date through `messageDaysAfter` days after, inclusive, at day granularity.
    static func isDueMessageActive<R: SeriesRecord>(_ record: R, calendar: Calendar = .current, now: Date = Date()) -> Bool {
        guard let dueDate = record.dueDate else { return false }
        let startNow = calendar.startOfDay(for: now)
        let startDue = calendar.startOfDay(for: dueDate)
        guard let delta = calendar.dateComponents([.day], from: startNow, to: startDue).day else { return false }
        return delta >= -record.messageDaysAfter && delta <= record.messageDaysBefore
    }

    /// True when a strictly newer series sibling was logged during the current repeating
    /// period — the one recurrence interval leading up to `record`'s due date — so the
    /// post-due message for `record` should be suppressed in favor of that newer occurrence.
    /// `max(record.createdAt, periodStart)` keeps an older same-period sibling (the one
    /// `record` itself was duplicated from) from suppressing `record`. Records with no series,
    /// or no due date, are never suppressed.
    static func isSuppressed<R: SeriesRecord>(_ record: R, in all: [R], calendar: Calendar = .current, now: Date = Date()) -> Bool {
        guard let seriesID = record.seriesID, let dueDate = record.dueDate else { return false }
        let periodStart: Date
        if let recurrence = record.recurrence {
            let (component, value) = recurrence.componentAndValue
            periodStart = calendar.date(byAdding: component, value: -value, to: dueDate) ?? .distantPast
        } else {
            periodStart = .distantPast
        }
        let threshold = max(record.createdAt, periodStart)
        return all.contains { sibling in
            sibling.id != record.id && sibling.seriesID == seriesID && sibling.createdAt > threshold
        }
    }

    /// Due date a fresh series occurrence duplicated from `source` should start with. A
    /// recurring source's due date advances by one recurrence interval (a verbatim copy would
    /// make every new occurrence instantly overdue and — being the series' newest member —
    /// un-suppressible). A non-recurring source's due date copies verbatim. `nil` if `source`
    /// has no due date.
    static func advancedDueDate<R: SeriesRecord>(for source: R, calendar: Calendar = .current) -> Date? {
        guard let dueDate = source.dueDate else { return nil }
        guard let recurrence = source.recurrence else { return dueDate }
        let (component, value) = recurrence.componentAndValue
        return calendar.date(byAdding: component, value: value, to: dueDate) ?? dueDate
    }

    /// Title for a new duplicate created at `creationDate`. Tries appending " yyyy-MM"; if
    /// `source` already contains a yyyy-MM pattern, appends/increments a "(n)" suffix instead,
    /// scanning `seriesTitles` (the other live series members) plus `source` itself for the
    /// highest existing suffix.
    static func duplicateTitle(source: String, seriesTitles: [String], creationDate: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM"
        let yyyyMM = formatter.string(from: creationDate)

        let fullRange = NSRange(source.startIndex..., in: source)
        guard yyyyMMPattern.firstMatch(in: source, range: fullRange) != nil else {
            return source + " " + yyyyMM
        }

        let base = trailingCountSuffixPattern.stringByReplacingMatches(
            in: source, range: NSRange(source.startIndex..., in: source), withTemplate: ""
        )

        var highest = 1
        for title in seriesTitles + [source] {
            let range = NSRange(title.startIndex..., in: title)
            guard let match = trailingCountCapturePattern.firstMatch(in: title, range: range),
                  let numRange = Range(match.range(at: 1), in: title),
                  let n = Int(title[numRange]) else { continue }
            highest = max(highest, n)
        }
        return base + " (\(highest + 1))"
    }
}

extension Event: SeriesRecord {}
extension Transaction: SeriesRecord {}
