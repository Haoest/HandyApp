- improve localization with domain vocabulary
-quick reporting
-export data to excel by email
-swiping to delete transaction/event carries the asset sheet under
- change event/transaction "duplicate" label

need to refine how notification works. have it open the transaction / event screen with information filled? post event or transaction to home for quick action?


revisit paywall ensure transaction and event has a limited free count

-improve asset navigation, especially in tree mode, when going into details view. 

- reorganize categories, remove specific appliances
- rework combo list, allow custom text values to be entered, and the new values becomes pre-selectable for the next 
combo list field


- definition deletes (composite types, combo lists, combo list option removal) don't propagate over sync — a
peer's still-live copy resurrects them on the next merge, since there's no tombstone on those two DTOs. Needs the
same isDeleted/deletedAt treatment assets/categories already have, plus join/reap support.
- purge deletes a photo's JPEG files immediately, even when the owning asset's strip gets refused by the new
auto-purge protection (see below) — the record survives but the images may already be gone. Possible fix: stage
purged photos in a local non-synced holding dir for a grace period instead of deleting outright.

== completed ==

improve localization to read more like asset management app
improve combo list feature
siri intergration
    - add asset
    - open asset
    - add event to asset
    - add transaction to asset
    
-- when a field is editted and user hit back to navigate away, value is lost
~homepage provide "more" to show more log entries~
~rework purging, need to count days-to-retain-deleted items, in addition, icloud sync must be live at the time~
~handle offline edit of an asset deleted on the cloud — purge (local retention sweep and sync merge alike) now
refuses to strip a record whose own content is newer than the delete/purge decision; it just stays a live
tombstone in Trash, restorable, instead of a prompt~
--category, asset, properties, transaction, event, photos, all need to have a modifiedDate field
-break up store.json
-rework category purge
- add + buttons to event/transaction/photo fields
- build on recurring event/transaction notification

- data import should merge with live data instead of replace
