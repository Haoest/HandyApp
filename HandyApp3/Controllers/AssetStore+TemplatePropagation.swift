import Foundation

/// What one propagation run changes across the assets of a category. Returned by both the dry
/// run and the apply, so a confirmation dialog and its result alert always describe the same
/// thing.
struct TemplatePropagationSummary: Equatable {
    /// Live, non-purged, non-deleted assets of the category the run considered.
    var eligibleAssetCount = 0
    /// Of those, how many gain, lose, or refresh at least one base property.
    var affectedAssetCount = 0
    /// Base properties appended, or revived from an earlier tombstone.
    var added = 0
    /// Base properties tombstoned because their template is no longer live.
    var removed = 0
    /// Base properties whose definition (name / type / referenced type / isRequired) was
    /// refreshed to match the template.
    var refreshed = 0
    /// Of `refreshed`, how many also lost a stored value that no longer validates against the
    /// refreshed type. Always ≤ `refreshed`.
    var valuesCleared = 0
    /// Base properties whose `sortOrder` was brought in line with its template's — i.e. the
    /// asset had reordered its own copy (via `AssetStore.moveBaseProperties`) since the
    /// category's own order last changed.
    var reordered = 0

    var isEmpty: Bool { added == 0 && removed == 0 && refreshed == 0 && reordered == 0 }
}

extension AssetStore {

    /// Dry run of `propagateTemplates(forCategoryID:)` — computes the same plan without
    /// mutating anything.
    func previewTemplatePropagation(forCategoryID categoryID: UUID) throws -> TemplatePropagationSummary {
        try templatePropagationPlan(forCategoryID: categoryID).summary
    }

    /// Reconciles every live asset of the category with its current property templates: adds
    /// fields the category gained, tombstones base properties for fields the category lost, and
    /// refreshes the definition of fields that were renamed / retyped / had `isRequired` change.
    ///
    /// Deliberately does not overwrite a value already entered on an asset with the template's
    /// default — that only happens for a field the asset never had before (the `add` case, which
    /// matches what `createAsset` already does for a brand-new asset). A value is cleared only
    /// when a refreshed type makes it invalid (see `validate(stored:against:definitionName:)`).
    ///
    /// `createAsset`, `Asset.baseProperties`, and `removeTemplateProperty` document that a
    /// template edit does not reach existing assets on its own — this is the explicit,
    /// user-triggered action that does.
    ///
    /// Also flattens the category's own templates onto a clean `0, 10, 20, …` ladder in their
    /// current display order before stamping that order onto the assets — see
    /// `normalizedTemplateSortOrders`. That normalization runs even when no asset needs any
    /// other change, so the ladder is a property of having run this action at all.
    @discardableResult
    func propagateTemplates(forCategoryID categoryID: UUID) throws -> TemplatePropagationSummary {
        let plan = try templatePropagationPlan(forCategoryID: categoryID)
        let now = Date()
        let normalizedAnyTemplate = applyNormalizedTemplateSortOrders(
            plan.normalizedSortOrders, forCategoryID: categoryID, at: now
        )
        guard !plan.work.isEmpty else {
            if normalizedAnyTemplate { markDirty() }
            return plan.summary
        }

        for (asset, changes) in plan.work {
            for change in changes {
                switch change {
                case .add(let template, let sortOrder):
                    // id: mirrors the template's definition id rather than a fresh UUID — see
                    // `seedBuiltInCategories`'s identical trick (BuiltInTypes.swift) for why:
                    // two devices independently propagating the same new field must mint the
                    // same AssetProperty.id, or SnapshotReconciler's union-by-id merge keeps
                    // both records and Asset.value(for:) silently resolves only one of them.
                    let prop = AssetProperty(
                        id: template.definition.id,
                        definition: template.definition,
                        value: template.value,
                        sortOrder: sortOrder,
                        modifyDate: now
                    )
                    asset.baseProperties.append(prop)

                case .revive(let property, let definition, let sortOrder, let clearsValue):
                    property.isDeleted = false
                    property.deletedAt = nil
                    property.definition = definition
                    property.sortOrder = sortOrder
                    if clearsValue {
                        property.value = nil
                    } else if let value = property.value {
                        handleComboListAutoAdd(stored: value, type: definition.type)
                    }
                    property.touch(now)

                case .remove(let property):
                    property.isDeleted = true
                    property.deletedAt = now
                    property.touch(now)

                case .refresh(let property, let definition, let clearsValue):
                    property.definition = definition
                    if clearsValue {
                        property.value = nil
                    } else if let value = property.value {
                        handleComboListAutoAdd(stored: value, type: definition.type)
                    }
                    property.touch(now)

                case .reorder(let property, let sortOrder):
                    property.sortOrder = sortOrder
                    property.touch(now)
                }
            }
            asset.modifiedDate = now
        }
        markDirty()
        return plan.summary
    }

