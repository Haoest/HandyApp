# Meta-prompt: generate the localization-rebuild prompt

Paste the block below into a fresh Claude Code session in this repo. Its output is
*not* the localization work — it is the detailed implementation prompt that will be
used to do the work in a later session.

---

You are writing a prompt, not doing the work. Your only deliverable is a single
self-contained implementation prompt (Markdown, ~600–1000 words plus any inline
tables) that a later Claude Code session will follow to rebuild every user-facing
string in this app: all screen copy and all property/field labels, across the four
shipped languages.

## Before you write, investigate the repo and ground the prompt in what you find

Do not guess at the codebase. Read enough to write a prompt that names real files,
real symbols, and real problems. At minimum:

1. `HandyApp3/Localizable.xcstrings` — the catalog. Report its actual key count,
   its `sourceLanguage`, which of `en` / `es` / `fr` / `zh-Hans` are complete vs
   stale/missing, how many entries are `needs_review`, `new`, or untranslated, and
   whether keys are English source strings or symbolic identifiers.
2. `HandyApp3/Views/*.swift` — find where user-facing text is still a bare Swift
   literal (`Text("…")`, `.navigationTitle("…")`, alert/button titles, section
   headers, placeholder text, accessibility labels) versus properly routed through
   `String(localized:)` / `LocalizedStringKey`. Name the worst offenders by file.
3. `HandyApp3/SystemTypes/` and `HandyApp3/Models/BuiltInTypes.swift` — the
   built-in category, property, and combo-list labels ("VIN", "Purchase date",
   "Power source", "Retailer", "Warranty", …). Determine whether these seeded
   strings are localized at all, and how the app would keep a *user-renamed*
   definition intact while still localizing the built-in ones. Flag the existing
   casing drift ("Purchase date" / "Power source" vs "Appliance Type" /
   "License Plate") as something the rebuild must settle with one rule.
4. Sample the current `es` / `fr` / `zh-Hans` values for tone. Note where they read
   as machine translation, and where a term of art was translated literally
   instead of using the local financial/household equivalent.
5. Check what is *not* covered: `Intents/`, notification and widget copy,
   `PaywallView`, `Info.plist` usage descriptions, the App Store-facing strings.

Also note the constraints the prompt must respect: Xcode 16 file-system-synchronized
groups (no `.pbxproj` edits), `swift test` as the headless test path, and the rule
that pure logic must stay free of SwiftUI/UIKit so the package target still compiles.

## The voice the generated prompt must specify

The audience is financially literate people who take deliberate care of what they
own — they maintain a maintenance log, they know their warranty expiry, they think
in total cost of ownership. Write the copy standard into the prompt explicitly, with
examples, so the implementing session is not left to improvise:

- **Precise over playful.** No exclamation points, no "Oops!", no "Let's get
  started!", no emoji in copy. A stated fact beats an encouragement.
- **Stewardship, not consumption.** Prefer the vocabulary of records, upkeep, and
  ownership: *record*, *log*, *ledger*, *statement*, *schedule*, *service*,
  *maintenance*, *warranty*, *coverage*, *valuation*, *acquired*, *disposed*,
  *retained*. Avoid *stuff*, *your things* used loosely, *fun*, *awesome*, *magic*.
- **Financial terms used correctly.** *Expense* vs *payment* vs *transaction* vs
  *cost basis* are not interchangeable; the prompt must require a fixed glossary and
  one term per concept, app-wide, in every language.
- **Calm, not urgent.** "Due soon" not "Don't miss it!". Reminders inform; they do
  not nag or manufacture pressure.
- **Short and concrete.** Buttons are verbs (*Log*, *Record*, *Schedule*,
  *Restore*). Empty states say what belongs there and what one action fills it.
  Errors say what happened and what to do, never blame the user.
- **Respect existing product nouns** already established in the UI (the Timeline
  tab, the Cashflow pill, Due Soon, Things vs Assets) — the prompt should require an
  explicit decision to keep or rename each, once, rather than letting each screen
  drift.

## Required shape of the prompt you produce

Structure it so a later session can execute it without asking questions:

- **Goal + scope**, with an explicit out-of-scope list.
- **A terminology glossary** — a table of canonical EN term → definition → forbidden
  synonyms → `es` / `fr` / `zh-Hans` equivalents, seeded with the app's real
  concepts (asset/thing, category, property, event, transaction, series/recurrence,
  due, warranty, receipt, attachment, soft delete/restore, sync).
- **A key-naming convention** for the catalog and a rule for when to use a symbolic
  key vs an English source key, plus comment/`%@`-argument-ordering requirements for
  translators.
- **A phased plan** that survives interruption: audit & inventory → glossary lock →
  extract remaining literals → rewrite `en` → translate the three locales →
  built-in type labels → verification. Each phase must state its own done-condition.
- **Per-language guidance**, including at least: `fr`/`es` string growth vs. tight
  iOS layouts; `zh-Hans` needing terser, term-of-art financial vocabulary rather
  than transliteration; correct handling of plurals, currency, dates, and units via
  the format catalog rather than string concatenation.
- **Verification steps**: `swift test`, a check that no user-facing literal remains
  outside the catalog, no orphaned or duplicate keys, and a pass at the largest
  Dynamic Type size and in RTL-agnostic layout terms — while stating plainly that
  visual confirmation happens in Xcode by the user, not in a simulator here.
- **A "do not" list**: don't renumber or churn keys unnecessarily, don't break
  existing user data or renamed definitions, don't touch the `.pbxproj`, don't
  invent a fifth language.

Output the prompt as one fenced Markdown block with no commentary before or after
it, and no summary of what you did.
