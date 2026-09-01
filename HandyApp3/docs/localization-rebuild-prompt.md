# Rebuild every user-facing string in Baron Book (en / es / fr / zh-Hans)

You are rewriting the app's entire user-facing copy and its three translations. The
English is stale and inconsistent; the translations are worse — they translate copy the
app no longer shows. Treat the catalog as something you are re-authoring, not patching.

## Goal

Every string a user can see reads as one voice, uses one term per concept, and is
correct and idiomatic in `en`, `es`, `fr`, and `zh-Hans`. Built-in category/field/option
labels are localized for display without touching stored data.

### In scope
- `HandyApp3/Localizable.xcstrings` — all 455 keys.
- All 35 files in `HandyApp3/Views/` plus `HandyApp3/ContentView.swift`.
- `HandyApp3/Intents/` — AppIntent titles, parameter dialogs, and the 6 shortcuts /
  18 Siri phrases in `HandyAppShortcuts.swift`, plus
  `QuickActionDelegate.swift:13`.
- `HandyApp3/Controllers/NotificationScheduler.swift` — notification bodies.
- `HandyApp3/Controllers/AssetStore+Persistence.swift:44-49` — the one `LocalizedError`.
- `HandyApp3/Views/PaywallView.swift` and `Products.storekit` display name/description.
- Display-only labels for `HandyApp3/SystemTypes/` + `Models/BuiltInTypes.swift`.
- A new `InfoPlist.xcstrings` for the camera/contacts usage descriptions.
- `knownRegions` in `HandyApp3.xcodeproj/project.pbxproj`.

### Out of scope
- App Store Connect metadata, screenshots, the app name "Baron Book" (never translated).
- Language endonyms in `Models/AppPreference.swift:30-36` (`Español`, `Français`,
  `简体中文` stay as written; only `System Default` is translatable).
- A fifth language. Any schema/DTO change beyond the optional field named in Phase 6.
- Layout/visual redesign. Renaming Swift types (`Asset`, `AssetStore`, `AssetProperty`
  keep their names — the noun decision is about *copy*, not code).

## Hard constraints

- **Xcode 16 file-system-synchronized groups.** New Swift files are picked up from disk;
  do not add file references to `.pbxproj`. The *only* permitted `.pbxproj` edits are
  `knownRegions` and the two `INFOPLIST_KEY_NS*UsageDescription` values.
- **`swift test` is the headless test path** (`swift test`, ~485 tests, ~11s). The package
  target (`Package.swift:20-26`) compiles `Models/`, `Controllers/`, `SystemTypes/`,
  `Intents/AssetNameMatcher.swift`, `Views/HomeActivityDigest.swift`. **No `SwiftUI` or
  `UIKit` import — and therefore no `LocalizedStringKey` — may enter those paths.**
  `String(localized:)` and `LocalizedStringResource` are Foundation and already compile
  there (`Models/SetupDigest.swift:26-37` proves it). Use those.
- **Never write a localized string into a persisted `name`.** `SnapshotReconciler`
  merges `CategoryDTO`/`ComboListDTO`/`CompositeTypeDTO` headers as whole-record LWW on
  `modifyDate` (`SnapshotReconciler.swift:144,160,173`), so a localized `name` would
  propagate one device's locale to every other device. `StoredValue.composite` is keyed
  **by field name** (`Models/StoredValue.swift:12`), so renaming `Width`/`Length`/
  `Height`/`Unit` in a definition orphans every stored composite value.
- **Do not touch `BuiltInTypes.deterministicID` key literals.** Keys like
  `"field.appliance.Purchase date"` hash the old English casing into a canonical UUID.
  Fixing a display label must not change the key string.
- Visual confirmation happens in Xcode, by the user. Do not launch a simulator.

## Terminology glossary — lock this first, then never deviate

One term per concept, app-wide, in every language. Forbidden synonyms are banned in copy
even when they read better in one sentence.

