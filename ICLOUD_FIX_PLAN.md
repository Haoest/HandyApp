# iCloud persistence fix plan

Execution plan for the defects found in the iCloud-persistence audit (2026-07-17).
Work through the phases **in order** — later phases depend on the test seam in Phase 0
and the suspension flag in Phase 1. Do not start a phase until the previous phase's
acceptance criteria pass.

## Context you need before touching anything

- The app persists the whole store as one JSON file, `store.json`, in the iCloud
  ubiquity container (fallback: local Documents). See
  `HandyApp3/Controllers/AssetStore+Persistence.swift`.
- `AssetStore.baseDir` (static let) resolves the directory once per launch and runs a
  one-time local→cloud migration.
- Saves are debounced: every mutation calls `markDirty()`, which schedules `save()`
  ~2 s later on a background thread (`AssetStore.swift`, "Persistence internals").
- An `NSMetadataQuery` ("cloud monitor", `startCloudMonitor()`) watches `store.json`
  and applies foreign changes. It compares raw bytes against
  `AssetStore.lastPersistedData` to skip echoes of our own writes — preserve this
  invariant in everything you do.
- Photo files live beside the store in `Photos/<uuid>_full.jpg` / `<uuid>_thumb.jpg`
  (`PhotoStorage` in the same file). Only metadata (`PhotoDTO`) is in store.json.
- `AppDependencies.makeStore()` (`HandyApp3/Intents/AppDependencies.swift`) loads at
  launch and **seeds sample data when `load()` returns false** — that seeding is the
  root of the critical defect below.

## Ground rules

- Swift conventions: no file-header comments, no author/date stamps. All store
  mutations go through `AssetStore`.
- The existing unit-test suite (152 cases incl. `StoreIntegrityTests`) must stay
  green after every phase. Never edit an existing test to make it pass unless the
  plan explicitly says so.
- Do not commit; leave the working tree for the user to review.
- Ignore SourceKit editor diagnostics like "Cannot find 'AssetStore' in scope" —
  the project indexes slowly; trust `xcodebuild` results only.

## How to build & test on this machine

The Mac's CoreSimulator install is partially broken (actool cannot spawn its
simulator agent). Use exactly this invocation — the two overrides are CLI-only
workarounds, **never** add them to the project file:

```bash
export TMPDIR=/tmp
xcodebuild test -project HandyApp3.xcodeproj -scheme HandyApp3 \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:HandyApp3Tests \
  'EXCLUDED_SOURCE_FILE_NAMES=*.xcassets' ENABLE_DEBUG_DYLIB=NO \
  > /tmp/test.log 2>&1
grep -cE "Test case .* passed" /tmp/test.log
grep -E "Test case .* failed" /tmp/test.log
```

`TMPDIR=/tmp` is required or the result bundle fails to write.

---

## Phase 0 — test seam: overridable store directory

**Why:** disk-touching tests currently share the test host's real Documents dir,
which is both a flakiness risk and a blocker for the tests in later phases.

**Changes** (`AssetStore+Persistence.swift`):

1. Rename the existing `static let baseDir` initializer to a private
   `static let resolvedBaseDir: URL = { ...unchanged body... }()`.
2. Add:

```swift
/// Tests only: points the store at a private temp directory.
static var baseDirOverride: URL?

static var baseDir: URL {
    if let override = baseDirOverride {
        try? FileManager.default.createDirectory(
            at: override.appendingPathComponent("Photos", isDirectory: true),
            withIntermediateDirectories: true)
        return override
    }
    return resolvedBaseDir
}
```

3. In `HandyApp3Tests/StoreIntegrityTests.swift`, set the override in `setUp()` to a
   unique temp dir (`FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)`),
   and clear it + delete the dir in `tearDown()`. Do the same in any new test class
   that touches disk.

**Acceptance:** full suite green; `testImportIsOnDiskWhenCallReturns` now reads
`AssetStore.storeURL` inside the temp dir.

---

## Phase 1 — CRITICAL: never clobber an unread cloud store with seed data

**Defect:** on a fresh device the cloud `store.json` may exist remotely but not be
downloaded. `load()` reads nil → `makeStore()` seeds sample data → the first save
uploads seeds over the user's real store, and other devices apply it. Total data loss.

**Design — two layers of defense:**

*Layer 1: bounded synchronous wait.* In `load()` (before the coordinated read), if
the ubiquity container is active, the local file is absent, and the iCloud
placeholder exists, trigger download and poll briefly:

```swift
// inside the background block of load(), before readStoreData():
Self.waitForCloudStore(timeout: 10)
```

