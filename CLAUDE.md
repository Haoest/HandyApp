# HandyApp3

iOS/SwiftUI app for tracking physical assets the user owns (a house, a car, appliances, etc.) and the structured data attached to them.

## Project / build

- Xcode project format `objectVersion = 77` (Xcode 16+), using **file-system-synchronized groups** — files added to the folders on disk are picked up automatically; no need to register them in the `.pbxproj`.
- iOS deployment target **18.2**; Swift language version **5.0**; universal (`TARGETED_DEVICE_FAMILY = 1,2`, iPhone + iPad); `MARKETING_VERSION = 0.9`.
- SwiftUI throughout, with the Observation framework (`@Observable` / `@Environment(Type.self)`) for shared state — `AssetStore` and `AppRouter` are injected this way.

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

- flesh out photo properties to allow selection, viewing, thumbnail
- work on real persistence, leave app with in-memory persistence for now
- enable icloud backup
- ~~application version~~
- ~~change add icon on asset listing screen and detail screen to differentiate them~~
- beautify screens
- auto parse photo for transaction?
- ~~list event/transaction~~
- preference screen (eg how many event/transaction to show)
- ~~add logging~~
- add tools (communication, data export)
- summarize home screen