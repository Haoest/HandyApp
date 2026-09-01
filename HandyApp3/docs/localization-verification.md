# Phase 7 — verification report

Run after Phases 0–6 (catalog rebuild, translation, built-in label localization).

## Automated checks — all clean

- **Catalog**: 416 keys (353 app-copy + 63 built-in `builtin.*` labels). Zero keys missing
  `es`/`fr`/`zh-Hans`. Zero `state` other than `translated`. Zero missing `comment`. Zero
  positional-argument mismatches between `en` and the other three languages.
- **"Duplicate" scan**: 18 same-text pairs found (e.g. `builtin.field.appliance.Purchase date`
  vs `builtin.field.residentialHousing.Purchase date`, both "Purchase date"). All are the
  intentional per-category `builtin.*` symbolic keys sharing English text by coincidence, not
  accidental catalog duplicates — each has its own id and can be re-worded independently later
  without touching the others.
- **Glossary conformance**: 3 substring hits on the "Thing" forbidden-synonym list, all false
  positives on inspection — French "quelque chose" / "autre chose" (the ordinary word for
  "something", unrelated to the product noun) and Spanish "elementos" in the receipt-scanner's
  "Select items" (about text blocks on a scanned receipt, not the product noun). Zero real
  violations.
- **Layout risk**: zero es/fr strings in a button/tab/picker/toggle/placeholder/section-header
  context exceeding English by more than 30%; zero zh-Hans strings longer (by character count)
  than their English source.
- **Build**: `swiftc -typecheck` against the real iOS 18.2 simulator SDK — zero errors.
  `swift test` — 692 tests (687 existing + 5 new `BuiltInLabelsTests`), 1 skipped, 1 failure —
  the same pre-existing `StoreIntegrityTests.testImportIsOnDiskWhenCallReturns` failure present
  on the unmodified branch tip before this work started, confirmed via `git stash` at the time.

## Not verified by this pass

Nothing in this environment can render SwiftUI or take a simulator screenshot (`swiftc
-typecheck` proves compilation, not layout, per this project's own CLAUDE.md). Visual
confirmation is yours to do in Xcode.

## Visual checklist

For each of `es`, `fr`, `zh-Hans` (Setup → Appearance → Language), and once more in English
after switching back:

1. **Timeline tab** — Coming up / History sections, the Cashflow pill, and Due Soon's
   long-press popover.
2. **Thing detail** — all four sub-tabs (Specs, Log, Photos, Inside), especially a built-in
   category like Appliance or Automobile so the new `builtin.*` field labels render.
3. **New thing / New category** flows — category picker, field list, the "N fields will be
   copied in" note.
4. **Category editor** — the field-diff summary lines ("N fields added/removed/reordered") and
   the delete confirmation dialog.
5. **Pick list editor** — a built-in list (Power source, Appliance type, Retailer) and the
   Add-an-option flow.
6. **Paywall** — hero text, benefit lines, the unlock button's price string.
7. **Setup → Deleted items** — a soft-deleted category, pick list, and thing.
8. **One Siri shortcut phrase** per shortcut (Settings → Siri, or Shortcuts app) — these carry
   the "Thing" wording change from Phase 4.
9. **Largest Dynamic Type size** (Settings → Accessibility → Display & Text Size) on at least
   the Timeline tab and Thing detail, since that's where layout risk would show first even
   though the automated length check came back clean.

Nothing else is blocking — this is confirmation, not a punch list of known issues.
