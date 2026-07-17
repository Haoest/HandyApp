import Foundation

// MARK: - Schema version

let storeSchemaVersion = 1

// MARK: - StoredValueDTO

indirect enum StoredValueDTO: Codable {
    case text(String)
    case number(Double)
    case currency(String)           // Decimal.description — preserves precision
    case date(Date)
    case contact(String)
    case composite([String: StoredValueDTO])
    case data(Data)
}

extension StoredValueDTO {
    private enum Tag: String, Codable { case text, number, currency, date, contact, composite, data }
    private enum CK: String, CodingKey { case tag, value }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CK.self)
        switch self {
        case .text(let v):      try c.encode(Tag.text,      forKey: .tag); try c.encode(v, forKey: .value)
        case .number(let v):    try c.encode(Tag.number,    forKey: .tag); try c.encode(v, forKey: .value)
        case .currency(let v):  try c.encode(Tag.currency,  forKey: .tag); try c.encode(v, forKey: .value)
        case .date(let v):      try c.encode(Tag.date,      forKey: .tag); try c.encode(v, forKey: .value)
        case .contact(let v):   try c.encode(Tag.contact,   forKey: .tag); try c.encode(v, forKey: .value)
        case .composite(let v): try c.encode(Tag.composite, forKey: .tag); try c.encode(v, forKey: .value)
        case .data(let v):      try c.encode(Tag.data,      forKey: .tag); try c.encode(v, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CK.self)
        switch try c.decode(Tag.self, forKey: .tag) {
        case .text:      self = .text(try c.decode(String.self,                        forKey: .value))
        case .number:    self = .number(try c.decode(Double.self,                      forKey: .value))
        case .currency:  self = .currency(try c.decode(String.self,                    forKey: .value))
        case .date:      self = .date(try c.decode(Date.self,                          forKey: .value))
        case .contact:   self = .contact(try c.decode(String.self,                     forKey: .value))
        case .composite: self = .composite(try c.decode([String: StoredValueDTO].self, forKey: .value))
        case .data:      self = .data(try c.decode(Data.self,                          forKey: .value))
        }
    }
}

// MARK: - PropertyTypeDTO

struct PropertyTypeDTO: Codable {
    enum Kind: String, Codable { case basic, composite, comboList }
    var kind: Kind
    var basicType: BasicType?   // populated when kind == .basic
    var typeID: UUID?           // populated when kind == .composite or .comboList
}

// MARK: - PropertyDefinitionDTO

struct PropertyDefinitionDTO: Codable {
    var id: UUID
    var name: String
    var type: PropertyTypeDTO
    var isRequired: Bool
}

// MARK: - AssetPropertyDTO

struct AssetPropertyDTO: Codable {
    var id: UUID
    var definition: PropertyDefinitionDTO
    var value: StoredValueDTO?
    var sortOrder: Double
}

// MARK: - CompositeTypeDTO

struct CompositeTypeDTO: Codable {
    var id: UUID
    var name: String
    var fields: [PropertyDefinitionDTO]
    var labelHint: String?
}

// MARK: - ComboListDTO

struct ComboListDTO: Codable {
    var id: UUID
    var name: String
    var systemOptions: [String]
    var userOptions: [String]
    var isUserExtensible: Bool
}

// MARK: - CategoryDTO

struct CategoryDTO: Codable {
    var id: UUID
    var name: String
    var iconName: String
    var propertyTemplates: [AssetPropertyDTO]
    var isDeleted: Bool
    var deletedAt: Date?
}

// MARK: - PhotoDTO
// Binary data is stored as separate files in Photos/; metadata is always present.
// fullImage/thumbnail are populated only in exports so imports on other devices can
// recreate the files — store.json itself never carries them (kept lean for sync).

struct PhotoDTO: Codable {
    var id: UUID
    var caption: String
    var addedDate: Date
    var fullImage: Data?
    var thumbnail: Data?
}

// MARK: - EventDTO

struct EventDTO: Codable {
    var id: UUID
    var title: String
    var date: Date
    var notes: String
    var recurrence: String?     // RecurrenceInterval.rawValue
}

// MARK: - TransactionDTO

struct TransactionDTO: Codable {
    var id: UUID
    var details: String
    var amount: String          // Decimal.description
    var date: Date
    var kind: String            // TransactionKind.rawValue
    var payeeContactID: String?
    var notes: String
    var recurrence: String?     // RecurrenceInterval.rawValue
}

// MARK: - AssetDTO

struct AssetDTO: Codable {
    var id: UUID
    var name: String
    var categoryID: UUID
    var baseProperties: [AssetPropertyDTO]
    var customProperties: [AssetPropertyDTO]
    var photos: [PhotoDTO]
    var events: [EventDTO]
    var transactions: [TransactionDTO]
    var parentID: UUID?
    var isDeleted: Bool
    var deletedAt: Date?
    var createdDate: Date
    var modifiedDate: Date
}

// MARK: - ActivityLogDTO

struct ActivityLogDTO: Codable {
    var id: UUID
    var recordID: UUID
    var kind: String            // LoggedRecordKind.rawValue
    var owningAssetID: UUID?
    var timestamp: Date
}

// MARK: - StoreSnapshotDTO

struct StoreSnapshotDTO: Codable {
    var schemaVersion: Int
    var compositeTypes: [CompositeTypeDTO]
    var comboLists: [ComboListDTO]
    var categories: [CategoryDTO]
    var assets: [AssetDTO]
    var activityLog: [ActivityLogDTO]
    var backgroundTheme: String     // BackgroundTheme.rawValue
}
