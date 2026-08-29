import SwiftUI

/// The symbol grid behind a category's icon. Presented as a sheet from both the category
/// editor and the new-category form, so it carries its own Baron chrome rather than the
/// record sheets' Cancel/Save header — there is nothing to save here, tapping a symbol is the
/// commit.
struct IconPickerView: View {
    let current: String
    let onSelect: (String) -> Void

    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private static let icons: [String] = [
        // Home & building
        "house", "house.fill", "building.2", "building.columns", "door.left.hand.closed",
        "window.horizontal", "archivebox", "tray", "tray.2",
        // Electronics
        "tv", "desktopcomputer", "laptopcomputer", "ipad", "iphone",
        "headphones", "speaker.wave.2", "hifispeaker", "printer", "keyboard",
        "mouse", "gamecontroller", "camera", "video", "photo",
        // Appliances
        "refrigerator", "washer", "dryer", "dishwasher", "oven",
        "microwave", "fan", "air.conditioner.vertical", "lightbulb", "lamp.desk",
        // Furniture
        "sofa", "bed.double", "table.furniture", "chair",
        // Vehicles
        "car", "car.fill", "truck.box", "bus", "bicycle",
        "scooter", "airplane", "ferry", "fuelpump",
        // Tools & hardware
        "wrench", "hammer", "screwdriver", "paintbrush", "shovel",
        "wrench.and.screwdriver", "gear", "gearshape", "gearshape.2",
        "bolt", "bolt.fill", "flashlight.on.fill",
        // Garden & outdoors
        "leaf", "tree", "drop.fill", "sun.max", "cloud",
        "snowflake", "flame", "wind", "umbrella",
        // Sports & hobbies
        "sportscourt", "football", "basketball", "baseball",
        "figure.run", "dumbbell", "guitar", "piano.keys",
        // Bags & clothing
        "tshirt", "briefcase", "bag", "handbag", "backpack", "suitcase",
        // Medical
        "cross.case", "pills", "stethoscope", "bandage", "heart",
        // Finance
        "creditcard", "banknote", "wallet.bifold", "dollarsign.circle",
        // Office
        "doc", "folder", "paperclip", "ruler", "pencil", "scissors",
        "book", "books.vertical", "magazine", "calendar", "clock",
        // Nature & pets
        "pawprint", "fish", "bird", "tortoise", "ant",
        // Food
        "fork.knife", "cup.and.saucer", "wineglass", "birthday.cake",
        // General
        "star", "bookmark", "tag", "flag", "location", "globe", "map",
        "bell", "music.note", "film", "alarm", "cart", "gift",
        "lock", "key", "person", "person.2", "barcode", "qrcode",
        "square.grid.2x2", "circle.grid.2x2", "rectangle.3.group",
    ]

    private var filtered: [String] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? Self.icons : Self.icons.filter { $0.contains(q) }
    }

    var body: some View {
        ZStack {
            Baron.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    if filtered.isEmpty {
                        Text("No symbol matches \"\(searchText)\".")
                            .font(Baron.body(13))
                            .foregroundStyle(Baron.neutral600)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 9)], spacing: 9) {
                        ForEach(filtered, id: \.self) { name in
                            Button { onSelect(name) } label: { iconCell(name: name) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Text("Cancel")
                        .font(Baron.body(12.5, .medium))
                        .foregroundStyle(Baron.neutral700)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Baron.inset, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Text("Choose a symbol")
                    .font(Baron.heading(15))
                    .foregroundStyle(Baron.text)
                Spacer(minLength: 0)
                // Balances the Cancel button so the title stays centred.
                Color.clear.frame(width: 62, height: 1)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Baron.neutral500)
                TextField("Search symbols", text: $searchText)
                    .font(Baron.body(14))
                    .foregroundStyle(Baron.text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Baron.neutral400)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Baron.inset, in: RoundedRectangle(cornerRadius: Baron.Radius.field, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Baron.surface)
    }

    private func iconCell(name: String) -> some View {
        let selected = name == current
        return Image(systemName: name)
            .font(.system(size: 21, weight: .light))
            .foregroundStyle(selected ? Color.white : Baron.text)
            .frame(width: 60, height: 60)
            .background(selected ? Baron.fill : Baron.surface,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Color.clear : Baron.neutral300, lineWidth: 1))
    }
}
