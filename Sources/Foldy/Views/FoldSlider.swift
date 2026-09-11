import SwiftUI

/// The drag control from Apple's iPhone Duo page: a grey track and a round blue thumb
/// with chevrons pointing both ways.
struct FoldSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragging = false

    private let thumbSize: CGFloat = 40
    private let trackHeight: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let travel = max(width - thumbSize, 1)
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let x = CGFloat(fraction.clamped()) * travel

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: x + thumbSize / 2, height: trackHeight)
                ZStack {
                    Circle()
                        .fill(isEnabled ? Color.accentColor : Color.gray)
                        .shadow(color: .black.opacity(dragging ? 0.28 : 0.18), radius: dragging ? 8 : 4, y: 2)
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                }
                .frame(width: thumbSize, height: thumbSize)
                .scaleEffect(dragging && !reduceMotion ? 1.08 : 1)
                .offset(x: x)
                .animation(reduceMotion ? nil : .spring(duration: 0.25), value: dragging)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        dragging = true
                        let fraction = Double((drag.location.x - thumbSize / 2) / travel).clamped()
                        value = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in dragging = false }
            )
        }
        .frame(height: thumbSize)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityElement()
        .accessibilityLabel("Lid angle")
        .accessibilityValue("\(Int(value.rounded())) degrees")
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
        }
    }
}

private extension Double {
    func clamped() -> Double { Swift.min(Swift.max(self, 0), 1) }
}
