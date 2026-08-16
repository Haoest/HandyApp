# iCloud sync — manual verification checklist

Run this on two real devices (or one device + one simulator signed into the same test Apple
ID) once per release that touches persistence or sync. The automated suite
(`SnapshotReconcilerTests`, `ApplyInPlaceTests`, `TwoDeviceRelayTests`, `ConflictResolutionTests`,
`SyncRelayTests`, `StoreFileLayoutTests`, `CategoryDeletionTests`) proves the reconciliation
logic, the purge-protection gate, and file-layout behavior in isolation; only a real run can
show that the ubiquity container actually resolves under the signing profile, that
`NSMetadataQuery`/`NSFileCoordinator`/`NSFileVersion` behave as assumed, and that download
priming works against real placeholder timing.

Watch logs on either device while testing:

```bash
log stream --predicate 'subsystem == "haoest.HandyApp3" and category == "Persistence"' --style compact
```

## Steps

1. **Fresh population.** Populate device 1 with a few categories, assets, and a photo. Confirm
   the tree lands in Files.app → iCloud Drive → Baron Book (`store.json`, `Definitions/`,
   `Assets/`, `Activity/`, `Photos/`).
2. **Fresh install, offline first.** Install on device 2 with airplane mode on. Sample seed data
   should appear; confirm nothing is written to the container while offline (`savesSuspended`
   holds). Disable airplane mode — device 1's real data should replace the seeds, with **no
   duplicate** "Primary Home" / "3D Size" / "Testarossa 85" (the seed-vs-real-store guard).
3. **Simple propagation.** Rename an asset on device 1; confirm it appears on device 2 within a
   few seconds. Reverse the direction.
4. **Concurrent edit, same asset, different fields.** Open the same asset's detail screen on
   both devices. Edit a different property on each. Both edits must survive, and neither screen
   should lose its in-progress draft.
5. **Concurrent rename of different categories, both offline.** Put both devices in airplane
   mode. Rename one category on device 1, a *different* category on device 2. Reconnect both.
   Both renames must survive (exercises the per-shard `NSFileVersion` conflict merge on
   `Definitions/categories.json`).
6. **Delete vs. offline edit.** Device 2 offline. Soft-delete an asset on device 1. Reconnect
   device 2 — the asset must be in its trash, not resurrected.
7. **Offline edit vs. later delete.** Device 2 offline, edits an asset. Device 1 (later)
   soft-deletes the same asset. Reconnect. The asset is deleted on both; open the trash on
   either device and confirm the edit is preserved inside the tombstoned record.
8. **Offline edit vs. delete that ages past retention (the purge-protection gate).** Device 2
   offline, edits an asset (or a category's property template). Device 1 soft-deletes the same
   record, then back-dates its own local `deletedAt`/force-purges it (Tools → System → Deleted →
   swipe → Delete now) so it's stripped to a husk before device 2 ever reconnects. Reconnect
   device 2 — the asset must land in Trash on both devices with device 2's edit still intact
   (not stripped), and the Trash row must show "Edited after deletion — won't be auto-purged".
   Confirm it truly never ages out: wait past the retention window (or lower
   `DaysToRetainDeletedItems` for the test) and re-launch — it must still be there, still with
   its content. Then swipe → Delete now on either device to confirm an explicit purge still
   works and propagates the strip to the other device on the next sync.
9. **Photos.** Add a photo on device 1. Confirm the thumbnail appears on device 2 within the
   retry window, then open it full-size.
10. **Reciprocal re-parent.** Move a child asset under a different parent on device 1 while
    device 2 (concurrently) moves the prospective parent under that child. Reconnect — no hang
    (`Asset.descendants` / `AssetDetailView.anchorIndex` are unbounded walks), one link drops,
    both devices converge on the same tree.
11. **Factory reset.** Reset device 1. Device 2 must converge to the reset (empty + reseeded)
    state rather than re-uploading its old data over the reset.
12. **Reinstall.** Delete the app from device 2 and reinstall. The full store — including
    photos — must download.
13. **Interrupted save.** On device 1, make an edit and immediately background the app (or
    force-quit) before the 2-second debounce fires. Relaunch — no partial tree, no lost edit.

## What each step is actually checking, if something goes wrong

- Container not visible in Files.app at all → check `NSUbiquitousContainers` in `Info.plist`
  and that `CURRENT_PROJECT_VERSION` was bumped since the container config was last read.
- Step 2 shows duplicates → `hasAuthoritativeLocalState` guard in
  `handleCloudMonitorNotification` (`AssetStore+Persistence.swift`) isn't firing correctly.
- Step 5 loses a rename → per-shard conflict resolution
  (`ConflictResolution.swift`/`resolveShardConflicts`) regressed to whole-file
  `removeOtherVersionsOfItem` behavior.
- Step 6/7 resurrects a delete → `AssetDTO.headModifyDate` isn't being stamped or compared
  correctly in `SnapshotReconciler.joinAsset`.
- Step 8 silently loses device 2's edit instead of protecting it → the purge gate isn't firing;
  check `AssetDTO.purgedAt`/`Asset.purgedAt` actually got stamped by the purging device (via
  `purgeInPlace(_:at:)` or `SnapshotReconciler.reap`) and that `SnapshotReconciler.joinAsset`'s
  `purgeIsEntitled` check is comparing against the live side's own `modifiedDate`/
  `headModifyDate`, not a stale/merged value. If it instead never purges even a genuinely
  untouched tombstone, check the fallback direction — `purgeHardDeleted`'s selection and
  `reap`'s transition test must use `purgedAtFallback: .distantPast` (a *not-yet-purged* record
  with no prior purge attempt), not `.distantFuture` (which is only correct once a side already
  carries `isPurged == true`).
- Step 10 hangs → `SnapshotReconciler.normalizeHierarchy`'s cycle-breaking regressed.
