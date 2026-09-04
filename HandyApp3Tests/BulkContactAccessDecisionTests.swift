import XCTest
@testable import HandyApp3

final class BulkContactAccessDecisionTests: XCTestCase {
    func testNoLinkedContactsNeverRequestsPermission() {
        for state in states {
            XCTAssertEqual(
                BulkContactAccessDecision.resolve(hasLinkedContacts: false, authorization: state),
                .noLinkedContacts
            )
        }
    }

    func testLinkedContactsMapAuthorizationToExpectedAction() {
        XCTAssertEqual(resolve(.notDetermined), .requestPermission)
        XCTAssertEqual(resolve(.allowed), .loadContacts)
        XCTAssertEqual(resolve(.denied), .denied)
        XCTAssertEqual(resolve(.restricted), .restricted)
        XCTAssertEqual(resolve(.unavailable), .unavailable)
    }

    private var states: [ContactAuthorizationState] {
        [.notDetermined, .allowed, .denied, .restricted, .unavailable]
    }

    private func resolve(_ state: ContactAuthorizationState) -> BulkContactAccessDecision {
        BulkContactAccessDecision.resolve(hasLinkedContacts: true, authorization: state)
    }
}
