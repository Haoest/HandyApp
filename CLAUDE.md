# HandyApp3

iOS/SwiftUI app for tracking physical assets the user owns (a house, a car, appliances, etc.) and the structured data attached to them.

## Layout

- `HandyApp3/HandyApp3App.swift`, `ContentView.swift` — SwiftUI app entry & root view
- `HandyApp3/Models/` — domain types (`Asset`, `TypeNode`, `AssetCategory` *(legacy, removed in Phase 4)*, `PropertyDefinition`, `PropertyValue`, `PropertyType`, `CompositeTypeDefinition`, `ComboListDefinition`, `AssetProperty`, `BuiltInTypes`)
- `HandyApp3/Controllers/` — `AssetStore` (single in-memory store; all mutations go through it) and `ContactResolver`
- `HandyApp3/SystemTypes/` — built-in seed code: composite *value* types (W × L, W × L × H), combo lists, and the IS-A type tree (`BuiltInTypeTree.swift`), all as extensions on `BuiltInTypes` / `AssetStore`
- `HandyApp3/UserTypes/` — user-defined types (currently empty)
- `HandyApp3Tests/`, `HandyApp3UITests/` — XCTest targets

## Domain model in one paragraph

An `Asset` is described by a `TypeNode` — a node in an IS-A tree (e.g. `Range` is-a `Appliance`). Each node has `localFields` (declared on it directly) and inherits its ancestors' fields via `allFields` (pure-append; no overrides). Abstract nodes like `Appliance` cannot be instantiated; only concrete descendants can. Assets carry `PropertyValue`s keyed by `PropertyDefinition`s from their type, plus a list of per-instance `AssetProperty` entries (each with its own embedded definition). A `PropertyType` is either a `BasicType` (text/number/currency/date/contact), a `CompositeTypeDefinition` (a struct of named fields used for *value* composites like W × L — distinct from `TypeNode`), or a `ComboListDefinition` (a pick-list of string options). Composite value types and combo lists have a system/user split: system fields/options are immutable, user ones are editable when `isUserExtensible` is true. Assets form a runtime containment tree via `Asset.parent` / `children` (separate from the type IS-A tree); mutate either hierarchy only through `AssetStore`. *(`AssetCategory` still exists transiently during the migration; removed in Phase 4.)*

## Conventions

- **No file header comments.** Don't add the Xcode `// Created by ... on <date>` block to new Swift files. Start at the first `import`.
- **No author/date stamps in code or commit messages.**
- All store mutations go through `AssetStore`. `Asset._addChild`/`_removeChild` and `TypeNode._addChild`/`_removeChild` are package-private by convention — call them from the store, not from views.
- Built-in seed APIs on `AssetStore`: `seedBuiltInComboLists()`, `seedBuiltInTypes(scope:)` (composite value types), and `seedBuiltInTypeTree()` (IS-A type tree — also seeds combo lists). All are idempotent and safe to call at startup.
- New built-in composite *value* types and combo lists live in `SystemTypes/` as `extension BuiltInTypes`. The built-in IS-A tree is built in `SystemTypes/BuiltInTypeTree.swift`.
- **Testing in conceptual phases:** write tests for behavior at boundaries (validation rules, store invariants, hierarchy/inheritance resolution) — skip tests for plain accessors or class shape. During a structural rewrite, don't nurse the existing test suite through intermediate steps; rewrite it once at the end of the phase that completes the rewrite.

## Open work

