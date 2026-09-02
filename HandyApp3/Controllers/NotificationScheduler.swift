import Foundation
import UserNotifications

// MARK: - Pure planning layer

/// Which section of the asset detail screen a tapped notification should jump to.
enum NotificationRecordKind: String {
    case event
    case transaction
}

struct PlannedNotification: Equatable {
    let identifier: String
    /// Concrete occurrence moment (9:00 AM local), used for sorting and the global cap.
    let fireDate: Date
    /// What the calendar trigger matches on: year/month/day/hour=9/minute=0.
    let fireDateComponents: DateComponents
    let title: String
    let body: String
    /// The asset the record is attached to; carried in the notification's userInfo
    /// so a tap can route to the asset's detail screen.
    let assetID: UUID
    /// Carried in the notification's userInfo so a tap can jump straight to the
    /// event/transaction section instead of just the asset's top.
    let kind: NotificationRecordKind
}

enum NotificationPlanner {
    /// No longer produced by `plan` — recurring-occurrence reminders were replaced by due-date
    /// notifications (see `dueCandidate`). Kept only so `apply`'s stale-request sweep still
    /// matches and clears any `recurring-*` requests a pre-existing install scheduled before
    /// this change; some run out as far as two years for `.biAnnually`. Do not remove until
    /// confident no install still has one pending.
    static let identifierPrefix = "recurring-"
    static let duePrefix = "due-"

    /// Computes the full set of notifications that should be pending for the given
    /// assets. Pure: no UserNotifications side effects, deterministic for a fixed
    /// `now` and `calendar`.
    static func plan(
        for assets: [Asset],
        now: Date = Date(),
        calendar: Calendar = .current,
        globalLimit: Int = 60
    ) -> [PlannedNotification] {
        var candidates: [PlannedNotification] = []
        for asset in assets {
            for event in asset.liveEvents {
                let body = eventDueBody(title: event.title, notes: event.notes, daysBefore: event.deviceNotificationDaysBefore)
                if let planned = dueCandidate(for: event, kindPrefix: "event", kind: .event, body: body, asset: asset, in: asset.liveEvents, now: now, calendar: calendar) {
                    candidates.append(planned)
                }
            }
            for txn in asset.liveTransactions {
                let body = transactionDueBody(kind: txn.kind, amount: txn.amount, notes: txn.notes, daysBefore: txn.deviceNotificationDaysBefore)
                if let planned = dueCandidate(for: txn, kindPrefix: "txn", kind: .transaction, body: body, asset: asset, in: asset.liveTransactions, now: now, calendar: calendar) {
                    candidates.append(planned)
                }
            }
        }
        let sorted = candidates.sorted {
            ($0.fireDate, $0.identifier) < ($1.fireDate, $1.identifier)
        }
        return Array(sorted.prefix(globalLimit))
    }

    /// Body for an event's due-date reminder. Also called directly by the edit screen's
    /// DEBUG "send test notification" button, so a test notification reads exactly like a
    /// real one.
    static func eventDueBody(title: String, notes: String, daysBefore: Int) -> String {
        let body = String(localized: "Due in \(daysBefore) days: \(title).", bundle: .appPreferred, locale: .appPreferred)
        return appendingNotes(body, notes: notes)
    }

    /// Body for a transaction's due-date reminder. Also called directly by the edit screen's
    /// DEBUG "send test notification" button, so a test notification reads exactly like a
    /// real one.
    static func transactionDueBody(kind: TransactionKind, amount: Decimal, notes: String, daysBefore: Int) -> String {
        let amountText = amount.formatted(
            .currency(code: Locale.current.currency?.identifier ?? "USD").locale(.appPreferred)
        )
        let body: String
        switch kind {
        case .expense:
            body = String(localized: "Expense transaction due in \(daysBefore) days in amount of \(amountText).", bundle: .appPreferred, locale: .appPreferred)
        case .income:
            body = String(localized: "Income transaction due in \(daysBefore) days in amount of \(amountText).", bundle: .appPreferred, locale: .appPreferred)
        }
        return appendingNotes(body, notes: notes)
    }

    private static func appendingNotes(_ prefix: String, notes: String) -> String {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? prefix : "\(prefix) \(trimmed)"
    }

    /// One-shot due-date reminder, `deviceNotificationDaysBefore` days ahead of `record`'s due
    /// date. Independent of recurrence — a non-recurring record can still carry one. Mirrors
    /// the home-tab due-message suppression rule so a logged newer occurrence also silences
    /// the pending device notification, not just the on-screen banner.
    private static func dueCandidate<R: SeriesRecord>(for record: R, kindPrefix: String, kind: NotificationRecordKind, body: String, asset: Asset, in siblings: [R], now: Date, calendar: Calendar) -> PlannedNotification? {
        guard record.deviceNotificationOn, let dueDate = record.dueDate,
              !SeriesLogic.isSuppressed(record, in: siblings, calendar: calendar, now: now) else { return nil }
        guard let occurrence = calendar.date(byAdding: .day, value: -record.deviceNotificationDaysBefore, to: dueDate) else { return nil }
        return makePlanned(
            identifier: "\(duePrefix)\(kindPrefix)-\(record.id.uuidString)",
            occurrence: occurrence, now: now, calendar: calendar,
            title: asset.name, body: body, assetID: asset.id, kind: kind
        )
    }

