import SwiftUI

/// A day-count slider that only lands on `DueDefaults.sliderSteps` (1/7/14/30/60). The
/// underlying `Slider` runs over step indices, not raw day counts, so it can't land in
/// between; a persisted value outside the step set (e.g. a hand-edited file) snaps to the
/// nearest step for display.
struct StepSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Int

    private var steps: [Int] { DueDefaults.sliderSteps }

    private var index: Double {
        Double(steps.enumerated().min(by: { abs($0.element - value) < abs($1.element - value) })?.offset ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value) days")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { index },
                    set: { value = steps[Int($0.rounded())] }
                ),
                in: 0...Double(steps.count - 1),
                step: 1
            )
        }
    }
}
