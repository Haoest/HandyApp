import Foundation
import CryptoKit
import os

/// Shards a `StoreSnapshotDTO` across many files on disk and reassembles one on read.
/// `AssetStore+Persistence.swift` still owns `applySnapshot`/`mergeSnapshot`/`buildSnapshot` —
/// this type only knows how to turn one snapshot into files and back, so every merge and
/// migration rule above the snapshot boundary is untouched by the multi-file layout.
///
/// On-disk shape:
/// ```
/// store.json                    StoreManifestDTO { layoutVersion, schemaVersion, backgroundTheme }
/// Definitions/types.json        [CompositeTypeDTO]   sorted by id.uuidString
/// Definitions/combolists.json   [ComboListDTO]        sorted by id.uuidString
/// Definitions/categories.json   [CategoryDTO]         sorted by id.uuidString
/// Assets/<uuid>.json            one AssetDTO
/// Activity/log.json             [ActivityLogDTO]      sorted by (timestamp, id.uuidString);
///                                read side globs Activity/*.json so monthly shards can be
///                                added later as a write-path-only change.
/// ```
///
/// Failure policy — the part that must not be got wrong. Sharding turns "decode failed, so
/// `load()` loudly returns false" into "load silently succeeds with a hole, and the next save
/// makes the hole permanent." Three rules prevent that:
/// 1. Definitions/categories are structural: every asset's `PropertyType.composite`/`.comboList`
///    only persists a `typeID`, resolved via `compactMap` in `applySnapshot` — a missing
///    `types.json` would silently drop every composite/comboList property from every asset. A
///    missing shard there fails the whole read rather than returning a partial snapshot.
/// 2. One bad asset file must not sink the store: it's skipped and flagged, and that flag
///    suppresses the orphan sweep on the next write so an unreadable-this-once (or
///    not-yet-downloaded, under sync) file is never mistaken for a deleted one.
/// 3. `store.json` is not load-bearing for existence: if it's missing but `Definitions/`/`Assets/`
///    are present, that still counts as a store, reconstructed with default manifest values —
///    otherwise a missing manifest reads as "no store" and the next write's orphan sweep would
///    erase every real asset file.
final class StoreFileLayout {

    /// Name of the one-time backup taken of a legacy single-file store before it's migrated to
    /// the multi-file layout — insurance against a crashed/partial migration losing the only
    /// copy. Versioned by `storeSchemaVersion` (the DTO shape being backed up), not
    /// `storeLayoutVersion` (which describes what it's being migrated *to*).
    static var legacyBackupFilename: String { "store.legacy-v\(storeSchemaVersion).json" }

    struct ReadResult {
        var snapshot: StoreSnapshotDTO
        var wasMigratedFromLegacy: Bool
        /// False when at least one asset file existed but couldn't be read/decoded. The caller
        /// still gets everything that *did* decode — but the next `write` must not sweep the
        /// files this read couldn't verify, since "couldn't verify" and "doesn't exist" are not
        /// the same thing.
        var isComplete: Bool
    }

    struct WriteReport {
        var writtenPaths: [String] = []
        var deletedPaths: [String] = []
        var skippedCount: Int = 0
        var allDataShardsSucceeded: Bool = true
    }

