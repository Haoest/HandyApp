import SwiftUI

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
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], spacing: 8) {
                    ForEach(filtered, id: \.self) { name in
                        Button { onSelect(name) } label: {
                            iconCell(name: name)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .searchable(text: $searchText, prompt: "Search symbols")
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func iconCell(name: String) -> some View {
        let selected = name == current
        let bg: Color = selected ? Color.accentColor.opacity(0.2) : Color(.secondarySystemGroupedBackground)
        let border: Color = selected ? Color.accentColor : .clear
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(bg)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(border, lineWidth: 2))
            Image(systemName: name)
                .font(.title2)
                .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
        }
        .frame(width: 56, height: 56)
    }
}
