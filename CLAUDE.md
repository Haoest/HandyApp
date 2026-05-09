# HandyApp3

iOS/SwiftUI app for tracking physical assets the user owns (a house, a car, appliances, etc.) and the structured data attached to them.

## Layout

- `HandyApp3/HandyApp3App.swift`, `ContentView.swift` — SwiftUI app entry & root view
- `HandyApp3/Models/` — domain types (`Asset`, `AssetCategory`, `PropertyDefinition`, `PropertyValue`, `PropertyType`, `CompositeTypeDefinition`, `ComboListDefinition`, `AssetProperty`, `BuiltInTypes`)
- `HandyApp3/Controllers/` — `AssetStore` (single in-memory store; all mutations go through it) and `ContactResolver`
- `HandyApp3/SystemTypes/` — built-in composite types and combo lists, defined as extensions on `BuiltInTypes`
- `HandyApp3/Prototypes/` — prototype factories for canonical asset categories (`Appliance`, `Automobile`, `HousingUnit`)
- `HandyApp3/UserTypes/` — user-defined types (currently empty)
- `HandyApp3Tests/`, `HandyApp3UITests/` — XCTest targets

## Domain model in one paragraph

An `Asset` belongs to an `AssetCategory` and carries `PropertyValue`s keyed by `PropertyDefinition`s on the category, plus a list of per-instance `AssetProperty` entries (each with its own embedded definition). A `PropertyType` is either a `BasicType` (text/number/currency/date/contact), a `CompositeTypeDefinition` (a struct of named fields, recursive), or a `ComboListDefinition` (a pick-list of string options). Composite types and combo lists each have a system/user split: system fields/options are immutable, user ones are editable when `isUserExtensible` is true. Assets form a tree via `parent` / `children`; mutate the hierarchy only through `AssetStore`.

## Conventions

- **No file header comments.** Don't add the Xcode `// Created by ... on <date>` block to new Swift files. Start at the first `import`.
- **No author/date stamps in code or commit messages.**
- All store mutations go through `AssetStore`. `Asset._addChild` / `_removeChild` are package-private by convention — call them from the store, not from views.
- Built-in types are seeded via `AssetStore.seedBuiltInComboLists()` and `seedBuiltInTypes(scope:)`. Both are idempotent — safe to call at startup.
- New built-in composite types live in `SystemTypes/` as `extension BuiltInTypes`; new prototypes (category + default fields) live in `Prototypes/`.
- **Testing in conceptual phases:** write tests for behavior at boundaries (validation rules, store invariants, hierarchy/inheritance resolution) — skip tests for plain accessors or class shape. During a structural rewrite, don't nurse the existing test suite through intermediate steps; rewrite it once at the end of the phase that completes the rewrite.

## Open work