| EN (canonical) | Definition | Forbidden synonyms | es | fr | zh-Hans |
|---|---|---|---|---|---|
| **Thing** | A physical object the user owns. | asset, item, object, possession, stuff | artículo | bien | 物品 |
| **Category** | Template of fields a thing is filed under. | type, kind, template, group | categoría | catégorie | 类别 |
| **Field** | One named slot on a thing (`PropertyDefinition`). | property, attribute, spec | campo | champ | 字段 |
| **Value** | What is stored in a field. | entry, data | valor | valeur | 值 |
| **Event** | A dated non-monetary occurrence (service, inspection). | activity, log entry, incident | evento | événement | 事件 |
| **Transaction** | A dated monetary record. | payment, expense, purchase, cost | transacción | transaction | 交易 |
| **Expense** | A transaction where money leaves. | cost, outgoing, spend, bill | gasto | dépense | 支出 |
| **Income** | A transaction where money arrives. | revenue, earnings, payment in | ingreso | revenu | 收入 |
| **Amount** | The money figure on a transaction. | price, sum, total | importe | montant | 金额 |
| **Record** | Event or transaction, when speaking of both. | entry, item, log | registro | enregistrement | 记录 |
| **Series** | A recurring event/transaction and its occurrences. | repeat, recurrence, schedule | serie | série | 系列 |
| **Occurrence** | One dated instance of a series. | instance, repeat | repetición | occurrence | 发生 |
| **Due** | Scheduled for a date not yet reached. | upcoming, pending, expiring | pendiente | à échéance | 待办 |
| **Due soon** | Within the record's own notice window. | coming up, expiring soon, urgent | próximo a vencer | bientôt dû | 即将到期 |
| **Overdue** | Past its due date. | late, missed, expired | vencido | en retard | 已逾期 |
| **Warranty** | Manufacturer/seller coverage period. | guarantee, protection | garantía | garantie | 保修 |
| **Receipt** | Scanned proof of purchase. | bill, invoice, ticket | recibo | reçu | 收据 |
| **Photo** | Image attached to a thing. | picture, image, attachment | foto | photo | 照片 |
| **Pick list** | A named list of choosable options (`ComboListDefinition`). | combo list, dropdown, options list | lista de opciones | liste de choix | 选项列表 |
| **Option** | One entry in a pick list. | choice, value, item | opción | option | 选项 |
| **Contact** | A person linked from the address book. | person, party | contacto | contact | 联系人 |
| **Deleted items** | The restore bin for soft-deleted records. | trash, bin, archive, recycle bin | elementos eliminados | éléments supprimés | 已删除项目 |
| **Restore** | Bring a soft-deleted record back. | undelete, recover, undo | restaurar | restaurer | 恢复 |
| **Sync** | iCloud replication across devices. | backup, cloud, mirror | sincronización | synchronisation | 同步 |
| **Export / Import** | Write / read a backup file. | backup, save, upload | exportar / importar | exporter / importer | 导出 / 导入 |
| **Timeline** | The tab of upcoming + past records. | home, feed, activity, dashboard | Cronología | Chronologie | 时间线 |
| **Cashflow** | The money pill on Timeline. | balance, budget, spending | Flujo de caja | Trésorerie | 现金流 |
| **Setup** | The settings tab. | settings, preferences, tools | Configuración | Configuration | 设置 |

### Product-noun decisions (settled — apply, do not revisit)

- **"Thing" wins everywhere in copy.** The UI already says it; the mismatch is in
  `Intents/` and StoreKit. Rewrite `AddAssetIntent` / `AddNamedAssetIntent` /
  `OpenAssetIntent` titles, every parameter dialog, all 18 Siri phrases in
  `HandyAppShortcuts.swift`, `QuickActionDelegate.swift:13`, and the `Products.storekit`
  `displayName`/`description` (currently "Unlocks unlimited assets.") to use *thing*.
  Swift type names are untouched. Delete the apology comment at
  `Views/SetupToolScreens.swift:319` once the copy agrees.
- **Keep** these established product nouns as-is: **Timeline**, **Cashflow**, **Due Soon**,
  **Setup**, **Deleted items**, **Pick list**.
- **Retire** these, replacing every occurrence: *asset* → thing; *money record* /
  *money* (as a noun for a record) → transaction; *item* (when it means a thing) → thing.
