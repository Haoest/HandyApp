# HandyApp3

iOS/SwiftUI app for tracking physical assets the user owns (a house, a car, appliances, etc.) and the structured data attached to them.

## Project / build

- Xcode project format `objectVersion = 77` (Xcode 16+), using **file-system-synchronized groups** — files added to the folders on disk are picked up automatically; no need to register them in the `.pbxproj`.
- iOS deployment target **18.2**; Swift language version **5.0**; universal (`TARGETED_DEVICE_FAMILY = 1,2`, iPhone + iPad); `MARKETING_VERSION = 0.9`.
- SwiftUI throughout, with the Observation framework (`@Observable` / `@Environment(Type.self)`) for shared state — `AssetStore` and `AppRouter` are injected this way.

- don't use embedded simulator in claude. i'll build with xcode

### Running the tests from the command line

`Package.swift` at the repo root is a **CLI test harness**, not a real dependency of the
app — Xcode still builds the app exactly as before and knows nothing about the package.
It points at the source files where they already live, so `swift test` compiles the
logic layer and runs all of `HandyApp3Tests/` headlessly in ~11s, with no simulator and
no asset catalog (which is what `xcodebuild` chokes on here).

```
swift test                                     # all ~485 tests
swift test --filter SyncRelayTests             # one suite
swift test --filter ComboListTests/testSeedBuiltInComboListsIsIdempotentAfterRename
```

The package target covers `Models/`, `Controllers/`, `SystemTypes/`, plus
`Intents/AssetNameMatcher.swift` and `Views/HomeActivityDigest.swift` (both
Foundation-only). It excludes `Views/`, the AppIntents files, and
`Controllers/ReceiptScanner.swift` — the only Controller importing UIKit. **Anything the
tests need must stay free of SwiftUI/UIKit**; if a new pure rule is written inside a
view file, move the rule down to `Models/` and let the view call it (see
`ComboListDefinition.matchingOptions`, `BackgroundTheme`, `AppPreference`).

Caveat: `swift test` builds for macOS, so it verifies logic, not iOS-specific runtime
behavior. Anything involving layout, gestures, or first-render still needs ⌘U / ⌘B in
Xcode.

## Layout

- `HandyApp3/HandyApp3App.swift`, `ContentView.swift` — SwiftUI app entry & root view
- `HandyApp3/Models/` — domain types (`Asset`, `AssetCategory`, `AssetProperty`, `StoredValue`, `PropertyDefinition`, `PropertyType`, `CompositeTypeDefinition`, `ComboListDefinition`, `BuiltInTypes`)
- `HandyApp3/Controllers/` — `AssetStore` (single in-memory store; all mutations go through it) and `ContactResolver`
- `HandyApp3/SystemTypes/` — built-in seed code: composite *value* types (W × L, W × L × H), combo lists, all as extensions on `BuiltInTypes` / `AssetStore`
- `HandyApp3/UserTypes/` — user-defined types (currently empty)
- `HandyApp3Tests/`, `HandyApp3UITests/` — XCTest targets

## Domain model in one paragraph

An `Asset` is a named physical object. It belongs to one `AssetCategory`, which defines a template of `AssetProperty` entries. When an asset is created, those templates are deep-copied into `Asset.baseProperties` (per-instance snapshot — changes to the category do not affect existing assets). Users may also attach additional `Asset.customProperties` specific to that instance. Each `AssetProperty` bundles a `PropertyDefinition` (name + `PropertyType` + isRequired) with an optional `StoredValue`. A `PropertyType` is either a `BasicType` (text/number/currency/date/contact), a `CompositeTypeDefinition` (a struct of named fields, e.g. W × L), or a `ComboListDefinition` (a pick-list of string options). Assets form a runtime containment tree via `Asset.parent` / `children`; mutate through `AssetStore`.

## Conventions

