import Foundation

// MARK: - Schema version

let storeSchemaVersion = 4

/// File layout version, independent of `storeSchemaVersion` (which versions the DTO shapes).
/// Bump this when the on-disk file/directory structure changes, not when a DTO field is added.
let storeLayoutVersion = 1

// MARK: - StoreManifestDTO

/// Root of the multi-file layout: `store.json` decodes as this once a store has been migrated.
/// `layoutVersion` is non-optional specifically so decoding this type is what disambiguates a
/// manifest from a legacy single-file `StoreSnapshotDTO` (which has no such field).
struct StoreManifestDTO: Codable {
    var layoutVersion: Int
    var schemaVersion: Int
    var backgroundTheme: String     // BackgroundTheme.rawValue
}

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
    /// Optional: absent in files written before per-property timestamps existed.
    /// Decoders substitute the owning record's date — see `assetProperty(from:)`.
    var modifyDate: Date?
    /// Optional: absent in files written before custom properties carried tombstones.
    var isDeleted: Bool?
    var deletedAt: Date?
}

// MARK: - CompositeTypeDTO

struct CompositeTypeDTO: Codable {
    var id: UUID
    var name: String
    var fields: [PropertyDefinitionDTO]
    var labelHint: String?
    /// Optional: absent in files written before composite types carried a timestamp.
    /// Decoders substitute `.distantPast`.
    var modifyDate: Date?
}

// MARK: - ComboListDTO

struct ComboListDTO: Codable {
    var id: UUID
    var name: String
    var systemOptions: [String]
    var userOptions: [String]
    var isUserExtensible: Bool
    /// Optional: absent in files written before combo lists carried a timestamp.
    /// Decoders substitute `.distantPast`.
    var modifyDate: Date?
}

// MARK: - CategoryDTO

struct CategoryDTO: Codable {
    var id: UUID
    var name: String
    var iconName: String
    var propertyTemplates: [AssetPropertyDTO]
    var isDeleted: Bool
    var deletedAt: Date?
    /// Optional: absent in files written before categories carried a timestamp.
    /// Decoders substitute `.distantPast`.
    var modifyDate: Date?
    /// Optional: absent in files written before purge stopped removing the category record.
    /// Decoders fall back to `false`. See `AssetCategory.isPurged`. Defaulted to `nil` so every
    /// existing `CategoryDTO(...)` construction site keeps compiling unchanged.
    var isPurged: Bool? = nil
    /// Optional: absent in files written before the purge instant was recorded separately from
    /// the delete decision. See `AssetCategory.purgedAt`. Defaulted to `nil` so every existing
    /// `CategoryDTO(...)` construction site keeps compiling unchanged, and so a record purged
    /// before this field existed decodes as permanently unrefusable (`nil` reads as
    /// `.distantFuture` wherever `SnapshotReconciler` compares against it).
    var purgedAt: Date? = nil
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
    /// Optional: absent in files written before inline records carried tombstones.
    /// Decoders substitute — see `photo(from:)`.
    var modifyDate: Date?
    var isDeleted: Bool?
    var deletedAt: Date?
}

// MARK: - EventDTO

