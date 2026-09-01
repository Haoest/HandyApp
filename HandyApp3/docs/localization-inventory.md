# Localization inventory — Phase 1

Every key in `HandyApp3/Localizable.xcstrings` (470 total — 455 original + 15 added in
Phase 3), its source call site(s), and its disposition for the Phase 4 rewrite. Built by tracing
each catalog key back to source:
- Format-specifier keys (`%@`/`%lld`) were matched by a wildcard pattern, since Xcode compiles
  Swift string interpolation into the positional catalog key.
- Plain keys were matched as an **exact double-quoted literal** (`"Key"` in source), not a bare
  substring — a first pass used substring matching and it was unusable: single/short-word keys
  like `Date`, `View`, `Type`, `Asset`, `Text` collided with hundreds of Swift type names and
  identifiers that are not the catalog string at all.
- **Both searches are Swift-escape-aware**: a catalog key's embedded `"` (e.g. `Delete "%@"?`) is
  matched against its *source* form `\"` — a first pass compared the unescaped catalog text
  directly against source and silently found nothing for any key containing a quote, which
  wrongly marked 10 keys orphaned. Two of them were confirmation-dialog text (`Type "reset" to
  confirm`, `Delete "%@"?`'s siblings) — exactly the strings a mechanical pass most needs to get
  right, since acting on that list would have deleted live safety copy. Caught by spot-checking
  outliers before Phase 4 touched anything; this version fixes both the escaping and a
  too-short interpolation-gap allowance that had the same false-orphan effect.
- Matches inside `///`/`//` comments don't count as a live call site — several apparent
  duplicates turned out to be a doc comment quoting a sheet's title, not a second copy of the UI
  text.

**Ledger:** 470 total → 358 rewrite in place, 15 merge into a canonical key
(14 groups, 2 of which have the losing member still live in code — see below), 11 delete
as accidental extractions or a confirmed-dead duplicate, 86 delete as orphaned (no live
source call site — leftovers of a renamed/removed screen, old "asset" wording, an old "Tools >
Export Data" menu path, a UserDefaults storage key, or a removed confirmation step — the import
flow dropped its "type import to confirm" step at some point and now only asks "Choose File";
the destructive-reset flow kept its type-to-confirm step).

## Merge groups — converge to one spelling in Phase 4

Casing rule (sentence case) picks the canonical form in every group below. Two groups have
**both** spellings live in different files today — Phase 4 must edit the losing call site, not
just delete a stale key:

- **`Belongs to`** ← canonical. Live at HandyApp3/Views/AssetParentPicker.swift:67, HandyApp3/Views/AssetParentPicker.swift:152.
  - absorbs `Belongs To` — no live call site, delete the key.
- **`Choose contact`** ← canonical. Live at HandyApp3/Views/CompositeEditView.swift:239, HandyApp3/Views/ThingSpecRows.swift:297.
  - absorbs `Choose Contact` — no live call site, delete the key.
  - absorbs `Choose contact…` — no live call site, delete the key.
- **`Choose a contact…`** ← canonical. Live at HandyApp3/Views/PropertyViews.swift:354.
  - absorbs `Choose a contact` — **also still live**, at HandyApp3/Views/AssetTransactionsViews.swift:341. Edit this call site to the canonical spelling.
- **`Delete category`** ← canonical. Live at HandyApp3/Views/CategoryEditorView.swift:270.
  - absorbs `Delete Category` — **also still live**, at HandyApp3/Views/CategoryEditorView.swift:77. Edit this call site to the canonical spelling.
- **`New category`** ← canonical. Live at HandyApp3/Views/CategoryNewView.swift:39.
  - absorbs `New Category` — no live call site, delete the key.
- **`New event`** ← canonical. Live at HandyApp3/Views/AssetEventsViews.swift:131.
  - absorbs `New Event` — no live call site, delete the key.
- **`Edit event`** ← canonical. Live at HandyApp3/Views/AssetEventsViews.swift:131.
  - absorbs `Edit Event` — no live call site, delete the key.
- **`Duplicate & edit`** ← canonical. Live at HandyApp3/Views/TimelineTab.swift:711.
  - absorbs `Duplicate & Edit` — **also still live**, at HandyApp3/Views/ThingDetailView.swift:817. Edit this call site to the canonical spelling.
- **`Log & edit`** ← canonical. Live at HandyApp3/Views/TimelineTab.swift:711.
  - absorbs `Log & Edit` — **also still live**, at HandyApp3/Views/ThingDetailView.swift:817. Edit this call site to the canonical spelling.
- **`Log now`** ← canonical. Live at HandyApp3/Views/ThingDetailView.swift:802.
  - absorbs `Log Now` — no live call site, delete the key.
- **`Factory reset`** ← canonical. Live at HandyApp3/Views/SetupTab.swift:239.
  - absorbs `Factory Reset` — **also still live**, at HandyApp3/Views/SetupTab.swift:438. Edit this call site to the canonical spelling.
- **`No deleted categories.`** ← canonical. Live at HandyApp3/Views/DeletedItems.swift:179.
  - absorbs `No Deleted Categories` — no live call site, delete the key.
- **`None · top level`** ← canonical. Live at HandyApp3/Views/AssetParentPicker.swift:70, HandyApp3/Views/AssetParentPicker.swift:180.
  - absorbs `None (top level)` — no live call site, delete the key.
- **`Late`** ← canonical. Live at HandyApp3/Views/ThingDetailView.swift:772, HandyApp3/Views/ThingsTab.swift:311.
  - absorbs `(Late)` — no live call site, delete the key.

## Flagged inconsistency — not a mechanical merge, needs a Phase 4 decision

- **"Custom field" vs "+ Custom field"** — the same add-a-custom-field action is labeled two
  ways: `Label("Custom field", systemImage: "text.badge.plus")` at
  [ThingDetailView.swift:369](../Views/ThingDetailView.swift) and
  `dashedButton("+ Custom field")` at
  [ThingDetailView.swift:438](../Views/ThingDetailView.swift). Pick one wording in Phase 4 — the
  `+` is redundant with the plus-badge `systemImage` on the other button, so `Custom field` is
  the likely keeper, but confirm against the rendered icon before changing either site.
  `Custom Field` (Title Case, zero live call sites) is a dead duplicate either way — delete it.

## Not user-facing — extracted by mistake, do not treat as UI copy

- **`Assets`** — matches only inside `AssetStore+Persistence.swift` and `StoreFileLayout.swift`,
  always as an on-disk directory name (`["Photos", "Definitions", "Assets", "Activity"]`) or a
  path component, never as a `Text`/`LocalizedStringKey`. Xcode's extraction grabbed it anyway.
  Delete the catalog key; **do not** rename the directory — that's the on-disk/iCloud layout and
  renaming it is a data-migration hazard, out of scope for a copy rebuild.

## Orphaned keys (delete — no live source call site)

These 86 keys have translated `es`/`fr`/`zh-Hans` values today, but the English text
doesn't appear as a live quoted literal anywhere in `HandyApp3/`. Most are leftovers of a
renamed/removed screen (the old "Categories tab" / "Events & Transactions" naming, pre-rename
"asset" wording, the dropped import-confirmation step); a few are internal storage keys or
debug-only strings extracted by mistake. Spot-check any that look surprising before deleting —
this list is mechanical, not hand-verified line by line (see the note above about what the
first mechanical pass got wrong).

- `%@: %@ paid out on %@. Next occurrence expected on %@.`
- `%@: %@ received on %@. Next occurrence expected on %@.`
- `%@: event happened on %@`
- `%@: event happened on %@. Next occurrence expected on %@.`
- `%@: payment %@ paid out on %@`
- `%@: payment %@ received on %@`
- `%lld items inside. Keep them as top-level assets, or delete everything.`
- `(automatically set to next interval)`
- `Add Event`
- `Add Property`
- `Add asset inside`
- `All existing data on this device will be permanently deleted and replaced with the contents of the imported file. Type "import" to continue.`
- `Amount`
- `Asset name`
- `Background`
- `Bulk Communication`
- `Category name`
- `Change Icon`
- `Choose Icon`
- `Create a category first in the Categories tab.`
- `Created assets, events, and transactions will show up here.`
- `Custom Field`
- `Date of Event`
- `Date of Transaction`
- `Default Values`
- `Delete Asset`
- `Delete Everything Inside`
- `Deleted Assets`
- `Deleted Categories`
- `Description`
- `Device Notification`
- `Due Date`
- `Duplicate Name`
- `Edit Property`
- `Edit Transaction`
- `Event title`
- `Events & Transactions`
- `Events Only`
- `Events and transactions logged on your assets will show up here.`
- `Export Data`
- `Filter`
- `Has Due Date`
- `Home`
- `Icon`
- `Keep Belongings`
- `Keep deleted items for`
- `Keep message after due date`
- `Late Only`
- `Logs`
- `New Asset`
- `New Property`
- `New Transaction`
- `No Activity`
- `No Assets`
- `No Categories`
- `No Contacts Found`
- `No Deleted Assets`
- `No Events or Transactions`
- `No top-level assets have a linked contact.`
- `None`
- `Notify before due date`
- `Optional notes`
- `Preference`
- `Properties`
- `Property name`
- `Recurrence`
- `Recurring`
- `Select Category`
- `Select…`
- `Send All`
- `Set value`
- `Show All`
- `Show message before due date`
- `Tap + to add your first asset.`
- `Tap + to create your first category.`
- `The category will be removed. Existing assets will not be affected.`
- `These values are copied into new assets created from this category.`
- `Title`
- `Tools`
- `Transaction`
- `Transactions Only`
- `Tree`
- `Type "import" to confirm`
- `View`
- `View Series`
- `Your data has been replaced with the imported file.`

## Accidental extractions / confirmed-dead duplicates (delete)

- `''`
- `'$'`
- `'%@'`
- `'+'`
- `'0.00'`
- `'·'`
- `'•••'`
- `'›'`
- `'−'`
- `'◷'`
- `'✓'`

## Degenerate format keys — call sites not traceable mechanically

These format-specifier keys are too short/generic for a wildcard pattern to locate reliably
(the gap between literal fragments matches almost anything). Find them by hand in Phase 4:

| Key | Comment | Note |
|---|---|---|
| `%lld` | A value displayed alongside a slider. | Likely the "keep deleted items for N days" slider — check `SetupScreens.swift`. |
| `+%lld more` | Overflow footer under a capped list of History rows on the Timeline tab. | Added in Phase 3 — call site is `Views/TimelineTab.swift:308`. |
| `%lld of %lld` | (none) | An "X of Y" progress/count pair — several plausible sites (paywall limits, field-copy progress). |
| `%lld days` | (none) | Likely the deleted-items retention period, paired with the `%lld` slider key above. |
| `in %@` | (none) | Almost certainly a relative-due-date string ("in 3 days"/"in 2 weeks") — cross-reference the now-fixed `whenText` in `TimelineTab.swift` (Phase 3 replaced it with `^[%lld day](inflect: true)` keys); this older key may be dead and foldable into that, verify by hand. |

## Full key ledger (rewrite in place)

The remaining 358 keys get their English rewritten against the glossary/voice/casing rule
in Phase 4 and retranslated in Phase 5; this table exists so Phase 4 can find each key's call
site(s) without re-deriving them.

| Key | Call site(s) |
|---|---|
| `%@ once · unlock` | HandyApp3/Views/PaywallView.swift:182 |
| `%lld of %lld things used` | HandyApp3/Models/SetupDigest.swift:34 |
| `%lld watched` | HandyApp3/Models/ThingLogDigest.swift:13, HandyApp3/Models/TimelineDigest.swift:7, HandyApp3/Models/TimelineDigest.swift:31 (+1 more) |
| `(not found)` | HandyApp3/Views/AssetTransactionsViews.swift:331, HandyApp3/Views/CompositeEditView.swift:233, HandyApp3/Views/PropertyViews.swift:352 (+1 more) |
| `(not in your contacts)` | HandyApp3/Views/SetupToolScreens.swift:124 |
| `+ Add field` | HandyApp3/Views/CategoryEditorView.swift:163, HandyApp3/Views/CategoryNewView.swift:123 |
| `+ Add thing inside` | HandyApp3/Views/ThingDetailView.swift:576 |
| `+ Custom field` | HandyApp3/Views/ThingDetailView.swift:438 |
| `+ Event` | HandyApp3/Views/ThingDetailView.swift:363, HandyApp3/Views/ThingDetailView.swift:490 |
| `+ Log` | HandyApp3/Views/TimelineTab.swift:169 |
| `+ Money` | HandyApp3/Views/ThingDetailView.swift:359, HandyApp3/Views/ThingDetailView.swift:489 |
| `+ New` | HandyApp3/Views/SetupScreens.swift:46, HandyApp3/Views/ThingsTab.swift:141 |
| `+ Photo` | HandyApp3/Views/ThingDetailView.swift:510 |
| `+%lld more` | HandyApp3/Views/TimelineTab.swift:308 |
| `100` | HandyApp3/Views/PropertyViews.swift:295 |
| `A category is a template. Its fields and its icon are copied into every thing you file ...` | HandyApp3/Views/SetupScreens.swift:123 |
| `A category named "%@" already exists.` | HandyApp3/Views/CategoryNewView.swift:74 |
| `A one-off. Turn this on for anything on a cycle.` | HandyApp3/Views/AssetEventsViews.swift:180, HandyApp3/Views/AssetTransactionsViews.swift:253 |
| `A pick list named "%@" already exists.` | HandyApp3/Views/PickListEditorView.swift:413 |
| `A structured field is filled in on the thing itself, one part at a time.` | HandyApp3/Views/PropertyViews.swift:164 |
| `A thing needs a category to copy its fields from. Create one under Setup → Categories.` | HandyApp3/Views/AssetCreateView.swift:330 |
| `Add %@ to save this.` | HandyApp3/Views/ThingSpecRows.swift:490 |
| `Add Asset` | HandyApp3/Intents/AddAssetIntent.swift:4, HandyApp3/Intents/HandyAppShortcuts.swift:24 |
| `Add Expense` | HandyApp3/Intents/AddTransactionIntent.swift:21, HandyApp3/Intents/HandyAppShortcuts.swift:51 |
| `Add Income` | HandyApp3/Intents/AddTransactionIntent.swift:38, HandyApp3/Intents/HandyAppShortcuts.swift:60 |
| `Add Named Asset` | HandyApp3/Intents/AddNamedAssetIntent.swift:4, HandyApp3/Intents/HandyAppShortcuts.swift:33 |
| `Add Photo` | HandyApp3/Views/ThingDetailView.swift:953 |
| `Add Transaction` | HandyApp3/Intents/AddTransactionIntent.swift:4, HandyApp3/Intents/HandyAppShortcuts.swift:42 |
| `Add a value` | HandyApp3/Views/PickListEditorView.swift:131, HandyApp3/Views/PickListEditorView.swift:465 |
| `Alert lead time` | HandyApp3/Views/AssetEventsViews.swift:240, HandyApp3/Views/AssetTransactionsViews.swift:313 |
| `All` | HandyApp3/Views/CategoryFilterChips.swift:23 |
| `All data has been cleared and the app has been restored to its initial state.` | HandyApp3/Views/SetupTab.swift:455 |
| `All fields` | HandyApp3/Views/ThingSpecRows.swift:498 |
| `Allow off-list answers` | HandyApp3/Views/PickListEditorView.swift:171, HandyApp3/Views/PickListEditorView.swift:493 |
| `Already bought it? Restore` | HandyApp3/Views/PaywallView.swift:170 |
| `Annually` | HandyApp3/Models/RecurrenceInterval.swift:8, HandyApp3/Models/RecurrenceInterval.swift:31 |
| `Another pick list already has that name.` | HandyApp3/Views/PickListEditorView.swift:53 |
| `App` | HandyApp3/Views/SetupTab.swift:207 |
| `App update required` | HandyApp3/Views/SetupTab.swift:68 |
| `Appearance` | HandyApp3/Views/SetupScreens.swift:315, HandyApp3/Views/SetupTab.swift:208 |
| `Appears this long before` | HandyApp3/Views/AssetEventsViews.swift:213, HandyApp3/Views/AssetTransactionsViews.swift:286 |
| `Ask Siri` | HandyApp3/Views/SetupTab.swift:211, HandyApp3/Views/SetupToolScreens.swift:308 |
| `Asset` | HandyApp3/Intents/AddTransactionIntent.swift:7, HandyApp3/Intents/AddTransactionIntent.swift:24, HandyApp3/Intents/AddTransactionIntent.swift:41 (+2 more) |
| `Asset Not Found` | HandyApp3/Views/TimelineTab.swift:92 |
| `Back` | HandyApp3/Views/AssetCreateView.swift:87 |
| `Baron Book` | HandyApp3/Views/PaywallView.swift:85 |
| `Baron Book %@ · %@` | HandyApp3/Views/SetupTab.swift:248 |
| `Basics` | HandyApp3/Views/PropertyViews.swift:230 |
| `Belongs to` | HandyApp3/Views/AssetParentPicker.swift:67, HandyApp3/Views/AssetParentPicker.swift:152 |
| `Bi-annually` | HandyApp3/Models/RecurrenceInterval.swift:32 |
| `Built-in values can't be renamed or removed — they're what the app seeded the list with.` | HandyApp3/Views/PickListEditorView.swift:102 |
| `Call` | HandyApp3/Views/ThingSpecRows.swift:288 |
| `Camera` | HandyApp3/Views/ThingDetailView.swift:956 |
| `Can be left blank.` | HandyApp3/Views/PropertyViews.swift:321 |
| `Cancel` | HandyApp3/Views/AssetCreateView.swift:264, HandyApp3/Views/AssetParentPicker.swift:143, HandyApp3/Views/AssetPhotosViews.swift:156 (+12 more) |
| `Caption` | HandyApp3/Views/AssetPhotosViews.swift:101 |
| `Careful` | HandyApp3/Views/SetupTab.swift:238 |
| `Categories` | HandyApp3/Views/CategoryEditorView.swift:40, HandyApp3/Views/SetupScreens.swift:122, HandyApp3/Views/SetupScreens.swift:413 (+1 more) |
| `Category` | HandyApp3/Views/AppRouter.swift:55 |
| `Category Not Found` | HandyApp3/Views/SetupScreens.swift:190 |
| `Change` | HandyApp3/Views/AssetTransactionsViews.swift:335, HandyApp3/Views/CompositeEditView.swift:239, HandyApp3/Views/ThingSpecRows.swift:297 |
| `Choose File` | HandyApp3/Views/SetupTab.swift:399 |
| `Choose a contact…` | HandyApp3/Views/PropertyViews.swift:354 |
| `Choose a symbol` | HandyApp3/Views/IconPickerView.swift:104 |
| `Choose contact` | HandyApp3/Views/CompositeEditView.swift:239, HandyApp3/Views/ThingSpecRows.swift:297 |
| `Clear` | HandyApp3/Views/AssetTransactionsViews.swift:336, HandyApp3/Views/CompositeEditView.swift:209, HandyApp3/Views/CompositeEditView.swift:241 (+2 more) |
| `Clear all parts` | HandyApp3/Views/CompositeEditView.swift:50 |
| `Clear the search or pick another category.` | HandyApp3/Views/ThingsTab.swift:191 |
| `Close` | HandyApp3/Views/PaywallView.swift:68 |
| `Coming up` | HandyApp3/Views/TimelineTab.swift:373 |
| `Contact` | HandyApp3/Models/StoredValue+Composite.swift:34 |
| `Cost 12 mo` | HandyApp3/Views/ThingDetailView.swift:331 |
| `Could not create` | HandyApp3/Views/AssetCreateView.swift:156 |
| `Couldn't find a receipt` | HandyApp3/Views/AssetPhotosViews.swift:148 |
| `Counts toward the Timeline's net figure, and toward Overdue once the date passes.` | HandyApp3/Views/AssetTransactionsViews.swift:266 |
| `Create` | HandyApp3/Views/AssetCreateView.swift:82, HandyApp3/Views/CategoryNewView.swift:40, HandyApp3/Views/PickListEditorView.swift:397 |
| `Custom` | HandyApp3/Views/AppRouter.swift:56 |
| `Custom field` | HandyApp3/Views/ThingDetailView.swift:369 |
| `Custom field on %@` | HandyApp3/Views/PickListEditorView.swift:211 |
| `Dark` | HandyApp3/Views/BaronTheme.swift:169, HandyApp3/Views/SetupTab.swift:87 |
| `Data` | HandyApp3/Views/SetupTab.swift:217 |
| `Data from the file you choose will be merged into what's already on this device. Nothin...` | HandyApp3/Views/SetupTab.swift:402 |
| `Date` | HandyApp3/Views/AssetEventsViews.swift:141, HandyApp3/Views/AssetTransactionsViews.swift:160 |
| `Definitions` | HandyApp3/Controllers/AssetStore+Persistence.swift:88, HandyApp3/Controllers/AssetStore+Persistence.swift:139, HandyApp3/Controllers/AssetStore+Persistence.swift:148 (+2 more) |
| `Delete` | HandyApp3/Views/ThingDetailView.swift:820, HandyApp3/Views/ThingDetailView.swift:1076 |
| `Delete "%@"?` | HandyApp3/Views/CategoryEditorView.swift:75, HandyApp3/Views/PickListEditorView.swift:40, HandyApp3/Views/ThingDetailView.swift:1075 |
| `Delete category` | HandyApp3/Views/CategoryEditorView.swift:270 |
| `Delete now` | HandyApp3/Views/DeletedItems.swift:149, HandyApp3/Views/DeletedItems.swift:205 |
| `Delete pick list` | HandyApp3/Views/PickListEditorView.swift:42, HandyApp3/Views/PickListEditorView.swift:231 |
| `Delete thing` | HandyApp3/Views/ThingDetailView.swift:373, HandyApp3/Views/ThingDetailView.swift:440 |
| `Deleted items` | HandyApp3/Views/SetupScreens.swift:435, HandyApp3/Views/SetupTab.swift:224 |
| `Deleting %@ deletes these too.` | HandyApp3/Views/ThingDetailView.swift:573 |
| `Done` | HandyApp3/Views/AssetPhotosViews.swift:115, HandyApp3/Views/SeriesOccurrencesSheet.swift:54 |
| `Due` | HandyApp3/Views/AssetEventsViews.swift:198, HandyApp3/Views/AssetTransactionsViews.swift:271 |
| `Due %@` | HandyApp3/Controllers/NotificationScheduler.swift:71, HandyApp3/Models/DueSeries.swift:94, HandyApp3/Models/DueSeries.swift:153 (+12 more) |
| `Duplicate` | HandyApp3/Views/SetupScreens.swift:173, HandyApp3/Views/TimelineTab.swift:701 |
| `Duplicate & edit` | HandyApp3/Views/TimelineTab.swift:711 |
| `Edit event` | HandyApp3/Views/AssetEventsViews.swift:131 |
| `Edit field` | HandyApp3/Views/PropertyViews.swift:152 |
| `Edit money record` | HandyApp3/Views/AssetTransactionsViews.swift:149 |
| `Edited after it was deleted, so it won't be removed on its own.` | HandyApp3/Views/DeletedItems.swift:43 |
| `Editing a category changes the template only. Existing things stay as they are until yo...` | HandyApp3/Views/SetupScreens.swift:179 |
| `Email` | HandyApp3/Views/SetupToolScreens.swift:25, HandyApp3/Views/ThingSpecRows.swift:292 |
| `End of history` | HandyApp3/Views/TimelineTab.swift:449 |
| `Enter Manually` | HandyApp3/Views/AssetPhotosViews.swift:149 |
| `Event` | HandyApp3/Views/QuickLogSheet.swift:126 |
| `Events` | HandyApp3/Views/AppRouter.swift:58 |
| `Everything, unlimited` | HandyApp3/Views/PaywallView.swift:90 |
| `Existing things keep what they have until you push this across. Values you've already e...` | HandyApp3/Views/CategoryEditorView.swift:206 |
| `Export` | HandyApp3/Views/SetupTab.swift:218 |
| `Export My Data` | HandyApp3/Intents/QuickActionDelegate.swift:13 |
| `Extras` | HandyApp3/Views/SetupTab.swift:231 |
| `Factory reset` | HandyApp3/Views/SetupTab.swift:239 |
| `Field` | HandyApp3/Views/CompositeEditView.swift:32 |
| `Field name` | HandyApp3/Views/CategoryEditorView.swift:383, HandyApp3/Views/PropertyViews.swift:190 |
| `Following the series — edit to take it over.` | HandyApp3/Views/AssetEventsViews.swift:207, HandyApp3/Views/AssetTransactionsViews.swift:280 |
| `Follows Settings › Display & Brightness.` | HandyApp3/Views/SetupScreens.swift:351 |
| `Free tier` | HandyApp3/Models/SetupDigest.swift:34, HandyApp3/Views/SetupTab.swift:248 |
| `Full Version restored.` | HandyApp3/Views/SetupTab.swift:269 |
| `Full version` | HandyApp3/Models/SetupDigest.swift:27, HandyApp3/Views/SetupTab.swift:248 |
| `Has to be filled in before the thing can be saved.` | HandyApp3/Views/PropertyViews.swift:320 |
| `History` | HandyApp3/Views/ThingDetailView.swift:803, HandyApp3/Views/TimelineTab.swift:421 |
| `How the app looks, and what language it speaks.` | HandyApp3/Views/SetupScreens.swift:316 |
| `Import` | HandyApp3/Views/SetupTab.swift:221 |
| `Import Complete` | HandyApp3/Views/SetupTab.swift:425 |
| `Import Data` | HandyApp3/Views/SetupTab.swift:398 |
| `Import Failed` | HandyApp3/Views/SetupTab.swift:430 |
| `Inside` | HandyApp3/Views/ThingDetailView.swift:17 |
| `Kept until you restore it · ^[%lld value](inflect: true)` | HandyApp3/Views/DeletedItems.swift:242 |
| `Kept until you restore or delete it` | HandyApp3/Views/DeletedItems.swift:161, HandyApp3/Views/DeletedItems.swift:216 |
| `Language` | HandyApp3/Views/SetupScreens.swift:362 |
| `Late` | HandyApp3/Views/ThingDetailView.swift:772, HandyApp3/Views/ThingsTab.swift:311 |
| `Later this month` | HandyApp3/Views/TimelineTab.swift:597 |
| `Light` | HandyApp3/Views/BaronTheme.swift:168, HandyApp3/Views/SetupTab.swift:86 |
| `List name` | HandyApp3/Views/PickListEditorView.swift:61, HandyApp3/Views/PickListEditorView.swift:402 |
| `Log` | HandyApp3/Views/ThingDetailView.swift:15 |
| `Log & edit` | HandyApp3/Views/TimelineTab.swift:711 |
| `Log it` | HandyApp3/Views/TimelineTab.swift:701 |
| `Log now` | HandyApp3/Views/ThingDetailView.swift:802 |
| `Log something` | HandyApp3/Views/QuickLogSheet.swift:66 |
| `Logging one occurrence offers the next.` | HandyApp3/Views/AssetEventsViews.swift:179, HandyApp3/Views/AssetTransactionsViews.swift:252 |
| `Match device` | HandyApp3/Views/BaronTheme.swift:167, HandyApp3/Views/SetupTab.swift:85 |
| `Max length` | HandyApp3/Views/PropertyViews.swift:293 |
| `Message` | HandyApp3/Views/SetupToolScreens.swift:75 |
| `Message everyone` | HandyApp3/Views/SetupTab.swift:232, HandyApp3/Views/SetupToolScreens.swift:61 |
| `Money in` | HandyApp3/Views/AssetTransactionsViews.swift:222, HandyApp3/Views/TimelineTab.swift:510 |
| `Money out` | HandyApp3/Views/AssetTransactionsViews.swift:218, HandyApp3/Views/TimelineTab.swift:510 |
| `Monthly` | HandyApp3/Models/RecurrenceInterval.swift:5, HandyApp3/Models/RecurrenceInterval.swift:28 |
| `More fields` | HandyApp3/Views/ThingSpecRows.swift:498 |
| `Name` | HandyApp3/Intents/AddNamedAssetIntent.swift:8, HandyApp3/Views/AssetCreateView.swift:125, HandyApp3/Views/CategoryEditorView.swift:109 (+4 more) |
| `Name already used` | HandyApp3/Views/CategoryNewView.swift:71, HandyApp3/Views/PickListEditorView.swift:50, HandyApp3/Views/PickListEditorView.swift:410 |
| `New %@` | HandyApp3/Views/AssetCreateView.swift:81, HandyApp3/Views/AssetCreateView.swift:273, HandyApp3/Views/AssetEventsViews.swift:131 (+8 more) |
| `New category` | HandyApp3/Views/CategoryNewView.swift:39 |
| `New event` | HandyApp3/Views/AssetEventsViews.swift:131 |
| `New field` | HandyApp3/Views/PropertyViews.swift:152 |
| `New money record` | HandyApp3/Views/AssetTransactionsViews.swift:149 |
| `New pick list` | HandyApp3/Views/PickListEditorView.swift:396 |
| `New thing` | HandyApp3/Views/AssetCreateView.swift:81, HandyApp3/Views/AssetCreateView.swift:273 |
| `Next %@` | HandyApp3/Views/ThingDetailView.swift:328, HandyApp3/Views/ThingDetailView.swift:586, HandyApp3/Views/ThingDetailView.swift:738 (+1 more) |
| `Next due` | HandyApp3/Views/ThingDetailView.swift:328 |
| `Next two weeks` | HandyApp3/Views/TimelineTab.swift:596 |
| `No categories yet` | HandyApp3/Views/AssetCreateView.swift:327 |
| `No contacts yet. Give a thing a contact field — an owner, a plumber, a landlord — and t...` | HandyApp3/Views/SetupToolScreens.swift:89 |
| `No deleted categories.` | HandyApp3/Views/DeletedItems.swift:179 |
| `No deleted pick lists.` | HandyApp3/Views/DeletedItems.swift:234 |
| `No fields yet. Things filed here will start blank.` | HandyApp3/Views/CategoryEditorView.swift:155, HandyApp3/Views/CategoryNewView.swift:115 |
| `No phone number or email on this contact.` | HandyApp3/Views/SetupToolScreens.swift:134 |
| `No pick lists yet. Make one in Setup › Pick lists to offer a fixed set of answers.` | HandyApp3/Views/PropertyViews.swift:243 |
| `No previous purchase was found for this Apple ID.` | HandyApp3/Views/SetupTab.swift:270 |
| `No symbol matches "%@".` | HandyApp3/Views/IconPickerView.swift:72 |
| `No things match. Clear the search or pick another category.` | HandyApp3/Views/QuickLogSheet.swift:88 |
| `No things yet` | HandyApp3/Views/ThingsTab.swift:56 |
| `None · top level` | HandyApp3/Views/AssetParentPicker.swift:70, HandyApp3/Views/AssetParentPicker.swift:180 |
| `Not enabled` | HandyApp3/Views/SetupTab.swift:64 |
| `Not on the list? Type it in — it'll be added to %@.` | HandyApp3/Views/AssetCreateView.swift:117 |
| `Notes` | HandyApp3/SystemTypes/BuiltInCategories.swift:33, HandyApp3/SystemTypes/BuiltInCategories.swift:107, HandyApp3/Views/AssetEventsViews.swift:144 (+1 more) |
| `Nothing deleted. Things you delete wait here before they're removed for good.` | HandyApp3/Views/DeletedItems.swift:119 |
| `Nothing filled in yet.` | HandyApp3/Views/CompositeEditView.swift:37 |
| `Nothing logged yet. Money and events you record show up here.` | HandyApp3/Views/ThingDetailView.swift:475 |
| `Nothing matches` | HandyApp3/Views/ThingsTab.swift:188 |
| `Nothing nested inside %@ yet.` | HandyApp3/Views/ThingDetailView.swift:572 |
| `Nothing yet` | HandyApp3/Views/TimelineTab.swift:468 |
| `Notify me on this device` | HandyApp3/Views/AssetEventsViews.swift:230, HandyApp3/Views/AssetTransactionsViews.swift:303 |
| `OK` | HandyApp3/Views/AssetCreateView.swift:160, HandyApp3/Views/CategoryEditorView.swift:89, HandyApp3/Views/CategoryNewView.swift:72 (+7 more) |
| `Off means this is history only — it never appears on the Timeline.` | HandyApp3/Views/AssetEventsViews.swift:194, HandyApp3/Views/AssetTransactionsViews.swift:267 |
| `Oil change, inspection, repair…` | HandyApp3/Views/AssetEventsViews.swift:137 |
| `On` | HandyApp3/Views/SetupTab.swift:70 |
| `One payment lifts every limit. The free tier holds %lld things, and %lld events and mon...` | HandyApp3/Models/SetupDigest.swift:36 |
| `One payment. No subscription, and it covers every device on your Apple ID.` | HandyApp3/Views/PaywallView.swift:113 |
| `One set of choices, reused by any field. Edit a value here and every thing using it fol...` | HandyApp3/Views/SetupScreens.swift:220 |
| `One-off · %@` | HandyApp3/Views/ThingDetailView.swift:740 |
| `Only the values above can be chosen.` | HandyApp3/Views/PickListEditorView.swift:498 |
| `Only the values above can be chosen. Anything already stored is left as it is.` | HandyApp3/Views/PickListEditorView.swift:176 |
| `Open Asset` | HandyApp3/Intents/HandyAppShortcuts.swift:13, HandyApp3/Intents/OpenAssetIntent.swift:4 |
| `Open the transaction editor to enter the details yourself.` | HandyApp3/Views/AssetPhotosViews.swift:158 |
| `Optional` | HandyApp3/Views/AssetEventsViews.swift:145, HandyApp3/Views/AssetTransactionsViews.swift:165, HandyApp3/Views/PropertyViews.swift:343 (+1 more) |
| `Overdue` | HandyApp3/Views/TimelineTab.swift:186, HandyApp3/Views/TimelineTab.swift:594 |
| `Photo` | HandyApp3/Views/AssetPhotosViews.swift:111, HandyApp3/Views/ThingDetailView.swift:367 |
| `Photo Library` | HandyApp3/Views/ThingDetailView.swift:954 |
| `Photos` | HandyApp3/Controllers/AssetStore+Persistence.swift:88, HandyApp3/Controllers/AssetStore+Persistence.swift:148, HandyApp3/Controllers/AssetStore+Persistence.swift:283 (+3 more) |
| `Pick List Not Found` | HandyApp3/Views/SetupScreens.swift:288 |
| `Pick lists` | HandyApp3/Views/PickListEditorView.swift:29, HandyApp3/Views/PropertyViews.swift:248, HandyApp3/Views/SetupScreens.swift:219 (+2 more) |
| `Purchase Failed` | HandyApp3/Views/PaywallView.swift:52 |
| `Push to ^[%lld thing](inflect: true)` | HandyApp3/Views/CategoryEditorView.swift:230 |
| `Quarterly` | HandyApp3/Models/RecurrenceInterval.swift:6, HandyApp3/Models/RecurrenceInterval.swift:29 |
| `Records` | HandyApp3/Views/ThingDetailView.swift:332, HandyApp3/Views/ThingsTab.swift:331 |
| `Relationship` | HandyApp3/Views/AppRouter.swift:60 |
| `Remove field` | HandyApp3/Views/ThingSpecRows.swift:60 |
| `Removed for good in ^[%lld day](inflect: true)` | HandyApp3/Views/DeletedItems.swift:99 |
| `Rename` | HandyApp3/Views/ThingDetailView.swift:370, HandyApp3/Views/ThingDetailView.swift:902 |
| `Rename field` | HandyApp3/Views/ThingSpecRows.swift:57 |
| `Rent, repair, insurance…` | HandyApp3/Views/AssetTransactionsViews.swift:155 |
| `Repeats` | HandyApp3/Views/AssetEventsViews.swift:177, HandyApp3/Views/AssetTransactionsViews.swift:250 |
| `Required` | HandyApp3/Views/CategoryEditorView.swift:365, HandyApp3/Views/CategoryNewView.swift:156, HandyApp3/Views/PropertyViews.swift:316 |
| `Required on new things` | HandyApp3/Views/CategoryEditorView.swift:423 |
| `Reset` | HandyApp3/Views/SetupTab.swift:442 |
| `Reset Complete` | HandyApp3/Views/SetupTab.swift:452 |
| `Restore` | HandyApp3/Views/DeletedItems.swift:140, HandyApp3/Views/DeletedItems.swift:199, HandyApp3/Views/DeletedItems.swift:244 |
| `Restore Purchases` | HandyApp3/Views/SetupTab.swift:457 |
| `Restore anything from Deleted items, however many things you already have.` | HandyApp3/Views/PaywallView.swift:112 |
| `Restore anything you deleted by mistake. Whatever is still here after %lld days is remo...` | HandyApp3/Views/SetupScreens.swift:436 |
| `Restore purchase` | HandyApp3/Models/SetupDigest.swift:29 |
| `Save` | HandyApp3/Views/AssetEventsViews.swift:132, HandyApp3/Views/AssetTransactionsViews.swift:150, HandyApp3/Views/PropertyViews.swift:153 (+1 more) |
| `Say "Hey Siri" followed by any of these, anywhere on your device.` | HandyApp3/Views/SetupToolScreens.swift:309 |
| `Scanning…` | HandyApp3/Views/AssetPhotosViews.swift:143 |
| `Search symbols` | HandyApp3/Views/IconPickerView.swift:115 |
| `Search things` | HandyApp3/Views/AssetParentPicker.swift:168, HandyApp3/Views/QuickLogSheet.swift:77 |
| `Search things, specs, categories` | HandyApp3/Views/ThingsTab.swift:161 |
| `See the full version` | HandyApp3/Models/SetupDigest.swift:37 |
| `Select Items` | HandyApp3/Views/ReceiptBlockSelectionView.swift:37 |
| `Semi-annually` | HandyApp3/Models/RecurrenceInterval.swift:30 |
| `Send` | HandyApp3/Views/SetupToolScreens.swift:168 |
| `Send to ^[%lld contact](inflect: true)` | HandyApp3/Views/SetupToolScreens.swift:168 |
| `Series` | HandyApp3/Views/SeriesOccurrencesSheet.swift:50 |
| `Set a date` | HandyApp3/Views/PropertyViews.swift:373 |
| `Setup` | HandyApp3/Views/ContentView.swift:20, HandyApp3/Views/SetupScreens.swift:118, HandyApp3/Views/SetupScreens.swift:215 (+5 more) |
| `Show earlier` | HandyApp3/Views/TimelineTab.swift:449 |
| `Show things` | HandyApp3/Views/SetupScreens.swift:171 |
| `Shows up under Coming up, and counts toward Overdue once the date passes.` | HandyApp3/Views/AssetEventsViews.swift:193 |
| `Siri still listens for "asset" — that's the wording the shortcuts were built with.` | HandyApp3/Views/SetupToolScreens.swift:319 |
| `Something else` | HandyApp3/Views/AssetCreateView.swift:109, HandyApp3/Views/CompositeEditView.swift:309, HandyApp3/Views/ThingSpecRows.swift:391 |
| `Specs` | HandyApp3/Views/ThingDetailView.swift:14 |
| `Starting value` | HandyApp3/Views/PropertyViews.swift:162 |
| `Stays overdue this long after` | HandyApp3/Views/AssetEventsViews.swift:214, HandyApp3/Views/AssetTransactionsViews.swift:287 |
| `Stays this way whatever the device is set to.` | HandyApp3/Views/SetupScreens.swift:352 |
| `Step 1 of 2 — pick a category template` | HandyApp3/Views/AssetCreateView.swift:288 |
| `Step 1 of 2 — which thing is this for?` | HandyApp3/Views/QuickLogSheet.swift:74 |
| `Step 2 of 2 — %@` | HandyApp3/Views/AssetCreateView.swift:89, HandyApp3/Views/QuickLogSheet.swift:121 |
| `Step 2 of 2 — one-off by default; you can switch on repeats in the next step.` | HandyApp3/Views/QuickLogSheet.swift:121 |
| `Still used by ^[%lld thing](inflect: true), so it's kept` | HandyApp3/Views/DeletedItems.swift:214 |
| `Structured` | HandyApp3/Views/PropertyViews.swift:236 |
| `Synced %@` | HandyApp3/Views/SetupTab.swift:74 |
| `System Default` | HandyApp3/Models/AppPreference.swift:31 |
| `Tap + New to add the first thing you own.` | HandyApp3/Views/ThingsTab.swift:58 |
| `Tap + New to create a list of reusable choices.` | HandyApp3/Views/SetupScreens.swift:223 |
| `Tap + New to create your first category.` | HandyApp3/Views/SetupScreens.swift:126 |
| `Tap a photo to caption it, or scan a receipt into a money record.` | HandyApp3/Views/ThingDetailView.swift:523 |
| `Tap the blocks that contain the items and total.` | HandyApp3/Views/ReceiptBlockSelectionView.swift:17 |
| `Template changed` | HandyApp3/Views/CategoryEditorView.swift:197 |
| `Template field on %@` | HandyApp3/Views/PickListEditorView.swift:210 |
| `Template fields` | HandyApp3/Views/CategoryEditorView.swift:124, HandyApp3/Views/CategoryNewView.swift:104 |
| `Templates` | HandyApp3/Views/SetupTab.swift:196 |
| `Text` | HandyApp3/Views/ThingSpecRows.swift:289 |
| `The category will be removed. Existing things will not be affected.` | HandyApp3/Views/CategoryEditorView.swift:83 |
| `The imported file has been merged into your data. Existing records were left unchanged;...` | HandyApp3/Views/SetupTab.swift:428 |
| `The most characters this field can hold, up to %lld.` | HandyApp3/Views/PropertyViews.swift:302 |
| `Theme` | HandyApp3/Views/SetupScreens.swift:327 |
| `These fields are copied into every thing filed here. You can add more to a single thing...` | HandyApp3/Views/CategoryNewView.swift:47 |
| `These values are copied into new things created from this category.` | HandyApp3/Views/CategoryEditorView.swift:176 |
| `Thing Not Found` | HandyApp3/Views/ThingDetailView.swift:88, HandyApp3/Views/ThingDetailView.swift:1071, HandyApp3/Views/ThingsTab.swift:80 |
| `Thing inside` | HandyApp3/Views/ThingDetailView.swift:368 |
| `Things` | HandyApp3/Views/ContentView.swift:17, HandyApp3/Views/SetupScreens.swift:412, HandyApp3/Views/ThingsTab.swift:134 |
| `Things already using this list keep their stored values — it only disappears from futur...` | HandyApp3/Views/PickListEditorView.swift:48 |
| `Things you add, and the records you log against them, show up here.` | HandyApp3/Views/TimelineTab.swift:470 |
| `This asset no longer exists.` | HandyApp3/Views/TimelineTab.swift:93 |
| `This category no longer exists.` | HandyApp3/Views/SetupScreens.swift:191 |
| `This contact isn't on the phone any more, so there's nothing to send to.` | HandyApp3/Views/SetupToolScreens.swift:133 |
| `This field type can't be edited here.` | HandyApp3/Views/ThingSpecRows.swift:113 |
| `This file isn't an exported backup — it looks like the app's own internal store file, n...` | HandyApp3/Controllers/AssetStore+Persistence.swift:48 |
| `This part can't be edited here.` | HandyApp3/Views/CompositeEditView.swift:123 |
| `This pick list no longer exists.` | HandyApp3/Views/SetupScreens.swift:289 |
| `This series has ^[%lld event](inflect: true).` | HandyApp3/Views/AssetEventsViews.swift:151 |
| `This series has ^[%lld record](inflect: true).` | HandyApp3/Views/AssetTransactionsViews.swift:171 |
| `This thing has no fields yet. Add one below, or give its category a template.` | HandyApp3/Views/ThingDetailView.swift:436 |
| `This thing no longer exists.` | HandyApp3/Views/ThingDetailView.swift:90, HandyApp3/Views/ThingDetailView.swift:1072, HandyApp3/Views/ThingsTab.swift:81 |
| `This week` | HandyApp3/Views/TimelineTab.swift:595 |
| `This will permanently delete all data on this device and in iCloud. Consider exporting ...` | HandyApp3/Views/SetupTab.swift:450 |
| `Timeline` | HandyApp3/Views/ContentView.swift:14, HandyApp3/Views/TimelineTab.swift:163 |
| `Transactions` | HandyApp3/Views/AppRouter.swift:59 |
| `Type` | HandyApp3/SystemTypes/BuiltInCategories.swift:25, HandyApp3/Views/AssetCreateView.swift:46, HandyApp3/Views/AssetCreateView.swift:94 (+1 more) |
| `Type "reset" to confirm` | HandyApp3/Views/SetupTab.swift:439 |
| `Type & default value` | HandyApp3/Views/CategoryEditorView.swift:434 |
| `Type a message…` | HandyApp3/Views/SetupToolScreens.swift:76 |
| `Type · required` | HandyApp3/Views/AssetCreateView.swift:94 |
| `Typing a new value adds it to this list.` | HandyApp3/Views/PickListEditorView.swift:175, HandyApp3/Views/PickListEditorView.swift:497 |
| `Unlimited events and money records on every thing, instead of ^[%lld record](inflect: t...` | HandyApp3/Views/PaywallView.swift:111 |
| `Unlimited things and records. Thanks for buying.` | HandyApp3/Models/SetupDigest.swift:28 |
| `Unlimited things — the free tier stops at ^[%lld thing](inflect: true).` | HandyApp3/Views/PaywallView.swift:110 |
| `Unlock the full version` | HandyApp3/Views/PaywallView.swift:186 |
| `Update existing things` | HandyApp3/Views/CategoryEditorView.swift:85 |
| `Update the app to keep editing — changes aren't being saved` | HandyApp3/Views/ContentView.swift:40 |
| `Updated ^[%lld thing](inflect: true).` | HandyApp3/Views/CategoryEditorView.swift:263, HandyApp3/Views/CategoryEditorView.swift:265 |
| `Updated ^[%lld thing](inflect: true). Cleared ^[%lld value](inflect: true) that no long...` | HandyApp3/Views/CategoryEditorView.swift:263 |
| `Use Selection` | HandyApp3/Views/ReceiptBlockSelectionView.swift:44 |
| `Used by` | HandyApp3/Views/PickListEditorView.swift:196 |
| `Value` | HandyApp3/Views/PickListEditorView.swift:320, HandyApp3/Views/PickListEditorView.swift:441, HandyApp3/Views/PropertyViews.swift:162 |
| `Values` | HandyApp3/Views/PickListEditorView.swift:75, HandyApp3/Views/PickListEditorView.swift:420 |
| `Waiting for iCloud…` | HandyApp3/Views/ContentView.swift:58, HandyApp3/Views/SetupTab.swift:69 |
| `Watch it on the timeline` | HandyApp3/Views/AssetEventsViews.swift:191, HandyApp3/Views/AssetTransactionsViews.swift:264 |
| `Weekly` | HandyApp3/Models/RecurrenceInterval.swift:4, HandyApp3/Models/RecurrenceInterval.swift:27 |
| `What do you call it?` | HandyApp3/Views/AssetCreateView.swift:127 |
| `What happened` | HandyApp3/Views/AssetEventsViews.swift:136, HandyApp3/Views/AssetTransactionsViews.swift:154 |
| `What kind?` | HandyApp3/Views/QuickLogSheet.swift:67 |
| `What would you like to name the new asset?` | HandyApp3/Intents/AddNamedAssetIntent.swift:9 |
| `What's Inside` | HandyApp3/Views/AppRouter.swift:61 |
| `Who it was with` | HandyApp3/Views/AssetTransactionsViews.swift:328 |
| `Write once, then pick who hears it. Each message opens in its own app so you can read i...` | HandyApp3/Views/SetupToolScreens.swift:62 |
| `You're at the free tier's limit of %lld events and money records on this thing.` | HandyApp3/Views/PaywallView.swift:15 |
| `You're at the free tier's limit of %lld things.` | HandyApp3/Views/PaywallView.swift:13 |
| `Your phone opens one message at a time. Come back here after sending each one.` | HandyApp3/Views/SetupToolScreens.swift:183 |
| `Your plan` | HandyApp3/Models/SetupDigest.swift:26 |
| `^[%lld day](inflect: true)` | HandyApp3/Views/DeletedItems.swift:99, HandyApp3/Views/RecordSheetParts.swift:226, HandyApp3/Views/TimelineTab.swift:652 (+1 more) |
| `^[%lld day](inflect: true) late` | HandyApp3/Views/TimelineTab.swift:652 |
| `^[%lld event](inflect: true) added` | HandyApp3/Views/TimelineTab.swift:603 |
| `^[%lld field](inflect: true)` | HandyApp3/Views/AssetCreateView.swift:148, HandyApp3/Views/AssetCreateView.swift:304, HandyApp3/Views/CategoryEditorView.swift:212 (+5 more) |
| `^[%lld field](inflect: true) added` | HandyApp3/Views/CategoryEditorView.swift:212 |
| `^[%lld field](inflect: true) copied in` | HandyApp3/Views/AssetCreateView.swift:304 |
| `^[%lld field](inflect: true) from %@ will be copied in, ready to fill.` | HandyApp3/Views/AssetCreateView.swift:148 |
| `^[%lld field](inflect: true) removed` | HandyApp3/Views/CategoryEditorView.swift:213 |
| `^[%lld field](inflect: true) renamed or retyped` | HandyApp3/Views/CategoryEditorView.swift:214 |
| `^[%lld field](inflect: true) reordered` | HandyApp3/Views/CategoryEditorView.swift:215 |
| `^[%lld item](inflect: true) inside will be deleted too.` | HandyApp3/Views/ThingDetailView.swift:1080 |
| `^[%lld option](inflect: true)` | HandyApp3/Views/SetupScreens.swift:243, HandyApp3/Views/SetupScreens.swift:245 |
| `^[%lld option](inflect: true) · %lld built in` | HandyApp3/Views/SetupScreens.swift:245 |
| `^[%lld photo](inflect: true) added` | HandyApp3/Views/TimelineTab.swift:603 |
| `^[%lld stored value](inflect: true) no longer fits its field's new type and will be cle...` | HandyApp3/Views/CategoryEditorView.swift:219 |
| `^[%lld thing](inflect: true)` | HandyApp3/Views/CategoryEditorView.swift:41, HandyApp3/Views/CategoryEditorView.swift:202, HandyApp3/Views/CategoryEditorView.swift:230 (+7 more) |
| `^[%lld thing](inflect: true) added` | HandyApp3/Views/TimelineTab.swift:606 |
| `^[%lld thing](inflect: true) inside · deleted with it` | HandyApp3/Views/DeletedItems.swift:157 |
| `^[%lld thing](inflect: true) would change` | HandyApp3/Views/CategoryEditorView.swift:202 |
| `^[%lld transaction](inflect: true) added` | HandyApp3/Views/TimelineTab.swift:605 |
| `e.g. Appliance` | HandyApp3/Views/CategoryNewView.swift:92 |
| `e.g. Condition` | HandyApp3/Views/PickListEditorView.swift:403 |
| `e.g. Serial number` | HandyApp3/Views/PropertyViews.swift:192 |
| `iCloud unavailable` | HandyApp3/Views/SetupTab.swift:66 |
| `in ^[%lld day](inflect: true)` | HandyApp3/Views/DeletedItems.swift:99, HandyApp3/Views/TimelineTab.swift:654 |
| `newest first` | HandyApp3/Views/TimelineTab.swift:425 |
| `not at all` | HandyApp3/Views/AssetEventsViews.swift:214, HandyApp3/Views/AssetTransactionsViews.swift:287 |
| `on the day` | HandyApp3/Views/AssetEventsViews.swift:213, HandyApp3/Views/AssetTransactionsViews.swift:286 |
| `same day` | HandyApp3/Views/AssetEventsViews.swift:240, HandyApp3/Views/AssetTransactionsViews.swift:313 |
| `today` | HandyApp3/Views/TimelineTab.swift:653 |
| `watched` | HandyApp3/Views/ThingDetailView.swift:742 |
