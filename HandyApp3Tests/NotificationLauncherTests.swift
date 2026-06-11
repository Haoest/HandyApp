import XCTest
import UserNotifications
@testable import HandyApp3

/// Not a real test — a manually invoked launcher that schedules a visible device
/// notification 10 seconds out, for the first existing asset in a seeded store.
/// Gated behind the MANUAL_NOTIFICATION_TEST environment variable so normal suite
/// runs report it as skipped.
///
/// To run it:
///   xcodebuild test -project HandyApp3.xcodeproj -scheme HandyApp3 \
///     -destination 'platform=iOS Simulator,name=iPhone 16' \
///     -only-testing:HandyApp3Tests/NotificationLauncherTests \
///     TEST_RUNNER_MANUAL_NOTIFICATION_TEST=1
///
/// or in Xcode: Edit Scheme… → Test → Arguments → Environment Variables, add
/// MANUAL_NOTIFICATION_TEST = 1, then click the diamond next to the test method
/// (uncheck the variable again when done).
final class NotificationLauncherTests: XCTestCase {

    func testScheduleNotificationForExistingAssetInTenSeconds() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MANUAL_NOTIFICATION_TEST"] == "1",
            "Manual launcher — set MANUAL_NOTIFICATION_TEST=1 to run"
        )

        // Same seeding as app startup, then pick an existing asset.
        let store = AssetStore()
        store.seedBuiltInComboLists()
        store.seedBuiltInCategories()
        store.seedBuiltInTypes()
        store.seedBuiltInAssets()
        let asset = try XCTUnwrap(store.allAssets.first, "store has no seeded assets")

        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        try XCTSkipUnless(granted, "notification permission denied on this simulator")

        let content = UNMutableNotificationContent()
        content.title = asset.name
        content.body = "Manual test notification"
        content.sound = .default
        content.userInfo = ["assetID": asset.id.uuidString]

        // Deliberately NOT using the "recurring-" identifier prefix, so an app-side
        // resync can't clear this request before it fires.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        try await center.add(UNNotificationRequest(
            identifier: "manual-test-notification",
            content: content,
            trigger: trigger
        ))

        // The request is registered with the system on behalf of the host app, so it
        // fires ~10s from now even though the test runner exits first. Background or
        // close the simulator's frontmost app to see the banner.
    }
}