    /// Canonical whole-store identity: SHA-256 over the sorted (relative path, SHA-256(bytes))
    /// pairs of every shard. Stands in for `lastPersistedData` now that there's no single set of
    /// bytes to compare — both `read` and `write` compute it identically from disk contents, so
    /// the cloud-monitor echo check in `handleCloudMonitorNotification` keeps working unchanged.
    private(set) var storeDigest: Data?

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "HandyApp3", category: "Persistence"
    )

    /// Serializes every read and write. `save()` can fire concurrently from the debounced task,
    /// scene-phase transitions, and launch/import/reset paths; with one file that was benign
    /// (one atomic write, last writer wins), but with N files two interleaved writers could tear
    /// the directory and would race the digest cache below.
    private let queue = DispatchQueue(label: "StoreFileLayout.write")

    /// Relative path → SHA-256 of the bytes last known to be on disk at that path. Seeded by
    /// `read` and kept current by `write`; touched only on `queue`. Digests, not bytes — bytes
    /// would keep a second full copy of the store resident for the process lifetime.
    private var digests: [String: Data] = [:]
    private var digestsBaseDir: URL?

    /// See `ReadResult.isComplete`. Starts `true` so a layout instance that has never read
    /// anything (a fresh install, or a factoryReset on a store that was already cleanly loaded)
    /// still permits the orphan sweep — there's nothing yet it failed to verify. Only a `read`
    /// that detects a hole sets it `false`, and only another clean `read` clears it again;
    /// `write` never touches it; it doesn't re-examine files it didn't write.
    private var lastReadWasComplete = true

    private enum Shard: Equatable {
        case manifest
        case types
        case comboLists
        case categories
        case asset(UUID)
        case activityLog

        var relativePath: String {
            switch self {
            case .manifest:          return "store.json"
            case .types:              return "Definitions/types.json"
            case .comboLists:         return "Definitions/combolists.json"
            case .categories:         return "Definitions/categories.json"
            case .asset(let id):      return "Assets/\(id.uuidString).json"
            case .activityLog:        return "Activity/log.json"
            }
        }
    }

    // MARK: - Codec

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Truncates to whole seconds, which is what makes encode(decode(encode(x))) == encode(x)
        // hold — the idempotency the whole content-diff rests on. Don't switch to a
        // sub-second strategy without re-checking that property.
        encoder.dateEncodingStrategy = .iso8601
        // Required for determinism, including on asset files: StoredValueDTO.composite encodes
        // a Swift Dictionary whose key order is randomized per process, so without sortedKeys
        // any asset carrying a composite value (e.g. the seeded 2D/3D Size types) would churn
        // its digest — and get rewritten — on every launch.
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    // MARK: - Read

    func read(baseDir: URL) -> ReadResult? {
        queue.sync { readLocked(baseDir: baseDir) }
    }

    private func readLocked(baseDir: URL) -> ReadResult? {
        resetDigestCacheIfBaseDirChanged(baseDir)
        let fm = FileManager.default
        let manifestPath = Shard.manifest.relativePath
        let manifestURL = baseDir.appendingPathComponent(manifestPath)
        let manifestBytes = try? Data(contentsOf: manifestURL)

        // A manifest decode is the normal, hot-path outcome; a legacy single-file snapshot is
        // the fallback. The two DTOs have disjoint required keys (layoutVersion vs.
        // compositeTypes/assets/…), so trying either order is unambiguous — this order just
        // favors the common case.
        let manifest = manifestBytes.flatMap { try? Self.makeDecoder().decode(StoreManifestDTO.self, from: $0) }
        if manifest == nil, let bytes = manifestBytes,
           let legacy = try? Self.makeDecoder().decode(StoreSnapshotDTO.self, from: bytes) {
            lastReadWasComplete = true
            // Insurance against a crashed/partial migration: back up the legacy file before the
            // caller's next write overwrites store.json with the manifest. Idempotent — never
            // clobbers a backup already taken by an earlier, interrupted migration attempt.
            let backupURL = baseDir.appendingPathComponent(Self.legacyBackupFilename)
            if !fm.fileExists(atPath: backupURL.path) {
                try? bytes.write(to: backupURL, options: .atomic)
            }
            seedDigest(path: manifestPath, bytes: bytes)
            recomputeStoreDigest()
            return ReadResult(snapshot: legacy, wasMigratedFromLegacy: true, isComplete: true)
        }

        let definitionsDir = baseDir.appendingPathComponent("Definitions", isDirectory: true)
        let assetsDir = baseDir.appendingPathComponent("Assets", isDirectory: true)
        let activityDir = baseDir.appendingPathComponent("Activity", isDirectory: true)
        let treeExists = fm.fileExists(atPath: definitionsDir.path)
            || fm.fileExists(atPath: assetsDir.path)
            || fm.fileExists(atPath: activityDir.path)

        // Neither a manifest nor any shard directory exists: a genuinely fresh install, not a
        // failure. Leave lastReadWasComplete untouched (still true) — there's nothing here to
        // have failed to verify.
        guard manifest != nil || treeExists else { return nil }

        guard
            let (types, typesBytes) = readShard(baseDir: baseDir, shard: .types, as: [CompositeTypeDTO].self),
            let (comboLists, comboBytes) = readShard(baseDir: baseDir, shard: .comboLists, as: [ComboListDTO].self),
            let (categories, categoriesBytes) = readShard(baseDir: baseDir, shard: .categories, as: [CategoryDTO].self)
        else {
            lastReadWasComplete = false
            Self.logger.error("read: a Definitions shard is missing or undecodable — treating as no store rather than persisting a partial one")
            return nil
        }
        seedDigest(path: Shard.types.relativePath, bytes: typesBytes)
        seedDigest(path: Shard.comboLists.relativePath, bytes: comboBytes)
        seedDigest(path: Shard.categories.relativePath, bytes: categoriesBytes)
        if let manifestBytes { seedDigest(path: manifestPath, bytes: manifestBytes) }

        // One bad asset file must not sink the store — skip and flag, never silently drop the
        // rest. seen/decoded tracks whether every asset-shaped file present actually decoded.
        var assets: [AssetDTO] = []
        var seenAssetFiles = 0
        var decodedAssetFiles = 0
        var assetEnumerationFailed = false
        if let entries = try? fm.contentsOfDirectory(at: assetsDir, includingPropertiesForKeys: nil) {
            for url in entries {
                guard url.pathExtension == "json",
                      UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil else { continue }
                seenAssetFiles += 1
                guard let data = try? Data(contentsOf: url) else {
                    Self.logger.error("read: could not read asset file \(url.lastPathComponent, privacy: .public)")
                    continue
                }
                guard let dto = try? Self.makeDecoder().decode(AssetDTO.self, from: data) else {
                    Self.logger.error("read: could not decode asset file \(url.lastPathComponent, privacy: .public)")
                    continue
                }
                assets.append(dto)
                decodedAssetFiles += 1
                seedDigest(path: "Assets/\(url.lastPathComponent)", bytes: data)
            }
        } else if fm.fileExists(atPath: assetsDir.path) {
            assetEnumerationFailed = true
            Self.logger.error("read: could not enumerate Assets/ despite it existing")
        }
        let assetsComplete = !assetEnumerationFailed && seenAssetFiles == decodedAssetFiles

        // Activity is historical, not structural: a bad shard is logged and skipped rather than
        // failing the whole read. Glob (not a fixed filename) so monthly shards later need no
        // read-side migration.
        var activityLog: [ActivityLogDTO] = []
        if let entries = try? fm.contentsOfDirectory(at: activityDir, includingPropertiesForKeys: nil) {
            for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where url.pathExtension == "json" {
                guard let data = try? Data(contentsOf: url),
                      let dtos = try? Self.makeDecoder().decode([ActivityLogDTO].self, from: data) else {
                    Self.logger.error("read: could not decode activity shard \(url.lastPathComponent, privacy: .public)")
                    continue
                }
                activityLog.append(contentsOf: dtos)
                seedDigest(path: "Activity/\(url.lastPathComponent)", bytes: data)
            }
        }

        lastReadWasComplete = assetsComplete
        recomputeStoreDigest()

        let snap = StoreSnapshotDTO(
            schemaVersion: manifest?.schemaVersion ?? storeSchemaVersion,
            compositeTypes: types,
            comboLists: comboLists,
            categories: categories,
            assets: assets,
            activityLog: activityLog,
            backgroundTheme: manifest?.backgroundTheme ?? BackgroundTheme.mist.rawValue
        )
        return ReadResult(snapshot: snap, wasMigratedFromLegacy: false, isComplete: assetsComplete)
    }

    private func readShard<T: Decodable>(baseDir: URL, shard: Shard, as type: T.Type) -> (value: T, bytes: Data)? {
        let url = baseDir.appendingPathComponent(shard.relativePath)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? Self.makeDecoder().decode(T.self, from: data) else { return nil }
        return (decoded, data)
    }

    // MARK: - Write

    /// No `NSFileCoordinator` here, deliberately. Per-shard coordination would be N round-trips
    /// for no benefit without per-shard conflict *resolution* to go with it, and that's its own
    /// design project — untestable while `AssetStore.iCloudSyncEnabled` is false and deferred
    /// until it's turned on. `AssetStore+Persistence.swift` still coordinates the legacy
    /// single-file path in `resolveConflicts()`, which only ever targets the manifest.
    @discardableResult
    func write(_ snap: StoreSnapshotDTO, baseDir: URL) -> WriteReport {
        queue.sync { writeLocked(snap, baseDir: baseDir) }
    }

    private func writeLocked(_ snap: StoreSnapshotDTO, baseDir: URL) -> WriteReport {
        resetDigestCacheIfBaseDirChanged(baseDir)
        let fm = FileManager.default
        var report = WriteReport()

        for sub in ["Definitions", "Assets", "Activity"] {
            try? fm.createDirectory(at: baseDir.appendingPathComponent(sub, isDirectory: true),
                                    withIntermediateDirectories: true)
        }

        let encoder = Self.makeEncoder()

        func writeShard<T: Encodable>(_ shard: Shard, _ value: T) {
            guard let data = try? encoder.encode(value) else {
                report.allDataShardsSucceeded = false
                Self.logger.error("write: failed to encode shard \(shard.relativePath, privacy: .public)")
                return
            }
            let path = shard.relativePath
            let digest = Self.sha256(data)
            if digests[path] == digest {
                report.skippedCount += 1
                return
            }
            let url = baseDir.appendingPathComponent(path)
            do {
                try data.write(to: url, options: .atomic)
                digests[path] = digest
                report.writtenPaths.append(path)
            } catch {
                report.allDataShardsSucceeded = false
                Self.logger.error("write: failed to write shard \(shard.relativePath, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }

        // Dependencies before dependents, manifest last: an interrupted save then leaves
        // definitions newer than assets (harmless — an unreferenced definition costs nothing),
        // never the reverse (which would amputate composite/comboList properties on read).
        writeShard(.types, snap.compositeTypes.sorted { $0.id.uuidString < $1.id.uuidString })
        writeShard(.comboLists, snap.comboLists.sorted { $0.id.uuidString < $1.id.uuidString })
        writeShard(.categories, snap.categories.sorted { $0.id.uuidString < $1.id.uuidString })

        var assetIDs: Set<UUID> = []
        for asset in snap.assets {
            assetIDs.insert(asset.id)
            writeShard(.asset(asset.id), asset)
        }

        // Swift's sort isn't stable, so equal timestamps (mergeSnapshot appends at differing
        // instants but two entries can still tie) need a secondary key to stay deterministic
        // across launches. HomeActivityDigest re-sorts internally, so on-disk order is invisible
        // to anything observable.
        let sortedLog = snap.activityLog.sorted {
            $0.timestamp == $1.timestamp ? $0.id.uuidString < $1.id.uuidString : $0.timestamp < $1.timestamp
        }
        writeShard(.activityLog, sortedLog)

        if report.allDataShardsSucceeded {
            let manifest = StoreManifestDTO(
                layoutVersion: storeLayoutVersion,
                schemaVersion: snap.schemaVersion,
                backgroundTheme: snap.backgroundTheme
            )
            writeShard(.manifest, manifest)
        } else {
            Self.logger.error("write: skipping manifest write — a data shard failed, leaving store.json pointing at the previous, still-consistent tree")
        }

        // Orphan sweep last, and only with positive confidence the in-memory asset set reflects
        // everything on disk — otherwise a transient read failure on one file becomes a
        // permanent deletion of that file on the very next save.
        if lastReadWasComplete {
            let assetsDir = baseDir.appendingPathComponent("Assets", isDirectory: true)
            if let entries = try? fm.contentsOfDirectory(at: assetsDir, includingPropertiesForKeys: nil) {
                for url in entries {
                    guard url.pathExtension == "json",
                          let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                          !assetIDs.contains(id) else { continue }
                    if (try? fm.removeItem(at: url)) != nil {
                        digests.removeValue(forKey: "Assets/\(url.lastPathComponent)")
                        report.deletedPaths.append("Assets/\(url.lastPathComponent)")
                    }
                }
            } else {
                Self.logger.error("write: could not enumerate Assets/ for the orphan sweep — skipping rather than risk deleting nothing or everything")
            }
        } else {
            Self.logger.debug("write: skipping orphan sweep — the last read couldn't verify every asset file")
        }

        recomputeStoreDigest()
        if !report.writtenPaths.isEmpty || !report.deletedPaths.isEmpty {
            Self.logger.debug("write: wrote \(report.writtenPaths.count, privacy: .public), deleted \(report.deletedPaths.count, privacy: .public), skipped \(report.skippedCount, privacy: .public)")
        }
        return report
    }

    // MARK: - Digest cache

    private func resetDigestCacheIfBaseDirChanged(_ baseDir: URL) {
        guard digestsBaseDir != baseDir else { return }
        digests.removeAll()
        digestsBaseDir = baseDir
        lastReadWasComplete = true
        storeDigest = nil
    }

    private func seedDigest(path: String, bytes: Data) {
        digests[path] = Self.sha256(bytes)
    }

    private func recomputeStoreDigest() {
        var hasher = SHA256()
        for path in digests.keys.sorted() {
            hasher.update(data: Data(path.utf8))
            hasher.update(data: digests[path]!)
        }
        storeDigest = Data(hasher.finalize())
    }

    /// Tests only: forgets the diff cache so the next `write` is unconditional.
    func resetDiffCache() {
        queue.sync {
            digests.removeAll()
            digestsBaseDir = nil
            lastReadWasComplete = true
            storeDigest = nil
        }
    }
}
