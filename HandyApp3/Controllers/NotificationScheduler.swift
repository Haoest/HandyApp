import Foundation
import UserNotifications

// MARK: - Pure planning layer

struct PlannedNotification: Equatable {
    let identifier: String
    /// Concrete occurrence moment (9:00 AM local), used for sorting and the global cap.
    let fireDate: Date
    /// What the calendar trigger matches on: year/month/day/hour=9/minute=0.
    let fireDateComponents: DateComponents
    let title: String
    let body: String
}

enum NotificationPlanner {
    static let identifierPrefix = "recurring-"

    /// Computes the full set of notifications that should be pending for the given
    /// assets. Pure: no UserNotifications side effects, deterministic for a fixed
    /// `now` and `calendar`.
    static func plan(
        for assets: [Asset],
        now: Date = Date(),
        calendar: Calendar = .current,
        perItemLimit: Int = 12,
        globalLimit: Int = 60
    ) -> [PlannedNotification] {
        // Record dates carry an arbitrary time-of-day, so filter occurrences at day
        // granularity (anything from today onward); makePlanned then drops the ones
        // whose 9 AM has already passed.
        let cutoff = calendar.startOfDay(for: now).addingTimeInterval(-1)
        var candidates: [PlannedNotification] = []
        for asset in assets {
            for event in asset.events {
                guard let recurrence = event.recurrence else { continue }
                for (index, date) in recurrence.occurrences(from: event.date, after: cutoff, count: perItemLimit, calendar: calendar) {
                    if let planned = makePlanned(
                        identifier: "\(identifierPrefix)event-\(event.id.uuidString)-\(index)",
                        occurrence: date, now: now, calendar: calendar,
                        title: asset.name, body: event.title
                    ) {
                        candidates.append(planned)
                    }
                }
            }
            for txn in asset.transactions {
                guard let recurrence = txn.recurrence else { continue }
                let amount = txn.amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
                let body = "\(txn.details) — \(amount) (\(txn.kind.rawValue))"
                for (index, date) in recurrence.occurrences(from: txn.date, after: cutoff, count: perItemLimit, calendar: calendar) {
                    if let planned = makePlanned(
                        identifier: "\(identifierPrefix)txn-\(txn.id.uuidString)-\(index)",
                        occurrence: date, now: now, calendar: calendar,
                        title: asset.name, body: body
                    ) {
                        candidates.append(planned)
                    }
                }
            }
        }
        let sorted = candidates.sorted {
            ($0.fireDate, $0.identifier) < ($1.fireDate, $1.identifier)
        }
        return Array(sorted.prefix(globalLimit))
    }

    private static func makePlanned(identifier: String, occurrence: Date, now: Date, calendar: Calendar, title: String, body: String) -> PlannedNotification? {
        var components = calendar.dateComponents([.year, .month, .day], from: occurrence)
        components.hour = 9
        components.minute = 0
        // An occurrence whose 9 AM has already passed (today, later in the day) is
        // unannounceable; the next cycle covers it.
        guard let fireDate = calendar.date(from: components), fireDate > now else { return nil }
        return PlannedNotification(identifier: identifier, fireDate: fireDate, fireDateComponents: components, title: title, body: body)
    }
}

// MARK: - UNUserNotificationCenter glue

final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var resyncTask: Task<Void, Never>?

    override init() {
        super.init()
        center.delegate = self
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

        // Always clear stale recurrence notifications, even when not authorized —
        // but never touch requests outside our prefix.
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(NotificationPlanner.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        for planned in plan {
            guard !Task.isCancelled else { return }
            let content = UNMutableNotificationContent()
            content.title = planned.title
            content.body = planned.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: planned.fireDateComponents, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: planned.identifier, content: content, trigger: trigger))
        }
    }

    /// iOS suppresses banners while the app is frontmost by default; show them anyway.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
