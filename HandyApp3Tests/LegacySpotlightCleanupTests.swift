import XCTest
@testable import HandyApp3

final class LegacySpotlightCleanupTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "LegacySpotlightCleanupTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDeletesOnlyLegacyAssetDomainAndRecordsCompletion() async {
        let index = FakeSpotlightIndex()
        let cleanup = LegacySpotlightCleanup(index: index, defaults: defaults)

        await cleanup.runIfNeeded()

        XCTAssertEqual(index.deletedDomains, [[LegacySpotlightCleanup.domainIdentifier]])
        XCTAssertTrue(defaults.bool(forKey: LegacySpotlightCleanup.completionKey))
    }

    func testSuccessfulCleanupDoesNotRepeat() async {
        let index = FakeSpotlightIndex()
        let cleanup = LegacySpotlightCleanup(index: index, defaults: defaults)

        await cleanup.runIfNeeded()
        await cleanup.runIfNeeded()

        XCTAssertEqual(index.deletedDomains.count, 1)
    }

    func testFailureIsNotRecordedAndRetries() async {
        let index = FakeSpotlightIndex(failuresRemaining: 1)
        let cleanup = LegacySpotlightCleanup(index: index, defaults: defaults)

        await cleanup.runIfNeeded()
        XCTAssertFalse(defaults.bool(forKey: LegacySpotlightCleanup.completionKey))

        await cleanup.runIfNeeded()
        XCTAssertEqual(index.deletedDomains.count, 2)
        XCTAssertTrue(defaults.bool(forKey: LegacySpotlightCleanup.completionKey))
    }
}

private final class FakeSpotlightIndex: SpotlightDomainDeleting {
    enum TestError: Error { case deletionFailed }

    private(set) var deletedDomains: [[String]] = []
    private var failuresRemaining: Int

    init(failuresRemaining: Int = 0) {
        self.failuresRemaining = failuresRemaining
    }

    func deleteSearchableItems(withDomainIdentifiers domainIdentifiers: [String]) async throws {
        deletedDomains.append(domainIdentifiers)
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw TestError.deletionFailed
        }
    }
}