```swift
private static func waitForCloudStore(timeout: TimeInterval) {
    let fm = FileManager.default
    guard baseDirOverride == nil,
          fm.url(forUbiquityContainerIdentifier: nil) != nil else { return }
    let url = storeURL
    guard !fm.fileExists(atPath: url.path) else { return }
    let placeholder = url.deletingLastPathComponent()
        .appendingPathComponent(".store.json.icloud")
    guard fm.fileExists(atPath: placeholder.path) else { return }
    try? fm.startDownloadingUbiquitousItem(at: url)
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline, !fm.fileExists(atPath: url.path) {
        Thread.sleep(forTimeInterval: 0.2)
    }
}
```

*Layer 2: suspended saves until the cloud answers.* The placeholder may not exist
yet (metadata still syncing), so Layer 1 can miss. Therefore:

1. Add to `AssetStore` (next to `saveTask`):

```swift
/// True while we have seeded in-memory data but have NOT yet confirmed the cloud
/// container is empty. While set, save()/markDirty() are no-ops so seed data can
/// never overwrite an unread cloud store.
@ObservationIgnored
var savesSuspended = false
```

2. `save()` and `markDirty()`: `guard !savesSuspended else { return }` first line.
3. Extract the cold-start decision as a pure, testable function on `AssetStore`:

```swift
enum ColdStartAction { case useLoaded, seedAndPersist, seedSuspended }

static func coldStartAction(loaded: Bool, iCloudActive: Bool) -> ColdStartAction {
    if loaded { return .useLoaded }
    return iCloudActive ? .seedSuspended : .seedAndPersist
}
```

4. In `AppDependencies.makeStore()`: replace the `if !wasLoaded` branch with a
   switch over `coldStartAction(loaded: wasLoaded, iCloudActive: FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil)`.
   For `.seedSuspended`: seed the same content, set `store.savesSuspended = true`,
   and **skip** the `DispatchQueue...save()` call.
5. In `startCloudMonitor()`, also observe `.NSMetadataQueryDidFinishGathering`
   (same handler closure — extract it into a method taking the query). In the
   handler, after the existing echo check and apply logic, add resolution of the
   suspension:
   - If a foreign `store.json` was applied → `savesSuspended = false` (real data won).
   - If the gather finished and the query has **zero results** for `store.json`
     (`query.results` empty) → cloud is genuinely empty → `savesSuspended = false;
     markDirty()` so the seeds persist.

**Tests** (new class `ColdStartTests` or extend `StoreIntegrityTests`):
- `coldStartAction(loaded: true, iCloudActive: *)` → `.useLoaded`.
- `coldStartAction(loaded: false, iCloudActive: false)` → `.seedAndPersist`.
- `coldStartAction(loaded: false, iCloudActive: true)` → `.seedSuspended`.
- With `savesSuspended = true`: mutate the store, call `save()` directly, assert
  `store.json` was NOT written to the (overridden) base dir; then set
  `savesSuspended = false`, `save()`, assert it was written.

**Acceptance:** suite green, new tests pass. Manual sanity (optional, user-run):
delete app from a device, airplane-mode it, reinstall, launch — app should show
sample data but write nothing; disable airplane mode — real data should arrive.

---

## Phase 2 — import must not destroy photos; export should carry them

**Defect A (import):** `importJSON` deletes *every* file in `Photos/` before
applying the snapshot, even though the incoming snapshot references the same photo
IDs — a round-trip wipes all photos, and the deletions sync to every device.

**Fix A** (`importJSON` in `AssetStore+Persistence.swift`): compute the set of photo
IDs referenced by the incoming snapshot and delete only unreferenced files:

```swift
let keepIDs = Set(incoming.assets.flatMap { $0.photos.map(\.id) })
let photosDir = Self.baseDir.appendingPathComponent("Photos", isDirectory: true)
if let files = try? FileManager.default.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: nil) {
    for file in files {
        let prefix = file.lastPathComponent.split(separator: "_").first.map(String.init) ?? ""
        if let id = UUID(uuidString: prefix), keepIDs.contains(id) { continue }
        try? FileManager.default.removeItem(at: file)
    }
}
```

