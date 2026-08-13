import Foundation

// MARK: - ComboListDefinition

/// A property type that presents a pick-list of string choices.
///
/// Options are split into two groups:
/// - `systemOptions` — seeded at creation; cannot be removed by the user.
/// - `userOptions`   — freely added or removed by the user at any time.
///
/// The computed `allOptions` (= systemOptions + userOptions) is the full
/// ordered list shown in the UI and used for validation.
///
/// When `isUserExtensible` is `true`, application users may type a brand-new
/// value to have it appended to `userOptions` automatically. When `false`,
/// only the predefined options are accepted.
final class ComboListDefinition: Identifiable, Equatable {
    let id: UUID
    var name: String

    /// Pre-seeded choices the creator locked in. Never removable by users.
    private(set) var systemOptions: [String]

    /// Choices the user has added beyond the system set.
    var userOptions: [String]

    /// Full ordered list: system options first, then user options.
    var allOptions: [String] { systemOptions + userOptions }

    /// When `true`, application users can type new values that are not yet in
    /// the list; those values are appended to `userOptions` automatically.
    /// When `false`, only the options already present in `allOptions` are accepted.
    let isUserExtensible: Bool

    /// Absolute instant `name` last changed. `userOptions` merges as a grow-only set rather
    /// than by timestamp — see `SnapshotReconciler` — but the header still needs one so a
    /// rename can be ordered against a peer's rename.
    var modifyDate: Date

    init(
        id: UUID = UUID(),
        name: String,
        systemOptions: [String] = [],
        userOptions: [String] = [],
        isUserExtensible: Bool = true,
        modifyDate: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.systemOptions = systemOptions
        self.userOptions = userOptions
        self.isUserExtensible = isUserExtensible
        self.modifyDate = modifyDate
    }

    static func == (lhs: ComboListDefinition, rhs: ComboListDefinition) -> Bool {
        lhs.id == rhs.id
    }
}
