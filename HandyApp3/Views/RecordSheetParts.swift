import SwiftUI

/// Shared chrome for the record editors. `EventEditView` and `TransactionEditView` were always
/// near-identical twins — same date/recurrence/due/notify/notes stack, differing only in the
/// title wording and the money block. The design draws them as one form, so their parts live
/// here rather than being transcribed twice.
///
/// Nothing here holds state. Both sheets keep their own `@State`, their `init`, and every bit
/// of the due-date/title projection logic exactly as it was — this is presentation only.

// MARK: - Sheet scaffold

/// Cancel · title · Save, over a Baron ground. Replaces the sheets' `NavigationStack { Form }`.
struct RecordSheetScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: LocalizedStringKey
    let saveLabel: LocalizedStringKey
    let canSave: Bool
    let onSave: () -> Void
    /// What the leading button does. Defaults to dismissing, which is right for a sheet's root
    /// view; a view *pushed* inside a sheet must pass its own closure, since `dismiss` there
    /// pops the stack rather than closing the sheet.
    var onCancel: (() -> Void)? = nil
    /// Whether the scaffold dismisses itself after a successful save. False when `onSave` owns
    /// the outcome — the create form, for instance, hands the new thing back to its presenter,
    /// which closes the sheet and then navigates.
    var dismissesOnSave: Bool = true
    /// Leading button label. "Back" where the action steps backward through a flow rather than
    /// abandoning it.
    var cancelLabel: LocalizedStringKey = "Cancel"
    @ViewBuilder let content: Content

    init(title: LocalizedStringKey, saveLabel: LocalizedStringKey, canSave: Bool,
         onSave: @escaping () -> Void, onCancel: (() -> Void)? = nil,
         dismissesOnSave: Bool = true, cancelLabel: LocalizedStringKey = "Cancel",
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.saveLabel = saveLabel
        self.canSave = canSave
        self.onSave = onSave
        self.onCancel = onCancel
        self.dismissesOnSave = dismissesOnSave
        self.cancelLabel = cancelLabel
        self.content = content()
    }

    var body: some View {
        ZStack {
            Baron.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) { content }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 24)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { if let onCancel { onCancel() } else { dismiss() } } label: {
                Text(cancelLabel)
                    .font(Baron.body(12.5, .medium))
                    .foregroundStyle(Baron.neutral700)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Baron.inset, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Text(title)
                .font(Baron.heading(15))
                .foregroundStyle(Baron.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button { onSave(); if dismissesOnSave { dismiss() } } label: {
                Text(saveLabel)
                    .font(Baron.heading(11.5))
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(Baron.fill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .opacity(canSave ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Baron.surface)
    }
}

// MARK: - Field chrome

/// Small uppercase caption above a field.
struct RecordFieldLabel: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(Baron.body(10.5, .medium))
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(Baron.neutral500)
    }
}

/// Labelled block wrapping any editor.
struct RecordField<Content: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RecordFieldLabel(text: label)
            content
        }
    }
}

extension View {
    /// The raised input the sheet uses for text and date fields.
    func recordInput() -> some View {
        font(Baron.body(15, .medium))
            .foregroundStyle(Baron.text)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .baronCard(radius: Baron.Radius.field, elevation: .low)
    }
}

/// A card whose header is a toggle and whose body only appears when it is on — the shape the
/// design uses for Repeats, Watch, and Notify.
struct RecordToggleCard<Content: View>: View {
    let title: LocalizedStringKey
    let hint: String
    let isOn: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(Baron.body(15, .medium))
                            .foregroundStyle(Baron.text)
                        Text(hint)
                            .font(Baron.body(11.5))
                            .foregroundStyle(Baron.neutral600)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ToggleTrack(isOn: isOn)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOn {
                VStack(alignment: .leading, spacing: 14) { content }
                    .padding(.top, 14)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .baronCard(elevation: .low)
    }
}

/// Wrapping pill picker over any `Hashable` option set — recurrence intervals here, but written
/// generically because the spec rows and category editor pick the same way.
struct RecordChipPicker<Option: Hashable>: View {
    let options: [Option]
    let selection: Option
    let title: (Option) -> String
    let onPick: (Option) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button { onPick(option) } label: {
                    Text(title(option))
                        .font(Baron.body(12, .medium))
                        .foregroundStyle(selected ? Color.white : Baron.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(selected ? Baron.fill : Baron.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(selected ? Color.clear : Baron.neutral300, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Label · value · slider. Same `DueDefaults.sliderRange` and day semantics as the old step slider,
/// restyled — the tick marks are dropped because the value now reads out above the track.
struct RecordDaySlider: View {
    let label: LocalizedStringKey
    @Binding var value: Int
    /// Shown instead of "N days" when the slider is at zero, e.g. "same day".
    var zeroLabel: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(Baron.body(12.5))
                    .foregroundStyle(Baron.neutral700)
                Spacer(minLength: 0)
                Group {
                    if value == 0, let zeroLabel {
                        Text(zeroLabel)
                    } else {
                        Text("^[\(value) day](inflect: true)")
                    }
                }
                .font(Baron.heading(13))
                .foregroundStyle(Baron.accent800)
                .monospacedDigit()
            }
            Slider(
                value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                in: Double(DueDefaults.sliderRange.lowerBound)...Double(DueDefaults.sliderRange.upperBound),
                step: 1
            )
            .tint(Baron.accent700)
        }
    }
}

/// The accent-tinted explanatory box the design uses to preview an effect.
struct RecordNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Baron.body(12))
            .foregroundStyle(Baron.accent800)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Baron.accent100, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

/// The date row. A compact `DatePicker` inside the sheet's own field chrome, so it matches the
/// text fields above and below it rather than bringing the system's row styling with it.
struct RecordDateField: View {
    let label: LocalizedStringKey
    @Binding var date: Date
    var footnote: LocalizedStringKey?

    var body: some View {
        RecordField(label: label) {
            VStack(alignment: .leading, spacing: 6) {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .baronCard(radius: Baron.Radius.field, elevation: .low)
                if let footnote {
                    Text(footnote)
                        .font(Baron.body(11.5))
                        .foregroundStyle(Baron.neutral600)
                }
            }
        }
    }
}
