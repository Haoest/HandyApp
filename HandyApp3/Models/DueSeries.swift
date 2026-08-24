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
    /// An existing "(n)" tag immediately following a matched yyyy-MM — anchored to the *start*
    /// of the remainder after that match, not the end of the whole string, so it's found
    /// correctly even when the date isn't the very last thing in the description.
    private static let leadingCountSuffixPattern = try! NSRegularExpression(pattern: #"^\s*\(\d+\)"#)
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

    /// Rolls `base` forward in whole `interval` steps until it lands strictly after `target`,
    /// compared at day granularity. Returns `base` untouched when it is already past `target`.
    static func rollForward(_ base: Date, past target: Date, interval: RecurrenceInterval, calendar: Calendar = .current) -> Date {
        let (component, value) = interval.componentAndValue
        let targetDay = calendar.startOfDay(for: target)
        var result = base
        // Bounded walk: a years-stale anchor still resolves in a few hundred steps, and a
        // calendar that declines to advance (or advances backwards) can't spin here forever.
        for _ in 0..<maxRollForwardSteps {
            guard calendar.startOfDay(for: result) <= targetDay else { break }
            guard let next = calendar.date(byAdding: component, value: value, to: result), next > result else { break }
            result = next
        }
        return result
    }

    private static let maxRollForwardSteps = 5_000

    /// Due date a new occurrence of `source`'s series, dated `occurrenceDate`, should start
    /// with: the series' latest due date falling strictly before `occurrenceDate`, rolled
    /// forward in whole intervals until it is the first such date after it.
    ///
    /// The anchor is the last *existing* occurrence's due date — the occurrence being logged
    /// is not a series member yet and never anchors itself — which keeps a logged occurrence
    /// on the series' original grid instead of one interval past today: a quarterly series due
    /// Jun 1, logged Aug 23, comes due Sep 1, not Nov 23.
    ///
    /// Falls back to the series' earliest due date when every recorded due date is still ahead
    /// of `occurrenceDate` (nothing precedes it to anchor on), which `rollForward` then returns
    /// untouched. A non-recurring source's due date copies verbatim; `nil` when `source` has no
    /// due date at all. `interval` is passed in rather than read off `source` so the edit sheet
    /// can project against an interval the user has changed but not yet saved.
    static func projectedDueDate<R: SeriesRecord>(for source: R, in siblings: [R], occurrenceDate: Date, interval: RecurrenceInterval?, calendar: Calendar = .current) -> Date? {
        guard let sourceDue = source.dueDate else { return nil }
        guard let interval else { return sourceDue }
        var candidates = members(of: source, in: siblings)
        // `members` filters `siblings` by series id, so a source not present in that array
        // (a record still being composed) would otherwise drop its own due date.
        if !candidates.contains(where: { $0.id == source.id }) { candidates.append(source) }
        let dueDates = candidates.compactMap(\.dueDate)
        let occurrenceDay = calendar.startOfDay(for: occurrenceDate)
        let anchor = dueDates.filter { calendar.startOfDay(for: $0) < occurrenceDay }.max()
            ?? dueDates.min()
            ?? sourceDue
        return rollForward(anchor, past: occurrenceDate, interval: interval, calendar: calendar)
    }

    /// Title for a new duplicate created at `creationDate`.
    ///
    /// 1. No yyyy-MM found anywhere in `source` → append the current one.
    /// 2. A yyyy-MM found but it isn't the current month → replace it (and any "(n)" it
    ///    carried, now meaningless) with the plain current month — a fresh month starts
    ///    unstamped, same as rule 1.
    /// 3. A yyyy-MM found and it *is* the current month → the description is being duplicated
    ///    again within the same month, so it needs a "(n)" disambiguator. The number is one
    ///    past the highest "(n)" already trailing this same current-month stamp on any live
    ///    series member (`seriesTitles`) or on `source` itself; absent any, it starts at 1.
    static func duplicateTitle(source: String, seriesTitles: [String], creationDate: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM"
        let currentYYYYMM = formatter.string(from: creationDate)

        let fullRange = NSRange(source.startIndex..., in: source)
        guard let dateMatch = yyyyMMPattern.firstMatch(in: source, range: fullRange),
              let dateRange = Range(dateMatch.range, in: source) else {
            return source + " " + currentYYYYMM
        }

        // Extend the span to be replaced past any "(n)" already trailing the matched date —
        // stale in the month-changed case, and recomputed fresh in the same-month case either way.
        let afterDate = source[dateRange.upperBound...]
        var replacedRange = dateRange
        if let suffixMatch = leadingCountSuffixPattern.firstMatch(
            in: String(afterDate), range: NSRange(afterDate.startIndex..., in: afterDate)
        ), let suffixRange = Range(suffixMatch.range, in: afterDate) {
            replacedRange = dateRange.lowerBound..<suffixRange.upperBound
        }

        let matchedYYYYMM = String(source[dateRange])
        guard matchedYYYYMM == currentYYYYMM else {
            return source.replacingCharacters(in: replacedRange, with: currentYYYYMM)
        }

        var highest = 0
        for title in seriesTitles + [source] {
            guard let occurrence = title.range(of: currentYYYYMM) else { continue }
            let after = title[occurrence.upperBound...]
            guard let match = trailingCountCapturePattern.firstMatch(
                in: String(after), range: NSRange(after.startIndex..., in: after)
            ), let numRange = Range(match.range(at: 1), in: after), let n = Int(after[numRange]) else { continue }
            highest = max(highest, n)
        }
        return source.replacingCharacters(in: replacedRange, with: "\(currentYYYYMM) (\(highest + 1))")
    }
}

extension Event: SeriesRecord {}
extension Transaction: SeriesRecord {}
