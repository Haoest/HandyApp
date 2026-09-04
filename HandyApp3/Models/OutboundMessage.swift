import Foundation

enum ContactMethod: String, CaseIterable, Identifiable {
    case sms, email, whatsapp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sms: return "SMS"
        case .email: return "Email"
        case .whatsapp: return "WhatsApp"
        }
    }
}

enum CommunicationURLBuildError: Error, Equatable {
    case emptyDestination
    case invalidDestination
    case couldNotConstructURL
}

/// Builds composer URLs without ever treating message text as an already-safe query fragment.
/// URLComponents owns all percent encoding, so reserved delimiters cannot escape the body value.
enum CommunicationURLBuilder {
    static func makeURL(method: ContactMethod, destination: String, message: String) throws -> URL {
        switch method {
        case .sms:
            let phone = try normalizedPhone(destination)
            var components = URLComponents()
            components.scheme = "sms"
            components.path = phone
            components.queryItems = [URLQueryItem(name: "body", value: message)]
            return try url(from: components)

        case .email:
            let address = destination.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else { throw CommunicationURLBuildError.emptyDestination }
            guard !address.contains(where: { $0.isNewline }) else {
                throw CommunicationURLBuildError.invalidDestination
            }
            var components = URLComponents()
            components.scheme = "mailto"
            components.path = address
            components.queryItems = [URLQueryItem(name: "body", value: message)]
            return try url(from: components)

        case .whatsapp:
            // WhatsApp's `phone` query expects an international number without punctuation or
            // a leading plus. SMS retains the plus because it is part of the destination path.
            let phone = try normalizedPhone(destination).removingLeadingPlus()
            var components = URLComponents()
            components.scheme = "whatsapp"
            components.host = "send"
            components.queryItems = [
                URLQueryItem(name: "phone", value: phone),
                URLQueryItem(name: "text", value: message)
            ]
            return try url(from: components)
        }
    }

    static func normalizedPhone(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CommunicationURLBuildError.emptyDestination }
        let hasLeadingPlus = trimmed.first == "+"
        let digits = trimmed.filter(\.isNumber)
        guard !digits.isEmpty else { throw CommunicationURLBuildError.invalidDestination }
        return (hasLeadingPlus ? "+" : "") + digits
    }

    private static func url(from components: URLComponents) throws -> URL {
        guard let url = components.url else { throw CommunicationURLBuildError.couldNotConstructURL }
        return url
    }
}

struct OutboundMessage: Identifiable, Equatable {
    let id: UUID
    let recipientName: String
    let method: ContactMethod
    let url: URL
}

/// Immutable messages plus a single cursor. SwiftUI can redraw freely without rebuilding the
/// recipients or returning to the first message.
struct OutboundMessageQueue: Equatable {
    let messages: [OutboundMessage]
    private(set) var currentIndex = 0

    init(messages: [OutboundMessage]) {
        self.messages = messages
    }

    var current: OutboundMessage? {
        messages.indices.contains(currentIndex) ? messages[currentIndex] : nil
    }

    var isComplete: Bool { current == nil }

    @discardableResult
    mutating func advance() -> Bool {
        guard current != nil else { return false }
        currentIndex += 1
        return true
    }
}

private extension String {
    func removingLeadingPlus() -> String {
        first == "+" ? String(dropFirst()) : self
    }
}