    // MARK: - Plan

    private enum BasePropertyChange {
        /// A template with no matching base property at all — append a fresh one, at the
        /// template's normalized `sortOrder`.
        case add(template: AssetProperty, sortOrder: Double)
        /// A template whose base property exists but is tombstoned — bring it back to life
        /// rather than appending a duplicate `definition.id`, at the template's current
        /// `sortOrder` (its position may have moved since the property was removed).
        case revive(property: AssetProperty, definition: PropertyDefinition, sortOrder: Double, clearsValue: Bool)
        /// A live base property whose template is gone — tombstone it.
        case remove(property: AssetProperty)
        /// A live base property whose definition drifted from its template — refresh it.
        case refresh(property: AssetProperty, definition: PropertyDefinition, clearsValue: Bool)
        /// A live base property whose `sortOrder` drifted from its template's — e.g. the
        /// category's fields were reordered since the asset was created or last propagated.
        case reorder(property: AssetProperty, sortOrder: Double)
    }

    /// The clean `0, 10, 20, …` ladder a category's templates should carry, keyed by template
    /// id, following their current *display* order (`SortOrdering.precedes`).
    ///
    /// Reordering deliberately leaves fractional midpoint values behind (see `SortOrdering`),
    /// which is right for an interactive drag but makes a poor thing to stamp onto every asset
    /// of the category. A propagation run is the natural place to flatten them: it's explicit,
    /// user-initiated, already rewrites every affected asset, and — unlike a drag — isn't
    /// trying to keep its write footprint small.
    private static func normalizedTemplateSortOrders(_ liveTemplates: [AssetProperty]) -> [UUID: Double] {
        let ordered = liveTemplates.sorted(by: SortOrdering.precedes)
        let values = SortOrdering.normalized(count: ordered.count)
        return Dictionary(uniqueKeysWithValues: zip(ordered.map(\.id), values))
    }

    /// Writes the ladder from `normalizedTemplateSortOrders` onto the category's templates,
    /// touching only the ones whose value actually moves. Returns whether anything changed.
    @discardableResult
    private func applyNormalizedTemplateSortOrders(
        _ normalized: [UUID: Double], forCategoryID categoryID: UUID, at now: Date
    ) -> Bool {
        guard let category = categories[categoryID] else { return false }
        var changed = false
        for template in category.propertyTemplates {
            guard let target = normalized[template.id], template.sortOrder != target else { continue }
            template.sortOrder = target
            template.touch(now)
            changed = true
        }
        return changed
    }

