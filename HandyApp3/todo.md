~homepage provide "more" to show more log entries~
siri intergration
    - add asset
    - open asset
    - add event to asset
    - add transaction to asset
    
quick reporting
export data to excel by email

swiping to delete transaction/event carries the asset sheet under

icloud backup not working, can't find on device under account/icloud backup
data import needs refining, maybe do a merge instead of complete replacement
need to refine how notification works. have it open the transaction / event screen with information filled? post event or transaction to home for quick action?

when a field is editted and user hit back to navigate away, value is lost

the lost-edit bug isn't limited to text fields. Seven fields share the same commit-on-blur shape and all have it — asset name, and Text/Number/Currency on both the asset detail and category-defaults screens. The persistence layer is clean; commit() simply never runs on pop.


when a field type is text, it needs to support multi line. When user hits enter, the field needs to increase height visually for the new line. Also when text overflows, the field also needs to increase height for the new line. whenever new line is needed, the space needs to increase height, to a maximum of 5 lines. More than 5 lines  the text field will become scrollable. After a multiline text field is saved, and user navigates away or app closes, reloading the field should show the correct height for the number of lines saved.

data import should merge with live data instead of replace

category, asset, properties, transaction, event, photos, all need to have a modifiedDate field

revisit paywall ensure transaction and event has a limited free count

== completed ==
add quick guide to tools tab, include some sample siri commands
group tools tab
support multiline text 
put field abel and value on different lines

improve localization to read more like asset management app

