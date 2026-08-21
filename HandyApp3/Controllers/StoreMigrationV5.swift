import Foundation

/// v4 → v5: re-keys built-in categories, template fields, composite types, and combo lists to
/// their canonical `BuiltInTypes.deterministicID` ids on installs that seeded before commit
/// 49c6600 (2026-08-13), when those ids were still random `UUID()`s. Without this, both
/// `seedBuiltInCategories` (name-guarded — sees the old category and skips) and
/// `upgradeBuiltInCategories` (id-keyed lookup — never finds it) silently leave such an install
/// stuck on whatever shape it first seeded, forever.
///
/// Pure DTO-level rewrite: only ids change. Names, types, `isRequired`, values, `sortOrder`,
/// `modifyDate`, and tombstones are all preserved untouched — the launch-time
/// `upgradeBuiltInCategories` pass, which can finally find these records once their ids are
/// canonical, is what refreshes *shape* afterward (e.g. a legacy free-text "Retailer" field
/// name-matches the current canonical combo-list field here, keeping its value, and gets its
/// type refreshed to the combo list on the next launch by `updateTemplateProperty`).
///
/// Idempotent: every candidate lookup below first checks whether the canonical id is already
/// occupied and skips if so, so re-running this against an already-migrated (or partially
/// migrated) snapshot changes nothing.
///
/// Documented limitation: a hypothetical un-migrated v4 peer would still reintroduce old-id
/// records via `SnapshotReconciler`'s union-by-id until it runs a build carrying this migration
/// — mitigated in-session by the `handleCloudMonitorNotification` call site (an incoming
/// snapshot is migrated before the merge sees it), but a peer's own on-disk store stays legacy
/// until that peer's build does. Acceptable for a single-device install.
extension StoreMigrator {

    static func migrateV5RekeyBuiltInIdentity(_ s: inout StoreSnapshotDTO) {
        var typeIDRewrites: [UUID: UUID] = [:]
        rekeyCompositeTypes(&s, typeIDRewrites: &typeIDRewrites)
        rekeyComboLists(&s, typeIDRewrites: &typeIDRewrites)
        applyTypeIDRewrites(&s, typeIDRewrites)
        rekeyCategories(&s)
    }

    // MARK: - Phase 1: composite types

    private static func rekeyCompositeTypes(_ s: inout StoreSnapshotDTO, typeIDRewrites: inout [UUID: UUID]) {
        for template in [BuiltInTypes.size2D(), BuiltInTypes.size3D()] {
            rekeyCompositeType(template, in: &s, typeIDRewrites: &typeIDRewrites)
        }
    }

    /// Canonical id present → skip (already migrated). Else exactly one live record sharing the
    /// template's exact name → re-key it and record the id translation; ambiguous (≥2) or none
    /// → skip, a safe no-op. `CompositeTypeDTO` carries no tombstone, so unlike combo lists
    /// there's no stray-folding pass here — two same-named live composites is an ambiguity this
    /// migration doesn't try to resolve.
    private static func rekeyCompositeType(
        _ template: CompositeTypeDefinition,
        in s: inout StoreSnapshotDTO,
        typeIDRewrites: inout [UUID: UUID]
    ) {
        guard !s.compositeTypes.contains(where: { $0.id == template.id }) else { return }
        let candidates = s.compositeTypes.indices.filter { s.compositeTypes[$0].name == template.name }
        guard candidates.count == 1 else { return }
        let idx = candidates[0]
        let oldID = s.compositeTypes[idx].id
        s.compositeTypes[idx].id = template.id
        typeIDRewrites[oldID] = template.id
        // Re-key fields by exact name match against the canonical field list. Composite
        // *values* are keyed by field name (StoredValueDTO.composite([String: ...])), not id,
        // so this never touches any stored value.
        for fieldIdx in s.compositeTypes[idx].fields.indices {
            let fieldName = s.compositeTypes[idx].fields[fieldIdx].name
            guard let canonicalField = template.fields.first(where: { $0.name == fieldName }) else { continue }
            s.compositeTypes[idx].fields[fieldIdx].id = canonicalField.id
        }
    }

