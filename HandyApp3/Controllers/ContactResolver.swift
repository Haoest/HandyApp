import Contacts

// MARK: - ContactResolver

/// Resolves a CNContact.identifier (stored in a `.contact` StoredValue)
/// back to a live CNContact object.
///
/// This is the **only** file in the domain layer that imports Contacts —
/// the rest of the model stays framework-free and fully testable without device permissions.
final class ContactResolver {

    static let shared = ContactResolver()
    private let store = CNContactStore()

    /// Memoized `displayName(for:)` results, including misses (a `nil` value means "looked up,
    /// not found"). Each miss-free lookup is a cross-process query into the Contacts database,
    /// and views call this from `body` — the asset detail form re-evaluates on every store
    /// mutation and on every frame of the keyboard animation, so an uncached fetch there shows
    /// up directly as input lag. Invalidated wholesale whenever Contacts reports a change.
    private var nameCache: [String: String?] = [:]

    private init() {
        NotificationCenter.default.addObserver(
            forName: .CNContactStoreDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.nameCache.removeAll()
        }
    }

    // MARK: - Permission

    /// Requests Contacts access if not already decided and returns whether contact data is
    /// available. Call only in response to a user action that needs Contacts; passive contact
    /// labels deliberately use the non-prompting fetch helpers below.
    @discardableResult
    func requestAccess() async throws -> Bool {
        if hasAccess { return true }
        _ = try await store.requestAccess(for: .contacts)
        return hasAccess
    }

    var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    /// Limited access is sufficient: the app only needs to resolve contacts the user chose.
    private var hasAccess: Bool {
        #if os(iOS)
        authorizationStatus == .authorized || authorizationStatus == .limited
        #else
        // CNAuthorizationStatus.limited is unavailable on macOS. The app itself is iOS-only,
        // but the Foundation logic target is compiled on macOS by the SwiftPM test harness.
        authorizationStatus == .authorized
        #endif
    }

    // MARK: - Fetch

    /// Returns the CNContact for a given identifier, or `nil` if not found / no permission.
    func contact(for identifier: String) throws -> CNContact? {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactInstantMessageAddressesKey as CNKeyDescriptor,
        ]
        return try store.unifiedContact(withIdentifier: identifier, keysToFetch: keys)
    }

    /// Convenience: display name for a contact identifier, or `nil` if unresolvable.
    ///
    /// Cached — see `nameCache`. Safe to call from a view body.
    func displayName(for identifier: String) -> String? {
        if let cached = nameCache[identifier] { return cached }
        let name = fetchDisplayName(for: identifier)
        nameCache[identifier] = name
        return name
    }

    private func fetchDisplayName(for identifier: String) -> String? {
        guard let c = try? contact(for: identifier) else { return nil }
        let full = [c.givenName, c.familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return full.isEmpty ? c.organizationName.isEmpty ? nil : c.organizationName : full
    }

    // MARK: - Search

    /// Returns contacts whose name contains the given string (case-insensitive).
    func searchContacts(matching query: String) throws -> [CNContact] {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
        ]
        let predicate = CNContact.predicateForContacts(matchingName: query)
        return try store.unifiedContacts(matching: predicate, keysToFetch: keys)
    }
}

// MARK: - AssetStore helpers

extension AssetStore {

    /// Returns the CNContact identifier stored in a `.contact` StoredValue, if present.
    func contactIdentifier(forDefinitionID definitionID: UUID, onAssetID assetID: UUID) -> String? {
        guard let asset = assets[assetID],
              case .contact(let identifier) = asset.value(for: definitionID)
        else { return nil }
        return identifier
    }

    /// Resolves the stored contact identifier to a live CNContact, if possible.
    func resolvedContact(forDefinitionID definitionID: UUID, onAssetID assetID: UUID) -> CNContact? {
        guard let identifier = contactIdentifier(forDefinitionID: definitionID, onAssetID: assetID) else { return nil }
        return try? ContactResolver.shared.contact(for: identifier)
    }
}
