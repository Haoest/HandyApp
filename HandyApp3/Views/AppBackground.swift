import SwiftUI

/// Foreground colors tuned to read well over a given background.
struct ThemePalette {
    let gradient: [Color]
    let gradientStart: UnitPoint
    let gradientEnd: UnitPoint
    let onBackground: Color
    let onBackgroundSecondary: Color
    let link: Color
    let deletedText: Color
    let iconTint: Color
}

/// User-selectable app backdrop. Each case is a calm, light, geometric gradient with a
/// matching foreground palette; the choice lives on `AssetStore.backgroundTheme`.
enum BackgroundTheme: String, CaseIterable, Identifiable {
    case mist, sand, facets

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mist: return "Mist"
        case .sand: return "Sand"
        case .facets: return "Facets"
        }
    }

    var palette: ThemePalette {
        switch self {
        case .mist:
            return ThemePalette(
                gradient: [
                    Color(red: 0.918, green: 0.945, blue: 0.984),
                    Color(red: 0.937, green: 0.922, blue: 0.980),
                    Color(red: 0.953, green: 0.965, blue: 0.984),
                ],
                gradientStart: .topLeading, gradientEnd: .bottomTrailing,
                onBackground: Color(red: 0.106, green: 0.141, blue: 0.200),
                onBackgroundSecondary: Color(red: 0.333, green: 0.376, blue: 0.478),
                link: Color(red: 0.180, green: 0.420, blue: 0.902),
                deletedText: Color(red: 0.55, green: 0.58, blue: 0.65),
                iconTint: Color(red: 0.227, green: 0.294, blue: 0.420)
            )
        case .sand:
            return ThemePalette(
                gradient: [
                    Color(red: 0.988, green: 0.957, blue: 0.925),
                    Color(red: 0.984, green: 0.933, blue: 0.941),
                    Color(red: 1.0, green: 0.969, blue: 0.941),
                ],
                gradientStart: .topLeading, gradientEnd: .bottomTrailing,
                onBackground: Color(red: 0.165, green: 0.137, blue: 0.125),
                onBackgroundSecondary: Color(red: 0.431, green: 0.373, blue: 0.345),
                link: Color(red: 0.710, green: 0.337, blue: 0.184),
                deletedText: Color(red: 0.62, green: 0.57, blue: 0.54),
                iconTint: Color(red: 0.478, green: 0.353, blue: 0.282)
            )
        case .facets:
            return ThemePalette(
                gradient: [
                    Color(red: 0.918, green: 0.953, blue: 0.941),
                    Color(red: 0.914, green: 0.941, blue: 0.973),
                ],
                gradientStart: .top, gradientEnd: .bottom,
                onBackground: Color(red: 0.086, green: 0.188, blue: 0.180),
                onBackgroundSecondary: Color(red: 0.310, green: 0.420, blue: 0.408),
                link: Color(red: 0.055, green: 0.486, blue: 0.482),
                deletedText: Color(red: 0.45, green: 0.55, blue: 0.54),
                iconTint: Color(red: 0.173, green: 0.337, blue: 0.329)
            )
        }
    }
}

/// The app's calm, geometric gradient backdrop, reflecting the user's chosen theme.
/// Drawn edge-to-edge; place content in a `ZStack` on top.
struct AppBackground: View {
    @Environment(AssetStore.self) private var store

    var body: some View {
        let theme = store.backgroundTheme
        let palette = theme.palette
        ZStack {
            LinearGradient(colors: palette.gradient, startPoint: palette.gradientStart, endPoint: palette.gradientEnd)
            GeometryReader { geo in
                decoration(for: theme, side: max(geo.size.width, geo.size.height))
            }
        }
        .ignoresSafeArea()
    }

    /// The per-theme overlay: soft radial glows for Mist/Sand, crisp translucent
    /// shapes for Facets.
    @ViewBuilder
    private func decoration(for theme: BackgroundTheme, side: CGFloat) -> some View {
        switch theme {
        case .mist:
            ZStack {
                glow(Color(red: 0.749, green: 0.831, blue: 0.949), at: .topLeading, radius: side * 0.7)
                glow(Color(red: 0.851, green: 0.800, blue: 0.949), at: .bottomTrailing, radius: side * 0.7)
            }
        case .sand:
            ZStack {
                glow(Color(red: 0.969, green: 0.851, blue: 0.745), at: .topLeading, radius: side * 0.7)
                glow(Color(red: 0.953, green: 0.796, blue: 0.847), at: .bottomTrailing, radius: side * 0.7)
            }
        case .facets:
            let mint = Color(red: 0.620, green: 0.816, blue: 0.788)
            let sky = Color(red: 0.686, green: 0.788, blue: 0.925)
            let line = Color(red: 0.173, green: 0.337, blue: 0.329)
            ZStack {
                RoundedRectangle(cornerRadius: 64, style: .continuous)
                    .fill(mint.opacity(0.20))
                    .frame(width: side * 0.75, height: side * 0.75)
                    .rotationEffect(.degrees(22))
                    .offset(x: -side * 0.22, y: -side * 0.28)
                RoundedRectangle(cornerRadius: 80, style: .continuous)
                    .fill(sky.opacity(0.18))
                    .frame(width: side * 0.85, height: side * 0.85)
                    .rotationEffect(.degrees(-16))
                    .offset(x: side * 0.30, y: side * 0.34)
                Circle()
                    .stroke(line.opacity(0.07), lineWidth: 2)
                    .frame(width: side * 0.55)
                    .offset(x: side * 0.12, y: -side * 0.06)
            }
        }
    }

    private func glow(_ color: Color, at point: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(
            gradient: Gradient(colors: [color.opacity(0.65), color.opacity(0)]),
            center: point, startRadius: 0, endRadius: radius
        )
    }
}
