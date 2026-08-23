- improve localization with domain vocabulary
-quick reporting
-export data to excel by email

revisit paywall ensure transaction and event has a limited free count

-improve asset navigation, especially in tree mode, when going into details view. 


- revisit siri command

- create transaction / event tab

-facelift


== completed ==
- set a hard length on each text form field
-importing data inserts duplicate assets

- enhance device notification, create notification to create new event/transaction entry, and maybe set up another notification by due date, to keep the loop alive
- revisit factory reset, leave asset husk after reset
improve localization to read more like asset management app
improve combo list feature
rework combo list: dedicated ComboListField (textbox + tap-to-fill suggestions, typed values
auto-add to the list), full CRUD + soft delete in a new Categories tab section, single
"Combo list" entry in the property Type picker (replacing one flattened entry per list)
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
- change event/transaction "duplicate" label
- need to refine how notification works. have it open the transaction / event screen with information filled? post event or transaction to home for quick action?
-swiping to delete transaction/event carries the asset sheet under
- reorganize categories, remove specific appliances
-provide option to propagate category properties to assets retroactively
- asset detail form sluggish

- property sort order