- `Uncategorized` stays the fallback category name.

## Key-naming convention

- **Default: English source string as the key.** The catalog is 455/455 English-source
  today; keep it. Do not mass-convert to symbolic keys — that would discard the existing
  extraction wiring for no user benefit.
- **Use a symbolic key** (`ns.concept.detail`, e.g. `builtin.field.purchaseDate`) in
  exactly two cases:
  1. Built-in seeded labels (Phase 6) — they are looked up by key, not by literal.
  2. Any English string that must render differently in two places (homograph collision,
     e.g. `Type` the appliance field vs `Type` the field-kind picker). Give both a
     symbolic key rather than one shared entry.
- **Every key gets a `comment`.** Today only 52 of 455 do. The comment states where the
  string appears and what each argument is: `"Timeline empty state. %1$lld = things used,
  %2$lld = free-tier limit."` A translator must never have to guess.
- **All multi-argument formats must be positional** (`%1$@`, `%2$lld`). There are 13
  multi-argument keys and **zero** currently use positional syntax; Xcode has already
  auto-rewritten 7 into `en` values in state `new`. Rewrite the source keys themselves so
  `es`/`fr`/`zh-Hans` may reorder freely — this is required, not optional, because the
  four Timeline sentences (`%@: %@ paid out on %@. Next occurrence expected on %@.`)
  cannot be idiomatic in Chinese without reordering.
- **Never concatenate.** No `"Due " + date`, no `"\(count) things"` assembled from parts.
  Numbers, currency, and dates go through `formatted()` with the environment locale;
  counts go through `^[…](inflect: true)` or a `plural` variation.
- Delete accidental extractions: the empty-string key `""` and the standalone glyph keys
  `·`, `›`, `•••`, `+`, `−`, `◷`, `✓`, `$`, `%@`, `0.00`. Replace their call sites with
  non-localized `Text(verbatim:)`.
- Collapse the 24 near-duplicate groups (`Belongs to`/`Belongs To`, `Log now`/`Log Now`,
  `New category`/`New Category`, `Choose contact`/`Choose Contact`/`Choose a contact…`,
  `None · top level`/`None (top level)`, `(Late)`/`Late`, …) into one key each.

## Casing rule (settles the existing drift)

**Sentence case for everything except the app name and proper nouns.** Buttons, titles,
section headers, field labels, pick-list options: `Purchase date`, `License plate`,
`Power source`, `Year built`, `Home insurance`. This makes the current minority
(`Purchase date`, `Power source`) the rule and normalizes the 29 Title Case labels.
Navigation titles follow the same rule. Product nouns keep their capital when used as
names of app surfaces: *Timeline*, *Cashflow*, *Due Soon*, *Setup*.
`VIN`, `HOA`, `HVAC`, `2D`, `3D` stay uppercase. Fix `Dish washer` → `Dishwasher`.

## Voice

Audience: financially literate people who take deliberate care of what they own — they
keep a maintenance log, know their warranty expiry, think in total cost of ownership.

- **Precise over playful.** No exclamation points, no "Oops!", no "Let's get started!",
  no emoji in copy. A stated fact beats an encouragement.
  - Not `Nothing here yet!` → `No records logged on this thing.`
- **Stewardship, not consumption.** Prefer *record, log, ledger, statement, schedule,
  service, maintenance, warranty, coverage, valuation, acquired, disposed, retained*.
  Avoid *stuff*, loose *your things*, *fun*, *awesome*, *magic*.
- **Financial terms used correctly.** *Expense*, *payment*, *transaction*, and *amount*
  are not interchangeable; use the glossary term for the concept actually meant.
- **Calm, not urgent.** `Due soon`, never `Don't miss it!`. Reminders inform; they do not
  nag or manufacture pressure. Notification bodies state the fact and the date.
- **Short and concrete.** Buttons are verbs: *Log*, *Record*, *Schedule*, *Restore*,
  *Export*. Empty states say what belongs there and the one action that fills it:
  `Events and transactions you log on this thing appear here. Tap + Log to add one.`
