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

    private init() {}

    // MARK: - Permission

    /// Requests Contacts access if not already granted.
    /// Call once at app launch before any fetch.
    func requestAccess() async throws {
        try await store.requestAccess(for: .contacts)
    }

    var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
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
        ]
        return try store.unifiedContact(withIdentifier: identifier, keysToFetch: keys)
    }

    /// Convenience: display name for a contact identifier, or `nil` if unresolvable.
    func displayName(for identifier: String) -> String? {
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