    /// One pass that both `previewTemplatePropagation` and `propagateTemplates` consume, so the
    /// dialog the user confirms can never disagree with what actually gets written. That's also
    /// why the normalized ladder is computed *here* rather than applied to the templates first
    /// and re-planned against: the preview must not mutate, so both sides plan against the same
    /// target values and only the apply writes them.
    private func templatePropagationPlan(forCategoryID categoryID: UUID)
        throws -> (summary: TemplatePropagationSummary,
                   work: [(asset: Asset, changes: [BasePropertyChange])],
                   normalizedSortOrders: [UUID: Double])
    {
        guard let category = categories[categoryID] else { throw AssetStoreError.categoryNotFound(categoryID) }

        let liveTemplates = category.liveTemplates
        let normalizedSortOrders = Self.normalizedTemplateSortOrders(liveTemplates)
        var liveByDefID: [UUID: AssetProperty] = [:]
        for template in liveTemplates {
            liveByDefID[template.definition.id] = template
        }

        var summary = TemplatePropagationSummary()
        var work: [(asset: Asset, changes: [BasePropertyChange])] = []

        // Not `assets(ofCategoryID:)`: that filters only `!isPurged`, so it includes assets
        // sitting in Trash. Bumping `modifiedDate` on a soft-deleted asset would rescue it from
        // the retention sweep permanently (`Asset.isProtectedFromAutoPurge`), so a run must skip
        // `isDeleted` assets entirely.
        let eligibleAssets = assets.values.filter {
            $0.category.id == categoryID && !$0.isDeleted && !$0.isPurged
        }
        summary.eligibleAssetCount = eligibleAssets.count

        for asset in eligibleAssets {
            // Raw, not `liveBaseProperties` — a tombstoned entry must still be found here so it
            // gets revived instead of shadowed by a second `.add` for the same `definition.id`.
            var byDefID: [UUID: AssetProperty] = [:]
            for prop in asset.baseProperties where byDefID[prop.definition.id] == nil {
                byDefID[prop.definition.id] = prop
            }
            // Also raw: `value(for:)`/`setPropertyValue` search base before custom, so appending
            // a base property that shadows a live custom one with the same `definition.id` would
            // make the custom property unreachable (see AssetStore+Persistence.swift's identical
            // dedupe rule for the additive-import path).
            let customDefIDs = Set(asset.customProperties.map { $0.definition.id })

            var changes: [BasePropertyChange] = []

            // Sorted by the templates' own display order (`SortOrdering.precedes`), not raw
            // array position: a reorder changes a template's `sortOrder` in place rather than
            // moving it within `propertyTemplates`, so array order no longer tracks display
            // order once a category has been reordered at least once.
            let missingTemplates = liveTemplates
                .filter { byDefID[$0.definition.id] == nil && !customDefIDs.contains($0.definition.id) }
                .sorted(by: SortOrdering.precedes)
            for template in missingTemplates {
                changes.append(.add(template: template, sortOrder: normalizedSortOrders[template.id] ?? template.sortOrder))
                summary.added += 1
            }

            for prop in asset.baseProperties {
                guard let template = liveByDefID[prop.definition.id] else {
                    if !prop.isDeleted {
                        changes.append(.remove(property: prop))
                        summary.removed += 1
                    }
                    continue
                }
                let clearsValue = prop.value != nil && (try? validate(
                    stored: prop.value!, against: template.definition.type, definitionName: template.definition.name
                )) == nil
                let targetSortOrder = normalizedSortOrders[template.id] ?? template.sortOrder
                if prop.isDeleted {
                    changes.append(.revive(
                        property: prop, definition: template.definition, sortOrder: targetSortOrder, clearsValue: clearsValue
                    ))
                    summary.added += 1
                    continue
                }
                if prop.definition != template.definition {
                    changes.append(.refresh(property: prop, definition: template.definition, clearsValue: clearsValue))
                    summary.refreshed += 1
                    if clearsValue { summary.valuesCleared += 1 }
                }
                if prop.sortOrder != targetSortOrder {
                    changes.append(.reorder(property: prop, sortOrder: targetSortOrder))
                    summary.reordered += 1
                }
            }

            if !changes.isEmpty {
                summary.affectedAssetCount += 1
                work.append((asset, changes))
            }
        }

        return (summary, work, normalizedSortOrders)
    }
}