- **Errors say what happened and what to do; never blame the user.** Rewrite
  `AssetStore+Persistence.swift:44-49` — it currently points at "Tools > Export Data", a
  menu path that no longer exists.
- Second person, present tense, active voice. Address the user as *you*.

## Per-language guidance

Register, locked app-wide — the current translations are inconsistent (fr `Appuyez`
vouvoiement next to es `Toca` tuteo):
- **es** — *tú*, informal, consistently. `Toca`, `tu`, `tus`.
- **fr** — *vous*, formal, consistently. `Appuyez`, `votre`.
- **zh-Hans** — 您 (formal), consistently.

**es / fr — string growth.** Expect +15–30% over English on a screen designed for tight
iOS controls. Where a translation would exceed the English by more than ~30% in a button,
tab label, segmented control, or list-row trailing label, shorten the *translation*
(`Tout supprimer` rather than a literal rendering of `Delete everything inside`) rather
than requesting a layout change. Never abbreviate with a period-truncation (`Transact.`).
- fr punctuation: narrow no-break space before `: ; ! ?` — the existing `%@ : %@ payé le
  %@.` is correct, preserve it. Use `«  »` for quotes, not `"`.
- es: `«»` or `“”`, not ASCII `"` — the current
  `Ya existe una categoría llamada "%@".` uses ASCII and must be fixed.
- Both: keep sentence case in headers; do not import English Title Case.

**zh-Hans — terser, term-of-art, not transliteration.**
- Use financial/household terms of art: 支出 not 花钱, 收入 not 进钱, 保修 not 担保,
  折旧 for depreciation, 到期 for due, 逾期 for overdue.
- Full-width punctuation throughout: `，。：、；（）` and `「」` or `“”` — the current
  `已存在名为"%@"的类别。` uses ASCII quotes and must be fixed.
- One space between a Latin/numeric run and adjacent Han characters (`%lld 个物品`), no
  space around full-width punctuation.
- No measure-word guessing from English: 个 for generic things, 项 for records/items,
  条 for entries in a list, 张 for photos/receipts.
- Chinese has no plural inflection: a `^[…](inflect: true)` key needs a single flat
  zh-Hans value, and a `plural` variation needs only `other`.
- Aim shorter than English, not longer; Chinese UI strings that match English character
  count are usually padded.

**Numbers, dates, currency, plurals — all four languages.**
- Currency: `Decimal.formatted(.currency(code:))`, never a hardcoded `$`. Delete the
  standalone `$` and `0.00` keys.
- Dates: `Date.formatted(date:time:)` with the environment locale. Never build a date
  string from components.
- Counts: keep the 26 `^[…](inflect: true)` keys and the 2 `plural` variation keys, and
  supply every CLDR category each language requires — `es`/`fr`: `one`/`other` (note fr
  treats 0 and 1 as `one`); `zh-Hans`: `other` only. One existing key is missing its
  zh-Hans plural variation; fix it.
- Units (`Lot Size`, `2D Size`) are user-entered with an explicit `Unit` field — do not
  auto-convert, only localize the label.

## Phased plan

Each phase ends with a commit and states its own done-condition. The work survives
interruption: if you resume mid-rebuild, re-read this prompt and continue at the first
phase whose done-condition is unmet.

### Phase 0 — Unblock shipping
1. In `HandyApp3.xcodeproj/project.pbxproj`, set
   `knownRegions = (en, Base, es, fr, "zh-Hans")`. This is the sanctioned exception to the
   no-`.pbxproj` rule — change nothing else in that file except the two usage
   descriptions in step 2.
2. Create `HandyApp3/InfoPlist.xcstrings` with `NSCameraUsageDescription` and
   `NSContactsUsageDescription`, and remove the hardcoded
   `INFOPLIST_KEY_NSCameraUsageDescription` / `INFOPLIST_KEY_NSContactsUsageDescription`
   build settings so the catalog wins. Leave `INFOPLIST_KEY_CFBundleDisplayName` alone —
   "Baron Book" is not translated.
