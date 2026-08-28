import SwiftUI
import UIKit

/// Design tokens for the Baron Book visual system, transcribed from the `v8` handoff
/// prototype's `#v8-light` / `#v8-dark` custom-property blocks.
///
/// Every color is a single dynamic `Color` carrying both schemes, so views never branch on
/// `colorScheme` — the same token renders correctly in either. That is what lets the new screens
/// drop the old `.environment(\.colorScheme, .light)` pin that `AppBackground`'s gradients forced.
enum Baron {

    // MARK: - Surfaces

    /// Card and sheet surface — the prototype's `--sf`.
    static let surface = Color(light: 0xFFFFFF, dark: 0x1C2028)
    /// Screen ground — `--bg`.
    static let background = Color(light: 0xF7F7F8, dark: 0x12161E)
    /// Recessed fill inside a card: inputs, chips — `--bg2`.
    static let inset = Color(light: 0xF2F2F3, dark: 0x242A34)
    /// Hairline divider between rows in a grouped card — `--line`.
    static let line = Color(light: 0xF0F0F2, dark: 0x2A3039)

    // MARK: - Text and neutrals

    static let text = Color(light: 0x1D1F20, dark: 0xE9ECF0)
    static let neutral200 = Color(light: 0xE7E7EA, dark: 0x2A3039)
    static let neutral300 = Color(light: 0xD4D4D7, dark: 0x363D48)
    static let neutral400 = Color(light: 0xB7B7BA, dark: 0x4D5765)
    static let neutral500 = Color(light: 0x98989B, dark: 0x8D97A4)
    static let neutral600 = Color(light: 0x7A7A7D, dark: 0x9BA5B2)
    static let neutral700 = Color(light: 0x5D5D60, dark: 0xBAC3CD)

    // MARK: - Accent ramp

    static let accent100 = Color(light: 0xEEF6FF, dark: 0x1F2B3A)
    static let accent500 = Color(light: 0x749DC4, dark: 0x6D95BD)
    static let accent700 = Color(light: 0x416180, dark: 0x5F8CBA)
    static let accent800 = Color(light: 0x2C455D, dark: 0x5F8CBA)
    static let accent900 = Color(light: 0x1D2D3D, dark: 0x0D131C)
    /// Primary button fill — `--fill`. Diverges from `accent800` in dark, where a filled button
    /// needs to sit above the surface rather than match the accent text color.
    static let fill = Color(light: 0x2C455D, dark: 0x3A6693)

    // MARK: - Semantic

    static let danger = Color(light: 0x8C2F28, dark: 0xF0A49C)
    static let dangerBackground = Color(light: 0xFDECEB, dark: 0x3A201D)
    static let good = Color(light: 0x2F6B46, dark: 0x7FD0A3)
    static let goodBackground = Color(light: 0xE8F2EC, dark: 0x1E3229)

    // MARK: - Elevation

    /// The prototype's three shadow depths (`0 1px 4px`, `0 2px 9px`, `0 3px 10px` over
    /// `rgba(29,45,61,…)`). Suppressed in dark, where the palette separates surfaces by value
    /// instead — an ink shadow on a near-black ground reads as mud.
    enum Elevation { case low, medium, high }

    // MARK: - Type

    /// Headings — Barlow Condensed in the design. Falls back to the system font at a matching
    /// weight until `BarlowCondensed-SemiBold.ttf` is added to the bundle and declared in
    /// `UIAppFonts`, so the layout is correct either way.
    static func heading(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        custom("BarlowCondensed-SemiBold", size: size, fallbackWeight: weight)
    }

    /// Body copy — Barlow in the design, system fallback as above.
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black: name = "Barlow-SemiBold"
        case .medium: name = "Barlow-Medium"
        default: name = "Barlow-Regular"
        }
        return custom(name, size: size, fallbackWeight: weight)
    }

    private static func custom(_ name: String, size: CGFloat, fallbackWeight: Font.Weight) -> Font {
        guard UIFont(name: name, size: size) != nil else {
            return .system(size: size, weight: fallbackWeight)
        }
        return .custom(name, size: size)
    }

    // MARK: - Metrics

    enum Radius {
        static let chip: CGFloat = 999
        static let control: CGFloat = 11
        static let field: CGFloat = 14
        static let card: CGFloat = 18
        static let sheet: CGFloat = 24
    }

    /// Horizontal page inset used by every Baron screen.
    static let pageInset: CGFloat = 18
}

// MARK: - Helpers

extension Color {
    /// Builds a dynamic color from a light/dark pair of `0xRRGGBB` literals.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension View {
    /// Applies one of the design's elevation levels, and nothing at all in dark mode.
    func baronShadow(_ level: Baron.Elevation) -> some View {
        modifier(BaronShadow(level: level))
    }

    /// The standard Baron card: surface fill, rounded corners, elevation.
    func baronCard(radius: CGFloat = Baron.Radius.card, elevation: Baron.Elevation = .medium) -> some View {
        background(Baron.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .baronShadow(elevation)
    }
}

private struct BaronShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let level: Baron.Elevation

    func body(content: Content) -> some View {
        guard scheme == .light else { return AnyView(content) }
        let tint = Color(red: 29 / 255, green: 45 / 255, blue: 61 / 255)
        switch level {
        case .low:
            return AnyView(content.shadow(color: tint.opacity(0.06), radius: 2, y: 1))
        case .medium:
            return AnyView(content.shadow(color: tint.opacity(0.07), radius: 4.5, y: 2))
        case .high:
            return AnyView(content.shadow(color: tint.opacity(0.20), radius: 5, y: 3))
        }
    }
}
