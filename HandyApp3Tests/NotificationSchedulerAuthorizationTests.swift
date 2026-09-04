import XCTest
import UserNotifications
@testable import HandyApp3

final class NotificationSchedulerAuthorizationTests: XCTestCase {

    func testAutomaticResyncNeverRequestsUndeterminedAuthorization() async throws {
        let center = FakeNotificationCenter(status: .notDetermined)
        center.pending = [request(identifier: "due-old")]
        let scheduler = NotificationScheduler(center: center)

        scheduler.requestResync(assets: [try watchedAsset()])
        await scheduler.waitForPendingResync()

        XCTAssertEqual(center.authorizationRequestCount, 0)
        XCTAssertEqual(center.removedIdentifiers, ["due-old"])
        XCTAssertTrue(center.added.isEmpty)
    }

    func testExplicitRequestPromptsOnceAndReturnsAllowed() async {
        let center = FakeNotificationCenter(status: .notDetermined)
        center.statusAfterRequest = .authorized
        let scheduler = NotificationScheduler(center: center)

        let first = await scheduler.requestAuthorizationFromUser()
        let second = await scheduler.requestAuthorizationFromUser()
        XCTAssertEqual(first, .allowed)
        XCTAssertEqual(second, .allowed)
        XCTAssertEqual(center.authorizationRequestCount, 1)
    }

    func testDeniedResyncClearsOnlyBaronBookRequests() async throws {
        let center = FakeNotificationCenter(status: .denied)
        center.pending = [
            request(identifier: "due-event-old"),
            request(identifier: "recurring-txn-old"),
            request(identifier: "another-feature")
        ]
        let scheduler = NotificationScheduler(center: center)

        scheduler.requestResync(assets: [try watchedAsset()])
        await scheduler.waitForPendingResync()

        XCTAssertEqual(Set(center.removedIdentifiers), ["due-event-old", "recurring-txn-old"])
        XCTAssertTrue(center.added.isEmpty)
        XCTAssertEqual(center.authorizationRequestCount, 0)
    }

    func testAuthorizedResyncSchedulesPlannedRequest() async throws {
        let center = FakeNotificationCenter(status: .authorized)
        let scheduler = NotificationScheduler(center: center)
        let asset = try watchedAsset()

        scheduler.requestResync(assets: [asset])
        await scheduler.waitForPendingResync()

        XCTAssertEqual(center.authorizationRequestCount, 0)
        XCTAssertEqual(center.added.count, 1)
        XCTAssertTrue(center.added[0].identifier.hasPrefix("due-event-"))
        XCTAssertEqual(center.added[0].content.userInfo["assetID"] as? String, asset.id.uuidString)
    }

    private func watchedAsset() throws -> Asset {
        let category = AssetCategory(name: "Test", iconName: "folder")
        let asset = Asset(name: "Boiler", category: category)
        let dueDate = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        asset.events = [Event(
            title: "Service",
            date: Date(),
            dueDate: dueDate,
            deviceNotificationOn: true,
            deviceNotificationDaysBefore: 1
        )]
        return asset
    }

    private func request(identifier: String) -> UNNotificationRequest {
        UNNotificationRequest(
            identifier: identifier,
            content: UNMutableNotificationContent(),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        )
    }
}

private final class FakeNotificationCenter: UserNotificationCenterClient {
    weak var delegate: UNUserNotificationCenterDelegate?
    var status: UNAuthorizationStatus
    var statusAfterRequest: UNAuthorizationStatus?
    var authorizationRequestCount = 0
    var pending: [UNNotificationRequest] = []
    var removedIdentifiers: [String] = []
    var added: [UNNotificationRequest] = []

    init(status: UNAuthorizationStatus) {
        self.status = status
    }

    func currentAuthorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationRequestCount += 1
        if let statusAfterRequest { status = statusAfterRequest }
        return status == .authorized || status == .provisional
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] { pending }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
    }

    func add(_ request: UNNotificationRequest) async throws {
        added.append(request)
    }
}