- **No file header comments.** Don't add the Xcode `// Created by ... on <date>` block to new Swift files. Start at the first `import`.
- **No author/date stamps in code or commit messages.**
- All store mutations go through `AssetStore`. `Asset._addChild`/`_removeChild` are package-private by convention — call them from the store, not from views.
- Built-in seed APIs on `AssetStore`: `seedBuiltInComboLists()` and `seedBuiltInTypes()` (composite value types: W × L, W × L × H). Both are idempotent and safe to call at startup.
- New built-in composite *value* types and combo lists live in `SystemTypes/` as `extension BuiltInTypes`.
- **Testing in conceptual phases:** write tests for behavior at boundaries (validation rules, store invariants, hierarchy rules) — skip tests for plain accessors or class shape. During a structural rewrite, don't nurse the existing test suite through intermediate steps; rewrite it once at the end of the phase that completes the rewrite.

## Open work


- ~~work on real persistence, leave app with in-memory persistence for now~~
- ~~enable icloud backup~~
- ~~application version~~
- ~~change add icon on asset listing screen and detail screen to differentiate them~~
- beautify screens
- auto parse photo for transaction?
- ~~list event/transaction~~
- ~~preference screen (eg how many event/transaction to show)~~ (the Preferences tab was replaced by the Events & Transactions tab, which aggregates events/transactions across all assets with its own filter/window controls; Appearance and Language moved to Tools → Preference)
- ~~add logging~~
- add tools (communication, data export)
- ~~summarize home screen~~
- ~~delete category~~
- ~~application icon~~
- ~~hard delete soft deleted records by age~~
- ~~deploy to iphone~~
- under asset detail screen, list child assets
- search
- definition tombstones: `ComboListDefinition` now has `isDeleted`/`deletedAt` (soft delete via `AssetStore.softDeleteComboList`/`restoreComboList`; `SnapshotReconciler.joinComboList` merges the flag LWW alongside the existing grow-only `userOptions` union; never auto-purged — see `AssetStore.purgeHardDeleted`'s doc comment). Still open: `deleteCompositeType` and `removeUserOption` hard-remove/mutate with no tombstone, so a peer's still-live copy resurrects a composite type or a removed combo-list option on the next sync merge. Needs `isDeleted`/`deletedAt` on `CompositeTypeDTO`, and its own per-option tombstone scheme for combo-list options — its own pass.
- purge-vs-offline-edit is now safe for asset/category *records* (an aged tombstone whose content was edited after the delete decision refuses to auto-purge — see `Asset`/`AssetCategory.isProtectedFromAutoPurge`, `SnapshotReconciler.joinAsset`/`joinCategory`'s purge gate) but photo *files* are not: `purgeInPlace` deletes JPEGs immediately regardless of whether the strip that triggered it was itself refused elsewhere, so a protected asset's photos can still be gone. Possible fix: stage purged photos in a local, non-synced holding directory for a grace period instead of deleting outright.
- ~~factory reset + import duplicated "My Home"/"Testarossa 85"~~ (fixed: sample assets now seed at `BuiltInTypes.deterministicID` ids, and `seedBuiltInAssets` is presence-keyed including purged husks — see its doc comment). Residual gap for an install that seeded before this change, still holding the samples at random ids: (1) delete-and-reinstall then import an old backup — the reinstall seeds at the canonical id, the backup's copy is at the legacy random id, no id match, both go live; (2) a peer device still on legacy random ids syncing its own copy in. Only a versioned DTO re-key (`StoreMigrationV5`-style, since `AssetDTO.id` is a `var` even though `Asset.id` is `let`) closes this — it would also need to run inside `importJSON` so an old backup gets re-keyed on the way in, same as v5 does for categories.
- `ReceiptParser.decimal(from:)` (`Controllers/ReceiptParser.swift:169-175`) strips a hardcoded `"$"` and treats every `,` as a thousands separator before parsing — unlike the manual entry fields (`NumberParsing`), it doesn't accept `,` as a decimal separator, and it will mangle a European receipt's `1.234,56`. Not fixed alongside `NumberParsing` since receipt OCR output shape wasn't audited for this pass.