    // MARK: - Phase 2: combo lists

    private static func rekeyComboLists(_ s: inout StoreSnapshotDTO, typeIDRewrites: inout [UUID: UUID]) {
        for template in [
            BuiltInTypes.powerSourceComboList(),
            BuiltInTypes.retailerComboList(),
            BuiltInTypes.applianceTypeComboList(),
        ] {
            rekeyComboList(template, in: &s, typeIDRewrites: &typeIDRewrites)
        }
    }

    /// Same shape as `rekeyCompositeType`, but combo lists get a second pass: once the
    /// canonical id is confirmed present (pre-existing, or just claimed below), every *other*
    /// soft-deleted list sharing the template's name — the strays `resolveBuiltInComboList`
    /// (BuiltInTypes.swift) already folds and tombstones on a legacy install — has its id
    /// mapped to the canonical one too, so a `PropertyTypeDTO.typeID` still pointing at a
    /// stray's old id resolves correctly instead of silently dropping the property. The stray
    /// record itself is left alone (absence-never-deletes); only references to it are repointed.
    private static func rekeyComboList(
        _ template: ComboListDefinition,
        in s: inout StoreSnapshotDTO,
        typeIDRewrites: inout [UUID: UUID]
    ) {
        if !s.comboLists.contains(where: { $0.id == template.id }) {
            let candidates = s.comboLists.indices.filter {
                s.comboLists[$0].name.caseInsensitiveCompare(template.name) == .orderedSame
            }
            let liveCandidates = candidates.filter { !(s.comboLists[$0].isDeleted ?? false) }
            let chosen: Int?
            if liveCandidates.count == 1 {
                chosen = liveCandidates[0]
            } else if candidates.count == 1 {
                chosen = candidates[0]
            } else {
                chosen = nil
            }
            // Ambiguous or no candidate at all: bail before the stray-repoint pass below, which
            // requires the canonical id to actually exist in s.comboLists — repointing onto a
            // template.id that isn't present would leave a dangling reference that silently
            // drops the property the next time applySnapshot resolves it.
            guard let idx = chosen else { return }
            let oldID = s.comboLists[idx].id
            s.comboLists[idx].id = template.id
            typeIDRewrites[oldID] = template.id
        }
        for idx in s.comboLists.indices
        where s.comboLists[idx].id != template.id
            && s.comboLists[idx].name.caseInsensitiveCompare(template.name) == .orderedSame
            && (s.comboLists[idx].isDeleted ?? false)
        {
            typeIDRewrites[s.comboLists[idx].id] = template.id
        }
    }

    // MARK: - Phase 3: reference rewrite

    /// Walks every `PropertyTypeDTO` in the snapshot and maps `.typeID` through `rewrites`.
    /// Basic-typed fields have `typeID == nil` and pass through untouched; a `.composite`/
    /// `.comboList` field whose `typeID` isn't in `rewrites` (i.e. wasn't re-keyed above) also
    /// passes through untouched.
    private static func applyTypeIDRewrites(_ s: inout StoreSnapshotDTO, _ rewrites: [UUID: UUID]) {
        guard !rewrites.isEmpty else { return }
        func rewrite(_ type: inout PropertyTypeDTO) {
            guard let typeID = type.typeID, let newID = rewrites[typeID] else { return }
            type.typeID = newID
        }
        for i in s.compositeTypes.indices {
            for j in s.compositeTypes[i].fields.indices {
                rewrite(&s.compositeTypes[i].fields[j].type)
            }
        }
        for i in s.categories.indices {
            for j in s.categories[i].propertyTemplates.indices {
                rewrite(&s.categories[i].propertyTemplates[j].definition.type)
            }
        }
        for i in s.assets.indices {
            for j in s.assets[i].baseProperties.indices {
                rewrite(&s.assets[i].baseProperties[j].definition.type)
            }
            for j in s.assets[i].customProperties.indices {
                rewrite(&s.assets[i].customProperties[j].definition.type)
            }
        }
    }

