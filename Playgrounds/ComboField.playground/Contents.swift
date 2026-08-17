import SwiftUI
import PlaygroundSupport

// A "combo list" field: pick from suggestions, or type anything you want.
//
// Native route  -> TextField + .textInputSuggestions (iOS 18+)
// Manual route  -> TextField + chevron Menu + inline match list (any iOS)

let powerSources = ["Battery", "Corded Electric", "Gas", "Propane", "Solar", "Manual Crank"]

func matches(for text: String, in options: [String]) -> [String] {
    guard !text.isEmpty else { return options }
    return options.filter { $0.localizedCaseInsensitiveContains(text) }
}

// MARK: - Native: .textInputSuggestions

struct ComboField: View {
    let label: String
    let options: [String]
    @Binding var text: String

    var body: some View {
        TextField(label, text: $text)
            .textInputSuggestions {
                ForEach(matches(for: text, in: options), id: \.self) { option in
                    // textInputCompletion is what makes the row pickable —
                    // without it the row is just decoration.
                    Text(option).textInputCompletion(option)
                }
            }
    }
}

// MARK: - Manual: full control over presentation

struct ManualComboField: View {
    let label: String
    let options: [String]
    @Binding var text: String
    @FocusState private var isFocused: Bool

    private var suggestions: [String] {
        let m = matches(for: text, in: options)
        // Hide the list once the text is already an exact pick.
        return m == [text] ? [] : m
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField(label, text: $text)
                    .focused($isFocused)
                Menu {
                    ForEach(options, id: \.self) { option in
                        Button(option) {
                            text = option
                            isFocused = false
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if isFocused && !suggestions.isEmpty {
                Divider().padding(.top, 8)
                ForEach(suggestions, id: \.self) { option in
                    Button {
                        text = option
                        isFocused = false
                    } label: {
                        HStack {
                            Text(option)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }
        }
    }
}

// MARK: - Demo

struct DemoView: View {
    @State private var native = ""
    @State private var manual = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ComboField(label: "Power source", options: powerSources, text: $native)
                } header: {
                    Text("Native · .textInputSuggestions")
                } footer: {
                    Text("Tap the field. Suggestions appear while focused and filter as you type — but you can still commit any text you like. iOS 18+.")
                }

                Section {
                    ManualComboField(label: "Power source", options: powerSources, text: $manual)
                } header: {
                    Text("Manual · TextField + Menu")
                } footer: {
                    Text("Same behavior, drawn by hand: chevron opens the full list, and matches expand inline under the field while it is focused.")
                }

                Section("Stored values") {
                    LabeledContent("Native", value: native.isEmpty ? "—" : native)
                    LabeledContent("Manual", value: manual.isEmpty ? "—" : manual)
                }
            }
            .navigationTitle("Combo list field")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

PlaygroundPage.current.setLiveView(
    DemoView().frame(width: 390, height: 780)
)