3. Fix the language-override bug. `.environment(\.locale, …)` at
   `HandyApp3App.swift:19` does not redirect `Bundle.main`, so the ~54
   `String(localized:)` sites ignore the in-app picker. Resolve them against the chosen
   locale explicitly — thread the selected `Locale` (and its matching `Bundle`) to those
   call sites, or pass `String(localized:locale:)` / `bundle:` where the value is built.
   Prefer a small Foundation-only helper in `Models/` over touching every call site by
   hand; it must compile in the `swift test` target.

**Done when:** a build in Spanish shows Spanish for a screen that uses
`String(localized:)` (e.g. Setup's sync status rows), and the user confirms in Xcode.

### Phase 1 — Audit & inventory
Produce `HandyApp3/docs/localization-inventory.md`: every catalog key with its call
site(s), its glossary concept, and a disposition — *keep / rewrite / merge into <key> /
delete*. Flag the 24 near-duplicate groups, the 11 glyph keys, and the 7 strings found in
source but missing from the catalog (`QuickLogSheet.swift:88`,
`TimelineTab.swift:308`, `ThingSpecRows.swift:490`, `SetupTab.swift:73`,
`SetupTab.swift:247`, and two `#if DEBUG` strings that may stay English).

**Done when:** every one of the 455 keys has a disposition and every disposition names a
file:line call site or is marked orphaned.

### Phase 2 — Glossary lock
Write the glossary table above into `HandyApp3/docs/localization-glossary.md` verbatim,
extended with any concept the Phase 1 inventory surfaced that it does not cover. This
file is the authority for the rest of the work.

**Done when:** no inventory row maps to a concept absent from the glossary.

### Phase 3 — Extract remaining literals
- Add the missing keys from Phase 1.
- Route `Controllers/NotificationScheduler.swift:71,79` through `String(localized:)` with
  positional arguments. `:79` currently interpolates `kind.rawValue` — an unlocalized
  enum raw value ("expense"/"income") — straight into user-visible text; replace it with
  two distinct keys, one per kind.
- Route `AssetStore+Persistence.swift:44-49`'s `errorDescription`.
- Replace glyph/verbatim call sites with `Text(verbatim:)`.

**Done when:** `swift test` passes and a grep for user-facing literals outside the
catalog returns only `Text(verbatim:)`, `#if DEBUG` strings, and language endonyms.

### Phase 4 — Rewrite `en`
Rewrite all English values against the voice, glossary, and casing rule. Apply the
thing/asset decision across Views, `Intents/`, `PaywallView`, and `Products.storekit`.
Merge duplicates; delete orphans; add a `comment` to every key; convert all 13
multi-argument keys to positional form.

**Done when:** zero glossary violations, zero Title Case outside the allowed list, every
key has a comment, and `swift test` passes.

### Phase 5 — Translate es / fr / zh-Hans
Retranslate **all** keys, including the 167 that already have values — those translate
retired copy (*activos* / *biens* / *资产*, a "Categories tab", an
"Events & Transactions" tab) and must not be trusted. Apply the per-language guidance;
set every unit's `state` to `translated` and `extractionState` consistently.

**Done when:** all three languages have a value for every non-`verbatim` key, no ASCII
quotes remain in `es`/`fr`/`zh-Hans` values, register is uniform per language, and every
plural/inflect key has the categories its language requires.

### Phase 6 — Built-in type labels (display-only)
The ~60 seeded labels in `SystemTypes/` and `Models/BuiltInTypes.swift` are persisted,
synced `String`s. Localize them **for display only**:
1. Add a Foundation-only lookup in `Models/` (e.g.
   `BuiltInTypes.localizedName(forID:) -> String?`) built from the *existing*
   `deterministicID` key literals — the seeder already knows the key that produced each
   UUID, so a `[UUID: String]` reverse map needs no schema change. It must use
   `String(localized:)`, not `LocalizedStringKey`, to stay compilable in the package target.
2. Show the localized label **only when the stored `name` still equals the shipped English
   literal**; a user rename wins and renders verbatim. This mirrors the shape
   `upgradeBuiltInCategories` already uses (`BuiltInTypes.swift:235`).
3. Views call the lookup at render time — `Text(category.name)` sites at
   `AssetCreateView.swift:300`, `ThingDetailView.swift:285`, `CategoryNewView.swift:143`,
   `CompositeEditView.swift:89`, `ThingSpecRows.swift:475` and their siblings.
4. Add the ~60 catalog entries under symbolic keys with disambiguating comments —
   `Retailer`, `Type`, `Size`, `Make`, `Year`, `Notes` are short and ambiguous, and
   `Appliance` is both a category and part of the pick-list name `Appliance type`.
5. Fix the English casing drift *in the seed literals* (`Power Source` field/list
   agreement, `Dish washer` → `Dishwasher`, and the 29 Title Case labels → sentence case)
   **without changing any `deterministicID` key string** — the key
   `"field.appliance.Purchase date"` must stay byte-identical.
6. Three seeders still match by **name**, not id, and will break once labels drift:
   `BuiltInTypes.swift:183` (categories), `:264` (composite types), `:143`
   (`resolveBuiltInAsset`), plus `seedSampleAutomobile`'s literal field lookups at
   `:159-161`. Convert them to id-keyed matching before changing any seed literal.

**Done when:** `swift test` passes with the built-in label tests updated
(`BuiltInCategoryUpgradeTests`, `MigrationV5Tests`, `ImportMergeTests`,
`TemplatePropagationTests`, `AssetTests`, `MaxLengthTests`, `HandyApp3Tests` all assert
these literals), a French build shows French built-in labels, and a renamed definition
still shows the user's own name.

### Phase 7 — Verification
See below. Ends with a summary of what changed and what the user must check in Xcode.

## Verification

1. `swift test` — the full ~485-test suite, headless, ~11s. Must pass at the end of every
   phase, not just at the end.
2. **Catalog integrity** — script it and report numbers:
   - key count before/after, and the delete/merge/add ledger;
   - zero keys missing `es`/`fr`/`zh-Hans`;
   - zero `state: new`, `needs_review`, or `stale`;
   - zero duplicate keys after case/punctuation normalization;
   - every key has a `comment`;
   - every multi-argument key is positional, and the argument *set* matches across all
     four languages (same specifiers, any order);
   - zero orphans: every key resolves to a source call site.
3. **No stray literals** — grep `Views/`, `Intents/`, `Controllers/` for user-facing
   string literals not routed through the catalog; the only permitted survivors are
   `Text(verbatim:)`, `#if DEBUG` blocks, and the language endonyms.
4. **Glossary conformance** — grep every forbidden synonym across all four languages'
   values; expect zero hits.
5. **Layout risk report** — list every `es`/`fr` value exceeding its English by >30% that
   lands in a button, tab, segmented control, or trailing list label, and every zh-Hans
   value longer than its English. These are the strings to check at the largest Dynamic
   Type setting. Report them; do not change layout code.
6. **Visual confirmation is the user's, in Xcode.** Do not launch a simulator. Hand back
   a short checklist naming the screens to look at per language — Timeline (Coming up /
   History / Cashflow), Thing detail's four sub-tabs, Category editor, Paywall, Setup →
   Deleted items, and one Siri phrase per shortcut — plus the largest Dynamic Type size.

## Do not

- Do not renumber, churn, or symbolically rename keys beyond the merges and deletes the
  Phase 1 inventory justifies.
- Do not write a localized string into any persisted `name`, or into
  `StoredValue.composite`'s field keys. Display-layer only.
- Do not change any `BuiltInTypes.deterministicID` key literal.
- Do not break a user-renamed category, field, pick list, or option — the rename always
  wins over the localized label.
- Do not touch `.pbxproj` beyond `knownRegions` and the two usage-description settings.
- Do not add a fifth language, and do not translate "Baron Book" or the language endonyms.
- Do not import `SwiftUI` or `UIKit` into `Models/`, `Controllers/`, or `SystemTypes/`.
- Do not run a simulator or claim visual verification you did not perform.
- Do not trust the 167 existing translations as a starting point.