    // MARK: - Phase 4 + 5: categories and their fields

    private static func rekeyCategories(_ s: inout StoreSnapshotDTO) {
        for (key, defs) in BuiltInTypes.categoryTemplates {
            let canonicalCatID = BuiltInTypes.deterministicID("category.\(key.rawValue)")
            if !s.categories.contains(where: { $0.id == canonicalCatID }) {
                // Purged categories are excluded: a purge blanks name/iconName, so it can never
                // be a meaningful name match, and a hypothetical purged same-named record isn't
                // something we want to resurrect an identity onto.
                let candidates = s.categories.indices.filter {
                    s.categories[$0].name == key.rawValue && !(s.categories[$0].isPurged ?? false)
                }
                guard candidates.count == 1 else { continue }
                let idx = candidates[0]
                let oldID = s.categories[idx].id
                s.categories[idx].id = canonicalCatID
                for i in s.assets.indices where s.assets[i].categoryID == oldID {
                    s.assets[i].categoryID = canonicalCatID
                }
            }
            // Proceed to field re-keying whether the canonical id pre-existed or was just
            // claimed above — this self-heals a mixed state (canonical category id, legacy
            // field ids) the same way as a fully-legacy one.
            rekeyCategoryFields(defs.map(\.definition), canonicalCatID: canonicalCatID, in: &s)
        }
    }

    /// For each canonical field definition: skip if the category already holds it (by either
    /// `id` or `definition.id` — the same dual-id dedup invariant `mergeSnapshot` enforces in
    /// AssetStore+Persistence.swift, and what makes this idempotent). Otherwise, exactly one
    /// template field sharing the canonical field's exact name → re-key both its own `id` and
    /// its `definition.id` to the canonical one (both are required: `upgradeBuiltInCategories`
    /// looks templates up by property `id`; `Asset.value(for:)` and `propagateTemplates` key on
    /// `definition.id`). Then repeat the same rewrite on every live asset of this category that
    /// still has a base property under the old `definition.id`, as long as doing so wouldn't
    /// collide with a property the asset already has under the canonical id.
    private static func rekeyCategoryFields(_ defs: [PropertyDefinition], canonicalCatID: UUID, in s: inout StoreSnapshotDTO) {
        guard let catIdx = s.categories.firstIndex(where: { $0.id == canonicalCatID }) else { return }
        for def in defs {
            guard !s.categories[catIdx].propertyTemplates.contains(where: {
                $0.id == def.id || $0.definition.id == def.id
            }) else { continue }

            let fieldCandidates = s.categories[catIdx].propertyTemplates.indices.filter {
                s.categories[catIdx].propertyTemplates[$0].definition.name == def.name
            }
            guard fieldCandidates.count == 1 else { continue }
            let fIdx = fieldCandidates[0]
            let oldDefID = s.categories[catIdx].propertyTemplates[fIdx].definition.id
            s.categories[catIdx].propertyTemplates[fIdx].id = def.id
            s.categories[catIdx].propertyTemplates[fIdx].definition.id = def.id

            for aIdx in s.assets.indices where s.assets[aIdx].categoryID == canonicalCatID {
                let occupied = s.assets[aIdx].baseProperties.contains(where: { $0.id == def.id || $0.definition.id == def.id })
                    || s.assets[aIdx].customProperties.contains(where: { $0.id == def.id || $0.definition.id == def.id })
                guard !occupied else { continue }
                for pIdx in s.assets[aIdx].baseProperties.indices
                where s.assets[aIdx].baseProperties[pIdx].definition.id == oldDefID {
                    s.assets[aIdx].baseProperties[pIdx].id = def.id
                    s.assets[aIdx].baseProperties[pIdx].definition.id = def.id
                }
            }
        }
    }
}
