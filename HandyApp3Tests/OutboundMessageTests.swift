import XCTest
@testable import HandyApp3

final class OutboundMessageTests: XCTestCase {

    func testSMSBodyRoundTripsReservedCharactersAndUnicode() throws {
        let message = "Meet at 5? A&B #1 — 50% ✅\nSecond line"
        let url = try CommunicationURLBuilder.makeURL(
            method: .sms,
            destination: "+1 (212) 555-0123",
            message: message
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "sms")
        XCTAssertEqual(components.path, "+12125550123")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "body" })?.value, message)
        XCTAssertFalse(url.absoluteString.contains("?&body="))
    }

    func testEmailBodyRoundTripsWithoutEscapingItsQueryItem() throws {
        let message = "Cost: $20 & tax? #receipt"
        let url = try CommunicationURLBuilder.makeURL(
            method: .email,
            destination: " person@example.com ",
            message: message
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "mailto")
        XCTAssertEqual(components.path, "person@example.com")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "body" })?.value, message)
    }

    func testWhatsAppUsesDigitsWithoutLeadingPlus() throws {
        let url = try CommunicationURLBuilder.makeURL(
            method: .whatsapp,
            destination: "+44 20 7946 0958",
            message: "Hello & goodbye"
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "whatsapp")
        XCTAssertEqual(components.host, "send")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "phone" })?.value, "442079460958")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "text" })?.value, "Hello & goodbye")
    }

    func testInvalidDestinationsAreRejected() {
        XCTAssertThrowsError(try CommunicationURLBuilder.makeURL(method: .sms, destination: "ext", message: "Hi")) {
            XCTAssertEqual($0 as? CommunicationURLBuildError, .invalidDestination)
        }
        XCTAssertThrowsError(try CommunicationURLBuilder.makeURL(method: .email, destination: "  ", message: "Hi")) {
            XCTAssertEqual($0 as? CommunicationURLBuildError, .emptyDestination)
        }
        XCTAssertThrowsError(try CommunicationURLBuilder.makeURL(method: .email, destination: "a@example.com\nBcc:x@example.com", message: "Hi")) {
            XCTAssertEqual($0 as? CommunicationURLBuildError, .invalidDestination)
        }
    }

    func testQueueAdvancesOnceAndNeverWrapsToFirstRecipient() throws {
        let first = OutboundMessage(
            id: UUID(), recipientName: "Alex", method: .sms,
            url: try CommunicationURLBuilder.makeURL(method: .sms, destination: "123", message: "Hi")
        )
        let second = OutboundMessage(
            id: UUID(), recipientName: "Blair", method: .email,
            url: try CommunicationURLBuilder.makeURL(method: .email, destination: "b@example.com", message: "Hi")
        )
        var queue = OutboundMessageQueue(messages: [first, second])

        XCTAssertEqual(queue.current, first)
        XCTAssertTrue(queue.advance())
        XCTAssertEqual(queue.current, second)
        XCTAssertTrue(queue.advance())
        XCTAssertTrue(queue.isComplete)
        XCTAssertFalse(queue.advance())
        XCTAssertTrue(queue.isComplete)
    }
}
