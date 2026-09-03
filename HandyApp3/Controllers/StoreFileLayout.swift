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

    /// Name older builds wrote a legacy-migration backup under before migrating to the
    /// multi-file layout. No longer created — `factoryReset` still deletes any stale copy
    /// left behind by an older build. Versioned by `storeSchemaVersion` (the DTO shape that
    /// was backed up), not `storeLayoutVersion` (which describes what it was migrated *to*).
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

    /// Only meaningful right after `read(baseDir:)` returns `nil` — distinguishes a genuinely
    /// fresh install (`.absent`, safe to seed) from a store that exists but currently can't be
    /// fully read: `.pending` while a structural shard is still downloading (also safe to seed
    /// for display — the seed is `savesSuspended` until the download completes and a later read
    /// succeeds), and `.damaged` when a structural shard is present and finished downloading but
    /// still didn't decode — e.g. `Definitions/` was deleted or corrupted out from under a
    /// populated `Assets/` tree via the ubiquity container's public Files folder. Seeding over
    /// `.damaged` is exactly the bug this exists to prevent: the caller must latch
    /// `savesSuspended` (or equivalent) and never lift it automatically for this case.
    enum StoreAbsenceReason: Equatable {
        case absent
        case pending
        case damaged
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

    private static func makeEncoder() -> JSONEncoder { CanonicalCodec.makeEncoder() }
    private static func makeDecoder() -> JSONDecoder { CanonicalCodec.makeDecoder() }

    private static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    // MARK: - File coordination

    /// True only once iCloud sync is actually on and this isn't a test run — coordinated I/O
    /// adds real overhead and complexity the test suite doesn't need and that only matters
    /// once files genuinely live in the ubiquity container. Computed rather than a stored,
    /// externally-set flag so it can never drift out of sync with the two conditions it
    /// depends on.
    private var usesFileCoordination: Bool { AssetStore.iCloudSyncEnabled && AssetStore.baseDirOverride == nil }

    /// Wraps `body` in `NSFileCoordinator` write coordination when enabled, a plain call
    /// otherwise. One coordinated call per changed file rather than one batched call for the
    /// whole write — simpler and safer to reason about than the async multi-item intent API,
    /// at the cost of N round-trips instead of one; N is small in practice, since `body` is
    /// only ever invoked for shards the digest-diff already found changed.
    private static func coordinatedAccess(at url: URL, options: NSFileCoordinator.WritingOptions, enabled: Bool, _ body: () -> Void) {
        guard enabled else { body(); return }
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        coordinator.coordinate(writingItemAt: url, options: options, error: &coordError) { _ in body() }
        if let coordError {
            logger.error("coordinatedAccess: coordination failed for \(url.lastPathComponent, privacy: .public): \(String(describing: coordError), privacy: .public)")
        }
    }

    // MARK: - Read

    func read(baseDir: URL) -> ReadResult? {
        queue.sync {
            guard usesFileCoordination else { return readLocked(baseDir: baseDir) }
            var result: ReadResult?
            let coordinator = NSFileCoordinator()
            var coordError: NSError?
            coordinator.coordinate(readingItemAt: baseDir, options: [], error: &coordError) { _ in
                result = self.readLocked(baseDir: baseDir)
            }
            if let coordError {
                Self.logger.error("read: coordination failed: \(String(describing: coordError), privacy: .public)")
            }
            return result
        }
    }

    private func readLocked(baseDir: URL) -> ReadResult? {
        resetDigestCacheIfBaseDirChanged(baseDir)
        // Rebuilt from scratch on every read, not merged into the previous map: under sync a
        // peer can delete or replace a file behind this process's back between reads. A
        // write-through cache that only ever adds entries would (a) skip recreating a file the
        // peer deleted, since writeShard would see a stale matching digest and no-op, and worse
        // (b) hash a ghost entry into storeDigest, which can then coincidentally equal
        // lastPersistedData and make the cloud monitor discard a genuine foreign change as an
        // echo of its own write. Only what THIS read actually finds should ever be in the cache.
        digests.removeAll()
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
        // have failed to verify. digests is already empty (cleared above) and storeDigest is
        // reset so nothing stale from a previous read lingers.
        guard manifest != nil || treeExists else {
            storeDigest = nil
            return nil
        }

        guard
            let (types, typesBytes) = readShard(baseDir: baseDir, shard: .types, as: [CompositeTypeDTO].self),
            let (comboLists, comboBytes) = readShard(baseDir: baseDir, shard: .comboLists, as: [ComboListDTO].self),
            let (categories, categoriesBytes) = readShard(baseDir: baseDir, shard: .categories, as: [CategoryDTO].self)
        else {
            lastReadWasComplete = false
            storeDigest = nil
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

    /// See `StoreAbsenceReason`. Call only after `read(baseDir:)` has just returned `nil` for
    /// this `baseDir` — this re-inspects the filesystem rather than reusing `read`'s state, so
    /// it stays correct even though it doesn't share a queue hop with the read that triggered it.
    func diagnoseAbsence(baseDir: URL) -> StoreAbsenceReason {
        let fm = FileManager.default
        let manifestURL = baseDir.appendingPathComponent(Shard.manifest.relativePath)
        // Checking the *contents* of Definitions/Assets/Activity, not just whether those
        // directories themselves exist: `AssetStore.baseDir` creates all three as empty
        // shells the moment it's first accessed (`createStoreSubdirectories`), on a
        // genuinely fresh install included — so directory existence alone would make
        // `.absent` unreachable and misreport every fresh install as `.damaged`.
        func hasAnyFile(in dir: URL) -> Bool {
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return false }
            return !entries.isEmpty
        }
        let hasManifest = fm.fileExists(atPath: manifestURL.path)
        let hasAssetFiles = hasAnyFile(in: baseDir.appendingPathComponent("Assets", isDirectory: true))
        let treeExists = hasManifest
            || hasAnyFile(in: baseDir.appendingPathComponent("Definitions", isDirectory: true))
            || hasAssetFiles
            || hasAnyFile(in: baseDir.appendingPathComponent("Activity", isDirectory: true))
        guard treeExists else { return .absent }

        let structuralURLs = [Shard.types, Shard.comboLists, Shard.categories]
            .map { baseDir.appendingPathComponent($0.relativePath) }
        if structuralURLs.contains(where: { !Self.isDownloaded($0) }) { return .pending }

        // `writeLocked` writes Definitions/ shards, then Assets/, then the manifest last — so a
        // tree with no manifest and no asset files can only be a first write torn before either
        // landed, meaning everything present is regenerable built-in seed data. Safe to treat as
        // a fresh install rather than latching `.damaged` (which would then block writes forever,
        // since the tree can never finish completing itself with saves disabled).
        if !hasManifest, !hasAssetFiles { return .absent }
        return .damaged
    }

    /// True if the item is fully downloaded, or if it can't be inspected at all — the latter
    /// almost always means it doesn't exist yet, which `diagnoseAbsence` already routes to
    /// `.absent`/`.damaged` on other grounds, not something to report as still-downloading.
    /// Mirrors `AssetStore.isDownloaded` (`AssetStore+Persistence.swift`) — kept as its own
    /// copy here rather than shared, since this type otherwise has no dependency on `AssetStore`.
    private static func isDownloaded(_ url: URL) -> Bool {
        guard let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus else { return true }
        return status == .current || status == .downloaded
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
        // Canonicalize once, up front: every nested array in canonical order regardless of
        // whether `snap` came from live model state or from a merge. Everything below reads
        // from `canonSnap`, never `snap`, so on-disk bytes are always a pure function of
        // content — see the doc comment on StoreSnapshotDTO.canonicalized().
        let canonSnap = snap.canonicalized()

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
            var writeError: Error?
            Self.coordinatedAccess(at: url, options: .forReplacing, enabled: usesFileCoordination) {
                do {
                    try data.write(to: url, options: .atomic)
                    digests[path] = digest
                    report.writtenPaths.append(path)
                } catch {
                    writeError = error
                }
            }
            if let writeError {
                report.allDataShardsSucceeded = false
                Self.logger.error("write: failed to write shard \(shard.relativePath, privacy: .public): \(String(describing: writeError), privacy: .public)")
            }
        }

        // Dependencies before dependents, manifest last: an interrupted save then leaves
        // definitions newer than assets (harmless — an unreferenced definition costs nothing),
        // never the reverse (which would amputate composite/comboList properties on read).
        writeShard(.types, canonSnap.compositeTypes)
        writeShard(.comboLists, canonSnap.comboLists)
        writeShard(.categories, canonSnap.categories)

        var assetIDs: Set<UUID> = []
        for asset in canonSnap.assets {
            assetIDs.insert(asset.id)
            writeShard(.asset(asset.id), asset)
        }

        writeShard(.activityLog, canonSnap.activityLog)

        if report.allDataShardsSucceeded {
            let manifest = StoreManifestDTO(
                layoutVersion: storeLayoutVersion,
                schemaVersion: canonSnap.schemaVersion,
                backgroundTheme: canonSnap.backgroundTheme
            )
            writeShard(.manifest, manifest)
        } else {
            Self.logger.error("write: skipping manifest write — a data shard failed, leaving store.json pointing at the previous, still-consistent tree")
        }

        // Orphan sweep last, and only with positive confidence the in-memory asset set reflects
        // everything on disk — otherwise a transient read failure on one file becomes a
        // permanent deletion of that file on the very next save.
        //
        // Candidates come from `digests` (what the last `read` actually saw), not from
        // enumerating the live `Assets/` directory. A peer's asset file can materialize on disk
        // between this device's last read and this write (iCloud downloads and app writes are
        // not coordinated against each other) — enumerating the directory would treat that
        // just-arrived file as an orphan and delete it, propagating a deletion the peer never
        // made. A file this device never read has no entry in `digests`, so it's simply not a
        // sweep candidate; the next `read` picks it up and folds it in normally.
        if lastReadWasComplete {
            let seenAssetPaths = digests.keys.filter { $0.hasPrefix("Assets/") }
            for path in seenAssetPaths {
                guard let id = UUID(uuidString: String(path.dropFirst("Assets/".count).dropLast(".json".count))),
                      !assetIDs.contains(id) else { continue }
                let url = baseDir.appendingPathComponent(path)
                var removed = false
                Self.coordinatedAccess(at: url, options: .forDeleting, enabled: usesFileCoordination) {
                    removed = (try? fm.removeItem(at: url)) != nil
                }
                if removed {
                    digests.removeValue(forKey: path)
                    report.deletedPaths.append(path)
                }
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

    /// Deletes every on-disk shard — `Definitions/*.json`, `Assets/*.json`, `Activity/*.json`,
    /// and the manifest — and forgets the digest cache. Used only by `factoryReset` on a store
    /// that was `.damaged`: nothing was ever loaded into memory, so there's no in-memory copy
    /// to overwrite as a tombstone the way a healthy reset purges assets in place; the leftover
    /// files must be removed outright instead. See that call site for the accepted cost.
    func removeAllShards(baseDir: URL) {
        queue.sync {
            let fm = FileManager.default
            for sub in ["Definitions", "Assets", "Activity"] {
                let dir = baseDir.appendingPathComponent(sub, isDirectory: true)
                guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
                for url in entries where url.pathExtension == "json" {
                    try? fm.removeItem(at: url)
                }
            }
            try? fm.removeItem(at: baseDir.appendingPathComponent(Shard.manifest.relativePath))
            digests.removeAll()
            digestsBaseDir = nil
            lastReadWasComplete = true
            storeDigest = nil
        }
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