struct EventDTO: Codable {
    var id: UUID
    var title: String
    var date: Date
    var notes: String
    var recurrence: String?     // RecurrenceInterval.rawValue
    /// Optional: absent in files written before inline records carried tombstones.
    /// `modifyDate` falls back to the owning asset's `modifiedDate` — `date` is the event's
    /// scheduled day and may be in the future, so it is not a record timestamp.
    /// Decoders substitute — see `event(from:fallbackModifyDate:)`.
    var modifyDate: Date?
    var isDeleted: Bool?
    var deletedAt: Date?
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
    /// Optional: absent in files written before inline records carried tombstones.
    /// `modifyDate` falls back to the owning asset's `modifiedDate` — `date` is the
    /// transaction's occurrence day, not a record timestamp.
    /// Decoders substitute — see `transaction(from:fallbackModifyDate:)`.
    var modifyDate: Date?
    var isDeleted: Bool?
    var deletedAt: Date?
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
    /// Optional: absent in files written before parentage changes were timestamped.
    /// Decoders fall back to `createdDate`.
    var parentageModifyDate: Date?
    /// Optional: absent in files written before the asset's own name/tombstone carried a
    /// separate timestamp from the `modifiedDate` rollup. Decoders fall back to
    /// `modifiedDate` — see `Asset.headModifyDate`'s doc comment for why the two differ.
    var headModifyDate: Date?
    /// Optional: absent in files written before purge stopped removing the asset record.
    /// Decoders fall back to `false`. See `Asset.isPurged`. Defaulted to `nil` so every
    /// existing `AssetDTO(...)` construction site keeps compiling unchanged.
    var isPurged: Bool? = nil
    /// Optional: absent in files written before the purge instant was recorded separately from
    /// the delete decision. See `Asset.purgedAt`. Defaulted to `nil` so every existing
    /// `AssetDTO(...)` construction site keeps compiling unchanged, and so a record purged
    /// before this field existed decodes as permanently unrefusable (`nil` reads as
    /// `.distantFuture` wherever `SnapshotReconciler` compares against it).
    var purgedAt: Date? = nil
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

// MARK: - Canonicalization
//
// Nested-array ordering that must hold regardless of how a snapshot was assembled — from live
// model state (`AssetStore.buildSnapshot`) or from a merge (`SnapshotReconciler`) — so the
// encoded bytes are a pure function of content, never of construction order. Without this,
// `merge(a,b)` and `merge(b,a)` (built from dictionary key-set unions, which have no defined
// iteration order in Swift) would encode the same records in different array order, hence
// different bytes, hence an endless re-upload cycle between two devices that agree on content
// but disagree on encoding. `StoreFileLayout.writeLocked` canonicalizes before every write, so
// on-disk files are always canonical no matter what produced the in-memory snapshot.
//
// Every display site already re-sorts for its own UI order — `AssetPhotosViews` by
// `addedDate`, `AssetEventsViews`/`AssetTransactionsViews` by `recurringFirstDateDescending()`,
// `AssetDetailView.sortedBase/sortedCustom` by `sortOrder` — so on-disk order is invisible to
// the UI. `CompositeTypeDTO.fields` and `ComboListDTO.userOptions` are deliberately NOT
// reordered here: field order is a semantic display order preserved by whole-record
// last-writer-wins in the reconciler, and `userOptions`' merge order is constructed
// deterministically by the reconciler itself (winner's array, then the loser's missing
// options), not by sorting.

extension AssetPropertyDTO {
    /// `(sortOrder, id)` — matches the app's own display order for property rows.
    fileprivate static func canonicalOrder(_ a: AssetPropertyDTO, _ b: AssetPropertyDTO) -> Bool {
        a.sortOrder == b.sortOrder ? a.id.uuidString < b.id.uuidString : a.sortOrder < b.sortOrder
    }
}

extension AssetDTO {
    func canonicalized() -> AssetDTO {
        var copy = self
        copy.baseProperties = baseProperties.sorted(by: AssetPropertyDTO.canonicalOrder)
        copy.customProperties = customProperties.sorted(by: AssetPropertyDTO.canonicalOrder)
        copy.photos = photos.sorted {
            $0.addedDate == $1.addedDate ? $0.id.uuidString < $1.id.uuidString : $0.addedDate < $1.addedDate
        }
        copy.events = events.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
        }
        copy.transactions = transactions.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
        }
        return copy
    }
}

extension CategoryDTO {
    func canonicalized() -> CategoryDTO {
        var copy = self
        copy.propertyTemplates = propertyTemplates.sorted(by: AssetPropertyDTO.canonicalOrder)
        return copy
    }
}

extension StoreSnapshotDTO {
    /// Full canonicalization: every top-level collection sorted by id (or `(timestamp, id)`
    /// for the log), every nested collection sorted per the rules above. Two snapshots with
    /// identical content, assembled in any order, encode to identical bytes after this.
    func canonicalized() -> StoreSnapshotDTO {
        var copy = self
        copy.compositeTypes = compositeTypes.sorted { $0.id.uuidString < $1.id.uuidString }
        copy.comboLists = comboLists.sorted { $0.id.uuidString < $1.id.uuidString }
        copy.categories = categories.map { $0.canonicalized() }.sorted { $0.id.uuidString < $1.id.uuidString }
        copy.assets = assets.map { $0.canonicalized() }.sorted { $0.id.uuidString < $1.id.uuidString }
        copy.activityLog = activityLog.sorted {
            $0.timestamp == $1.timestamp ? $0.id.uuidString < $1.id.uuidString : $0.timestamp < $1.timestamp
        }
        return copy
    }
}
