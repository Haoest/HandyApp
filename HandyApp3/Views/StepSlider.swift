import SwiftUI

/// A day-count slider spanning the full `DueDefaults.sliderRange` (1–60 days), every value
/// equally reachable, with tick marks at `DueDefaults.sliderTickDays` as a purely visual
/// reference (no snapping). Built on the native `Slider` (not a hand-rolled drag control) to
/// keep its accessibility for free — VoiceOver adjustable actions, Dynamic Type — at the cost
/// of the tick overlay only approximating the thumb's true radius, which Apple doesn't expose.
struct StepSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Int

    private var range: ClosedRange<Int> { DueDefaults.sliderRange }
    private var ticks: [Int] { DueDefaults.sliderTickDays }
    /// Approximates the native Slider thumb's radius so ticks line up with its travel.
    private let thumbInset: CGFloat = 11

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value) days")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            .overlay(
                GeometryReader { geo in
                    let trackWidth = max(geo.size.width - thumbInset * 2, 0)
                    ForEach(ticks, id: \.self) { tick in
                        Rectangle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 1, height: 5)
                            .position(x: thumbInset + xFraction(for: tick) * trackWidth, y: geo.size.height - 2)
                    }
                }
                .allowsHitTesting(false)
            )
        }
    }

    private func xFraction(for day: Int) -> CGFloat {
        CGFloat(day - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)
    }
}
