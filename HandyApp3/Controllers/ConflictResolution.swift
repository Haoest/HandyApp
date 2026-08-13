import Foundation
import os

private let conflictLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HandyApp3", category: "Persistence")

/// Abstraction over `NSFileVersion` so conflict *resolution logic* is testable — a real
/// `NSFileVersion` conflict can't be fabricated in a unit test, but a test double conforming to
/// this can supply fake conflicting byte contents and let a test assert the merge-then-resolve
/// behavior end to end. `FileVersionConflictSource` is the only production conformer.
protocol ConflictSource {
    /// Relative paths (e.g. "Definitions/categories.json", "Assets/<uuid>.json") under
    /// `baseDir` that currently have one or more unresolved conflict versions.
    func conflictedPaths(baseDir: URL) -> [String]
    /// Byte contents of every unresolved conflict version at the given absolute URL — NOT
    /// including the current on-disk version, which the caller reads separately.
    func conflictingContents(at url: URL) -> [Data]
    /// Marks every conflict version at the given URL resolved and discards them.
    func resolve(at url: URL)
}

struct FileVersionConflictSource: ConflictSource {
    func conflictedPaths(baseDir: URL) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: baseDir, includingPropertiesForKeys: nil) else { return [] }
        var prefix = baseDir.path
        if !prefix.hasSuffix("/") { prefix += "/" }
        var paths: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "json" {
            if let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !conflicts.isEmpty {
                paths.append(String(url.path.dropFirst(prefix.count)))
            }
        }
        return paths
    }

    func conflictingContents(at url: URL) -> [Data] {
        (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).compactMap { try? Data(contentsOf: $0.url) }
    }

    func resolve(at url: URL) {
        for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] {
            version.isResolved = true
        }
        try? NSFileVersion.removeOtherVersionsOfItem(at: url)
    }
}

/// Decodes the current bytes and every conflicting version for a shard, folds them through the
/// matching `SnapshotReconciler` join, and re-encodes. Pure — no file I/O, no `NSFileVersion`,
/// directly unit-testable with hand-built byte blobs.
enum ShardConflictMerger {
    static func mergeShardBytes(relativePath: String, current: Data, conflicts: [Data]) -> Data? {
        let decoder = CanonicalCodec.makeDecoder()
        let encoder = CanonicalCodec.makeEncoder()

        func foldArray<T: Codable>(id: @escaping (T) -> UUID, join: @escaping (T, T) -> T) -> Data? {
            guard let currentValue = try? decoder.decode([T].self, from: current) else { return nil }
            let merged = conflicts
                .compactMap { try? decoder.decode([T].self, from: $0) }
                .reduce(currentValue) { acc, next in SnapshotReconciler.joinKeyed(acc, next, id: id, join: join) }
            return try? encoder.encode(merged)
        }

        func foldSingle<T: Codable>(join: @escaping (T, T) -> T) -> Data? {
            guard let currentValue = try? decoder.decode(T.self, from: current) else { return nil }
            let merged = conflicts
                .compactMap { try? decoder.decode(T.self, from: $0) }
                .reduce(currentValue, join)
            return try? encoder.encode(merged)
        }

        switch relativePath {
        case "Definitions/types.json":
            return foldArray(id: { (v: CompositeTypeDTO) in v.id }, join: SnapshotReconciler.joinCompositeType)
        case "Definitions/combolists.json":
            return foldArray(id: { (v: ComboListDTO) in v.id }, join: SnapshotReconciler.joinComboList)
        case "Definitions/categories.json":
            return foldArray(id: { (v: CategoryDTO) in v.id }, join: SnapshotReconciler.joinCategory)
        case "Activity/log.json":
            // Immutable records — union by id is all that's needed; either side of a
            // collision is byte-identical, so the join can just keep the current value.
            return foldArray(id: { (v: ActivityLogDTO) in v.id }, join: { a, _ in a })
        case "store.json":
            // layoutVersion/schemaVersion: never regress. backgroundTheme is a per-device
            // field moved out of the manifest entirely once iCloud sync is on — current wins,
            // it's never read as authoritative once that migration lands.
            return foldSingle(join: { (a: StoreManifestDTO, b: StoreManifestDTO) -> StoreManifestDTO in
                StoreManifestDTO(layoutVersion: max(a.layoutVersion, b.layoutVersion),
                                 schemaVersion: max(a.schemaVersion, b.schemaVersion),
                                 backgroundTheme: a.backgroundTheme)
            })
        default:
            guard relativePath.hasPrefix("Assets/"), relativePath.hasSuffix(".json") else { return nil }
            return foldSingle(join: { (a: AssetDTO, b: AssetDTO) in SnapshotReconciler.joinAsset(a, b) })
        }
    }
}

extension AssetStore {
    /// Resolves conflicts across every shard, not just the manifest: decodes the current file
    /// and every conflicting version, folds them through the matching `SnapshotReconciler`
    /// join — the same merge logic pinned by `SnapshotReconcilerTests` — writes the merged
    /// result, then marks the conflicts resolved. Never resolved before a successful
    /// merge+write: a version that fails to decode stays a live conflict rather than being
    /// silently discarded, unlike a bare `removeOtherVersionsOfItem` call, which would drop
    /// the losing version unread.
    ///
    /// Writes go straight to disk, bypassing `StoreFileLayout`'s digest cache entirely —
    /// `StoreFileLayout.readLocked` rebuilds that cache from scratch on every read, so a file
    /// changed by conflict resolution is picked up correctly on the next read with no
    /// coordination needed here.
    func resolveShardConflicts(baseDir: URL, source: ConflictSource) {
        for relativePath in source.conflictedPaths(baseDir: baseDir) {
            let url = baseDir.appendingPathComponent(relativePath)
            guard let currentBytes = try? Data(contentsOf: url) else { continue }
            let conflictingBytes = source.conflictingContents(at: url)
            guard !conflictingBytes.isEmpty,
                  let mergedBytes = ShardConflictMerger.mergeShardBytes(
                    relativePath: relativePath, current: currentBytes, conflicts: conflictingBytes)
            else { continue }
            do {
                try mergedBytes.write(to: url, options: .atomic)
                source.resolve(at: url)
            } catch {
                conflictLogger.error("resolveShardConflicts: failed to write merged shard \(relativePath, privacy: .public)")
            }
        }
    }
}
