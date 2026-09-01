import Foundation

extension BuiltInTypes {
    /// Every built-in category / field / pick-list / composite-type label that gets a
    /// display-only localized name, keyed by the construct's `deterministicID`. Each entry
    /// pairs the catalog's symbolic key with the exact English literal the seeder currently
    /// stores in `name` (or `SystemCategory.rawValue`) — the comparison string that decides
    /// whether a rename has happened. Reuses the very same key string already passed to
    /// `deterministicID(_:)` at each seed site (prefixed `builtin.`), so there is one source of
    /// truth for "this id, this key" instead of a second hand-kept table that could drift.
    ///
    /// This never feeds back into stored data: `name`/`rawValue` are never rewritten from a
    /// translation. See `localizedSeedName(id:currentName:)`.
    static let seedLabelKeys: [UUID: (catalogKey: String, english: String)] = {
        var map: [UUID: (catalogKey: String, english: String)] = [:]
        func add(_ key: String, _ english: String) {
            map[deterministicID(key)] = ("builtin.\(key)", english)
        }

        add("category.Primary Home", "Primary Home")
        add("category.Rental Home", "Rental Home")
        add("category.Automobile", "Automobile")
        add("category.Appliance", "Appliance")
        add("category.Uncategorized", "Uncategorized")
        add("field.appliance.Type", "Type")
        add("field.appliance.Make", "Make")
        add("field.appliance.Purchase date", "Purchase date")
        add("field.appliance.Price", "Price")
        add("field.appliance.Power source", "Power source")
        add("field.appliance.Size", "Size")
        add("field.appliance.Warranty", "Warranty")
        add("field.appliance.Retailer.comboList", "Retailer")
        add("field.appliance.Notes", "Notes")
        add("field.residentialHousing.Address", "Address")
        add("field.residentialHousing.Purchase date", "Purchase date")
        add("field.residentialHousing.HOA Contact", "HOA Contact")
        add("field.residentialHousing.Lot Size", "Lot Size")
        add("field.residentialHousing.Year Built", "Year Built")
        add("field.residentialHousing.Gas Provider", "Gas Provider")
        add("field.residentialHousing.Water Provider", "Water Provider")
        add("field.residentialHousing.Electricity Provider", "Electricity Provider")
        add("field.residentialHousing.Roof", "Roof (material, year, expected lifespan)")
        add("field.residentialHousing.Home Insurance", "Home Insurance")
        add("field.residentialHousing.Mortgage Lender", "Mortgage Lender")
        add("field.residentialHousing.Tax ID", "Tax ID")
        add("field.rentalHome.Address", "Address")
        add("field.rentalHome.Tenant", "Tenant")
        add("field.rentalHome.Gas Provider", "Gas Provider")
        add("field.rentalHome.Water Provider", "Water Provider")
        add("field.rentalHome.Electricity Provider", "Electricity Provider")
        add("field.rentalHome.Rental License", "Rental License")
        add("field.rentalHome.Purchase date", "Purchase date")
        add("field.rentalHome.Roof", "Roof (material, year, expected lifespan)")
        add("field.rentalHome.Landlord Insurance", "Landlord Insurance")
        add("field.rentalHome.Mortgage Lender", "Mortgage Lender")
        add("field.rentalHome.Smoke Detector", "Smoke Detector")
        add("field.rentalHome.Property Manager", "Property Manager")
        add("field.rentalHome.Lot Size", "Lot Size")
        add("field.rentalHome.Year Built", "Year Built")
        add("field.rentalHome.Tax ID", "Tax ID")
        add("field.automobile.Make", "Make")
        add("field.automobile.Model", "Model")
        add("field.automobile.Trim", "Trim")
        add("field.automobile.Year", "Year")
        add("field.automobile.License Plate", "License Plate")
        add("field.automobile.Registration Number", "Registration Number")
        add("field.automobile.VIN", "VIN")
        add("field.automobile.Engine Oil", "Engine Oil")
        add("field.automobile.Oil Filter", "Oil Filter")
        add("field.noCategory.Notes", "Notes")
        add("comboList.powerSource", "Power Source")
        add("comboList.applianceType", "Appliance Type")
        add("comboList.retailer", "Retailer")
        add("compositeType.2DSize", "2D Size")
        add("compositeType.2DSize.Width", "Width")
        add("compositeType.2DSize.Length", "Length")
        add("compositeType.2DSize.Unit", "Unit")
        add("compositeType.3DSize", "3D Size")
        add("compositeType.3DSize.Width", "Width")
        add("compositeType.3DSize.Length", "Length")
        add("compositeType.3DSize.Height", "Height")
        add("compositeType.3DSize.Unit", "Unit")

        return map
    }()

    /// The display name for a built-in category/field/pick-list/composite-type: the current
    /// display-language translation of its shipped English label, or `currentName` verbatim if
    /// the record's id isn't a recognized built-in, or if `currentName` no longer matches what
    /// was shipped — a user rename always wins over the localized label.
    static func localizedSeedName(id: UUID, currentName: String) -> String {
        guard let entry = seedLabelKeys[id], entry.english == currentName else { return currentName }
        return String(localized: String.LocalizationValue(entry.catalogKey), locale: .appPreferred)
    }
}