    private static func makePlanned(identifier: String, occurrence: Date, now: Date, calendar: Calendar, title: String, body: String, assetID: UUID, kind: NotificationRecordKind) -> PlannedNotification? {
        var dayComponents = calendar.dateComponents([.year, .month, .day], from: occurrence)
        dayComponents.hour = 9
        dayComponents.minute = 0
        if let nineAM = calendar.date(from: dayComponents), nineAM > now {
            return PlannedNotification(identifier: identifier, fireDate: nineAM, fireDateComponents: dayComponents, title: title, body: body, assetID: assetID, kind: kind)
        }
        // 9 AM on the trigger day has already passed, but the trigger moment itself — the
        // occurrence's own time of day — may still be ahead of now (it was computed as
        // dueDate - daysBefore, and dueDate carries an arbitrary wall-clock time). Deliver
        // then rather than dropping the reminder for the day entirely. Only ever engages on
        // the current day: for any future day, 9 AM is still in the future.
        let exact = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: occurrence)
        guard let exactDate = calendar.date(from: exact), exactDate > now else { return nil }
        return PlannedNotification(identifier: identifier, fireDate: exactDate, fireDateComponents: exact, title: title, body: body, assetID: assetID, kind: kind)
    }
}

// MARK: - UNUserNotificationCenter glue

final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var resyncTask: Task<Void, Never>?

    /// Called on the main actor with the asset ID and record kind when the user taps
    /// a notification. Wired up at app startup to route to the asset's detail screen,
    /// jumping to its Events/Transactions section. `kind` is nil for a notification
    /// scheduled before this field existed.
    var onOpenAsset: ((UUID, NotificationRecordKind?) -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    /// Fires a local notification a few seconds from now, bypassing all planning/dedup
    /// logic. Debug-build-only escape hatch so a developer can confirm notification delivery
    /// (banner, sound, permissions, tap routing) without waiting on a real due date to arrive.
    func fireDebugNotification(title: String, body: String, assetID: UUID, kind: NotificationRecordKind) {
        Task {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = ["assetID": assetID.uuidString, "kind": kind.rawValue]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "debug-test-\(UUID().uuidString)", content: content, trigger: trigger))
        }
    }

    /// Recomputes and replaces all recurrence notifications from the given snapshot.
    /// Planning happens synchronously on the caller's thread; only value types cross
    /// into the async task. Rapid successive calls coalesce: a new resync cancels the
    /// in-flight one, so only the latest plan is applied.
    func requestResync(assets: [Asset]) {
        let plan = NotificationPlanner.plan(for: assets)
        resyncTask?.cancel()
        resyncTask = Task { await self.apply(plan) }
    }

    private func apply(_ plan: [PlannedNotification]) async {
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined, !plan.isEmpty {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            settings = await center.notificationSettings()
        }
        guard !Task.isCancelled else { return }

        // Always clear stale recurrence/due notifications, even when not authorized —
        // but never touch requests outside our prefixes.
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter {
            $0.hasPrefix(NotificationPlanner.identifierPrefix) || $0.hasPrefix(NotificationPlanner.duePrefix)
        }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        for planned in plan {
            guard !Task.isCancelled else { return }
            let content = UNMutableNotificationContent()
            content.title = planned.title
            content.body = planned.body
            content.sound = .default
            content.userInfo = ["assetID": planned.assetID.uuidString, "kind": planned.kind.rawValue]
            let trigger = UNCalendarNotificationTrigger(dateMatching: planned.fireDateComponents, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: planned.identifier, content: content, trigger: trigger))
        }
    }

    // Both delegate methods use the completion-handler form, finishing on the main
    // queue. The async variants are a trap here: their generated thunk invokes the
    // system completion handler on a concurrency background thread, and UIKit's
    // snapshot/state-restoration work in that completion asserts main-thread-only
    // (SIGABRT on notification tap).

    /// iOS suppresses banners while the app is frontmost by default; show them anyway.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        DispatchQueue.main.async {
            completionHandler([.banner, .sound])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let assetID = (userInfo["assetID"] as? String).flatMap(UUID.init(uuidString:))
        let kind = (userInfo["kind"] as? String).flatMap(NotificationRecordKind.init(rawValue:))
        DispatchQueue.main.async {
            if let assetID { self.onOpenAsset?(assetID, kind) }
            completionHandler()
        }
    }
}
