import SwiftUI

// MARK: - ComboListField

/// A text field with tap-to-fill option rows drawn from a `ComboListDefinition`. While focused,
/// options matching the current draft appear as tappable rows directly beneath the field —
/// mirroring the word-suggestion pattern in `PropertyEditView`'s Name field — but the user can
/// still type any value they like.
///
/// Holds a local draft and reports exactly one commit per completed edit rather than a live
/// `Binding<String>`: several call sites write straight through to the store on every set, and a
/// per-keystroke write would run `AssetStore.handleComboListAutoAdd` on every prefix typed —
/// appending "E", "El", "Ele", … to `userOptions` for an extensible list, each one syncing under
/// a grow-only union that never lets a peer remove them.
struct ComboListField: View {
    let label: String?
    let list: ComboListDefinition
    /// Authoritative value from the owner (`nil`-backed `StoredValue?` reduced to `""`).
    let current: String
    /// The owning property's character bound, if any. Suggestion pills longer than this are
    /// dropped rather than offered — tapping one would commit a value the field can't actually
    /// hold once clamped, silently storing something that matches no option on the list.
    var maxLength: Int? = nil
    var onEditLabel: (() -> Void)? = nil
    /// Called once per completed edit. `nil` means the value was cleared.
    let onCommit: (String?) -> Void

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(
        label: String?,
        list: ComboListDefinition,
        current: String,
        maxLength: Int? = nil,
        onEditLabel: (() -> Void)? = nil,
        onCommit: @escaping (String?) -> Void
    ) {
        self.label = label
        self.list = list
        self.current = current
        self.maxLength = maxLength
        self.onEditLabel = onEditLabel
        self.onCommit = onCommit
        _draft = State(initialValue: current)
    }

    /// Options matching `draft`, case- and diacritic-insensitive, capped at 10 (matching
    /// `PropertyEditView.suggestions`). An empty draft returns every option. Returns `[]` once
    /// the draft already exactly matches its only remaining match — nothing left to suggest.
    /// Forwards to the model-layer rule so the view and its tests share one definition.
    static func matches(for draft: String, in list: ComboListDefinition) -> [String] {
        list.matchingOptions(for: draft)
    }

    private var suggestions: [String] {
        let matches = Self.matches(for: draft, in: list)
        guard let maxLength else { return matches }
        return matches.filter { $0.count <= maxLength }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label {
                PropertyLabel(name: label, onEditLabel: onEditLabel)
            }
            TextField("", text: $draft)
                .focused($isFocused)
                .autocorrectionDisabled()
                .onSubmit { commit() }
                .commitsPendingEdit(focused: isFocused) { commit() }
                .limitLength(maxLength, text: $draft)
                .onChange(of: current) { _, new in
                    guard !isFocused else { return }
                    draft = new
                }
            if isFocused {
                FlowLayout(spacing: 8) {
                    ForEach(suggestions, id: \.self) { option in
                        Text(option)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundStyle(.tint)
                            .contentShape(Capsule())
                            .onTapGesture { choose(option) }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func choose(_ option: String) {
        draft = option
        isFocused = false
        commit()
    }

    /// Idempotent and dirty-checked, per `commitsPendingEdit`'s contract — `choose` and focus
    /// loss both call this, and the second call must be a no-op.
    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard trimmed != current else { return }
        if trimmed.isEmpty {
            onCommit(nil)
            return
        }
        if !list.isUserExtensible && !list.allOptions.contains(trimmed) {
            // The store's validate(stored:against:) would reject this anyway; revert rather
            // than let the field hold a value it can never successfully commit.
            draft = current
            return
        }
        onCommit(trimmed)
    }
}

// MARK: - FlowLayout

/// Lays out its children left-to-right, wrapping to a new row when the next child would
/// overflow the available width — the natural "pill row" flow `ComboListField`'s suggestion
/// chips want, which none of `HStack`/`LazyVGrid` produce on their own.
/// Wrapping row layout. Internal rather than file-private since the Thing detail screen's
/// combo-list editor lays its option chips out the same way.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)

        // Report the full proposed width when finite, not just the widest row (`totalWidth`).
        // `placeSubviews` below is handed bounds matching whatever size this method returns, so
        // if the two disagree on available width they wrap rows differently — placement then
        // wraps more aggressively than this height accounted for, and the trailing row(s) land
        // outside the reported bounds and get clipped by the container. Falling back to the
        // hugging `totalWidth` only when the proposal itself is unconstrained.
        let width = maxWidth.isFinite ? maxWidth : totalWidth
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + spacing + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
