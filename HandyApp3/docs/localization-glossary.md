# Localization glossary — Phase 2

Locked terminology for the rebuild. One term per concept, app-wide, in every language.
Forbidden synonyms are banned in copy even when they read better in one sentence — if a
sentence only works with a forbidden synonym, rewrite the sentence, not the glossary.

Carried over verbatim from `HandyApp3/docs/localization-rebuild-prompt.md`, plus three
rows (**Notification**, **Icon**, **Structured field**) added below the line — concepts
the Phase 1 inventory surfaced repeatedly (`Device Notification`, `Notify before due
date`, `Change Icon`, the composite-value copy in `PropertyViews.swift`) that weren't in
the original table.

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
| **Notification** | A local device alert for a due record (see `NotificationScheduler`). Distinct from the notification's *message*, which is the record's own body text — "message" stays the right word for that specific field, it just isn't a synonym for the notification concept itself. | alert, reminder (as the concept, not the text) | notificación | notification | 通知 |
| **Icon** | The SF Symbol representing a category. | image, picture, symbol | icono | icône | 图标 |
| **Structured field** | A field whose value has multiple named parts, entered one part at a time (`CompositeTypeDefinition` — e.g. Width × Length). | composite field, compound field | campo estructurado | champ structuré | 结构化字段 |

## Product-noun decisions (settled — apply, do not revisit)

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

## Coverage check against the Phase 1 inventory

No inventory row maps to a concept absent from this table. The recurring English nouns in
the 332-key rewrite list — *field*, *value*, *event*, *transaction*, *category*, *due*,
*photo*, *contact*, *icon*, *notification*, *structured field* (composite editing copy),
and the *thing/asset* nouns the merge and orphan lists surface — all resolve to a row
above. `Series`/`Occurrence`/`Recurrence`/`Recurring` (the orphaned `Recurrence` and
`Recurring` keys, plus the live `RecurrenceInterval` labels in the "missing from the
catalog" list) all fall under the existing **Series** / **Occurrence** rows — `Recurrence`
and `Recurring` are exactly the kind of synonym drift the glossary exists to collapse, not
new concepts.
