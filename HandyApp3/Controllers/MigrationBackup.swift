import Foundation
import os

private let migrationBackupLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "HandyApp3", category: "Persistence"
)

/// Local, non-synced snapshots of the store taken immediately before a version-gated schema
/// migration changes its shape — insurance independent of the store's own persistence, since a
/// migration that goes wrong would otherwise take its only copy of the pre-migration data down
/// with it. Written under Application Support, never inside the iCloud ubiquity container (the
/// store's own `baseDir` may BE that container's Documents directory — see
/// `AssetStore.resolvedBaseDir`), so a backup never syncs to a peer and churns.
///
/// Photo bytes are deliberately not included: DTO migrations never touch photo files (they're
/// keyed by `Photo.id`, which no migration step rewrites), so a full `exportJSON`-style dump
/// would balloon the backup for zero additional protection.
enum MigrationBackup {

    /// Tests only: points backups at a private temp directory instead of the real one.
    static var directoryOverride: URL?

    static var directory: URL {
        let dir = directoryOverride ?? {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            return support.appendingPathComponent("MigrationBackups", isDirectory: true)
        }()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// How many backup files to keep, across all `fromVersion`s combined, newest first.
    static let retentionCount = 3

    private static let filenamePrefix = "store.v"

    private static func filename(fromVersion: Int, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        // Zero-padded, fixed-width timestamp so filename lexical order == chronological order —
        // `prune()` relies on that to find the oldest backups without parsing dates back out.
        return "\(filenamePrefix)\(fromVersion).\(formatter.string(from: date)).json"
    }

    /// Encodes `snapshot` (the pre-migration content) via `CanonicalCodec` and writes it under
    /// `directory`, skipping if a backup for this `fromVersion` already exists — a crash-and-
    /// relaunch retry of the same migration must not pile up duplicate backups of the same
    /// starting point. Best-effort throughout: a failed backup must never block the migration
    /// itself, so every failure just logs and returns.
    static func writeIfNeeded(_ snapshot: StoreSnapshotDTO, fromVersion: Int, date: Date = Date()) {
        let fm = FileManager.default
        let dir = directory
        let existing = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        guard !existing.contains(where: { $0.hasPrefix("\(filenamePrefix)\(fromVersion).") }) else { return }

        guard let data = CanonicalCodec.encode(snapshot) else {
            migrationBackupLogger.error("MigrationBackup: failed to encode pre-migration snapshot for v\(fromVersion, privacy: .public)")
            return
        }
        let url = dir.appendingPathComponent(filename(fromVersion: fromVersion, date: date))
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            migrationBackupLogger.error("MigrationBackup: failed to write backup: \(String(describing: error), privacy: .public)")
            return
        }
        prune()
    }

    /// Keeps the newest `retentionCount` backups (by filename, which sorts lexically =
    /// chronologically since the timestamp is zero-padded and fixed-width), deleting the rest.
    private static func prune() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        let backups = files.filter { $0.hasPrefix(filenamePrefix) }.sorted()
        guard backups.count > retentionCount else { return }
        for name in backups.dropLast(retentionCount) {
            try? fm.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