**Defect B (export):** exports contain no photo bytes, so import-from-export on a
different device (or after A's cleanup of genuinely missing files) loses photos.

**Fix B — embed photos in the export JSON.** In the DTO file (find `PhotoDTO` —
grep for `struct PhotoDTO`):

1. Add two optional fields: `var fullImage: Data?`, `var thumbnail: Data?`
   (optional keeps old exports decodable — verify `init(from:)` is synthesized;
   if the DTO has explicit `CodingKeys`, add the new cases).
2. `exportJSON()` only (NOT `buildSnapshot()` used by `save()` — store.json must
   stay lean): after building the snapshot, populate the photo fields from
   `PhotoStorage.loadFull/loadThumb`. Implement by giving `buildSnapshot` a
   parameter `includePhotoData: Bool = false` and passing `true` from `exportJSON`.
3. `importJSON`: after applying the snapshot, for each incoming photo DTO with
   embedded data, write files via `PhotoStorage.save` (skip if the file already
   exists).

**Tests:**
- Round-trip preserves photo files: with the Phase-0 override active, call
  `PhotoStorage.save(id:...)` with tiny fixture data, attach a photo record to an
  asset via the store API (grep `addPhoto` for the method), export, import, assert
  both files still exist and `asset.photos` metadata survives.
- Unreferenced photo file is deleted on import.
- Export with `includePhotoData` contains the bytes; import into a store whose
  Photos/ dir is empty recreates the files.

**Acceptance:** suite green including new tests. JSON exports grow with photo count —
expected, note it in the Tools screen only if a string already mentions export
contents (do not redesign UI in this phase).

---

## Phase 3 — deletion hygiene

**3a. `factoryReset` (in `AssetStore+Persistence.swift`):**
- Replace the async save with a synchronous one, mirroring `importJSON`:
  `DispatchQueue.global(qos: .userInitiated).sync { self.save() }`.
- Do **not** `removeItem` on `store.json` at all — reseeding + synchronous save
  overwrites it, which propagates to other devices as content (a "tombstone by
  overwrite") instead of a file deletion they'd ignore and later clobber.
- Clear `savesSuspended = false` at the start (a reset is an explicit user decision).
- Keep deleting all photo files (a reset should wipe them) — that part is correct.

**3b. Hard `deleteAsset` (in `AssetStore.swift`, ~line 245):** before
`assets.removeValue(forKey: id)` add:

```swift
for photo in asset.photos { PhotoStorage.delete(id: photo.id) }
```

**Tests:**
- `factoryReset` leaves a decodable `store.json` on disk (overridden dir) when the
  call returns, containing seeded content.
- `deleteAsset` removes the photo files (create fixture files first via
  `PhotoStorage.save`).

---

## Phase 4 — photos must download on other devices

**Defect:** `PhotoStorage.loadFull/loadThumb` never trigger iCloud download; iOS
does not auto-download ubiquitous files, so photos never appear on a second device
or after reinstall.

**Changes** (`PhotoStorage` in `AssetStore+Persistence.swift`):

```swift
private static func read(_ url: URL) -> Data? {
    if let data = try? Data(contentsOf: url) { return data }
    try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    return nil
}
static func loadFull(id: UUID) -> Data? { read(fullURL(id: id)) }
static func loadThumb(id: UUID) -> Data? { read(thumbURL(id: id)) }
```

**UI retry** (`HandyApp3/Views/AssetPhotosViews.swift`): the thumbnail view loads
via `PhotoStorage.loadThumb` in `onAppear`/`task` (line ~68). Where the result is
nil, add a bounded retry: a `.task` loop of up to 10 attempts, 1 s apart, breaking
when data arrives or the view disappears (`Task.isCancelled`). Same pattern for the
full-image path (~line 99, 188). Keep it minimal — no spinner redesign; the existing
placeholder stays until data lands.

**Tests:** the download trigger can't be unit-tested without iCloud; test only that
`loadThumb` on a missing file returns nil without throwing, and (behavioral) that
the retry loop stops after data appears — if that requires awkward view plumbing,
skip the view test and leave verification manual (two simulators, ⇧⌘I to force sync).

---

## Phase 5 — monitor completeness and conflict cleanup

**5a. DidFinishGathering:** done as part of Phase 1 step 5 — verify both
notifications route through the shared handler.

**5b. Conflict versions:** after every successful apply in the monitor handler AND
at the end of a successful `save()`, add:

```swift
if let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: Self.storeURL),
   !conflicts.isEmpty {
    for version in conflicts { version.isResolved = true }
    try? NSFileVersion.removeOtherVersionsOfItem(at: Self.storeURL)
}
```

This makes last-writer-wins explicit and stops stale versions from accumulating.
Guard it behind `baseDirOverride == nil` so tests never touch NSFileVersion.

**Tests:** none practical; verify the suite still passes and rely on manual
two-simulator checks.

---

## Definition of done

1. Full unit suite green (152 pre-existing cases + all new ones) via the build
   command above.
2. No project-file changes except new test files picked up by the synced folders.
3. Each phase's acceptance criteria met before moving on.
4. Working tree left uncommitted, with a short summary of what changed per phase.
