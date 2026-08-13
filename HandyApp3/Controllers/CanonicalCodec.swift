import Foundation

/// The single encoder/decoder pair for every on-disk store shard and every DTO comparison that
/// must agree with what's on disk — `StoreFileLayout`'s content-diff, the cloud monitor's echo
/// check, and `SnapshotReconciler`'s deterministic tie-break all depend on encoding the same
/// bytes for the same content. Never construct a second `JSONEncoder`/`JSONDecoder` for store
/// DTOs; drift between two encoders would silently break every one of those.
enum CanonicalCodec {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Truncates to whole seconds, which is what makes encode(decode(encode(x))) == encode(x)
        // hold — the idempotency the content-diff and the reconciler's byte tie-break both rest on.
        encoder.dateEncodingStrategy = .iso8601
        // Required for determinism: StoredValueDTO.composite encodes a Swift Dictionary whose
        // key order is randomized per process, so without sortedKeys any value carrying a
        // composite (e.g. the seeded 2D/3D Size types) would churn its digest on every launch.
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func encode<T: Encodable>(_ value: T) -> Data? {
        try? makeEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? makeDecoder().decode(type, from: data)
    }
}
