import FoldyCore
import SwiftUI

struct AppearanceSettingsView: View {
    var controller: AppController
    @State private var selectedChip: Chip?

    private var settings: SettingsStore { controller.settings }

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 24) {
            PaneHeader(title: "Appearance", symbol: "circle.lefthalf.filled", tint: .blue)

            if let graphics = controller.graphics {
                MacBookPreviewView(
                    graphics: graphics,
                    lidAngle: controller.previewAngle,
                    parameters: settings.parameters,
                    curve: settings.curve
                )
                .frame(height: 340)
                .frame(maxWidth: .infinity)
            } else {
                Text(controller.graphicsError ?? "Metal is not available.")
                    .foregroundStyle(.secondary)
            }

            // The "take a closer look" panel: a sentence about the state, the drag hint,
            // and the slider that opens and closes the lid.
            VStack(alignment: .leading, spacing: 14) {
                (Text(chipTitle).bold() + Text(" ") + Text(chipBlurb))
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.easeOut(duration: 0.2), value: selectedChip)
                Text(dragHint)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    FoldSlider(value: $settings.previewAngle, range: 0...FoldCurve.fullyOpenAngle)
                        .disabled(followsLid)
                        .onChange(of: settings.previewAngle) { _, _ in selectedChip = nil }
                    Text("\(Int(controller.previewAngle.rounded()))°")
                        .font(.system(size: 14, weight: .medium).monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                    Toggle(isOn: $settings.previewFollowsLid) {
                        Text("Follow lid")
                    }
                    .toggleStyle(.switch)
                    .disabled(!controller.sensorAvailable)
                    .help(controller.sensorAvailable ? "Move the preview with the real lid." : "No lid angle sensor on this Mac.")
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.quaternary.opacity(0.45)))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), alignment: .leading, spacing: 10) {
                ForEach(Chip.allCases) { chip in
                    ChipButton(title: chip.title, selected: selectedChip == chip) {
                        select(chip)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Style")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                HStack(spacing: 14) {
                    ForEach(FoldStyle.allCases) { style in
                        StyleCard(controller: controller, style: style, selected: settings.style == style) {
                            settings.style = style
                            selectedChip = nil
                            controller.evaluate()
                        }
                    }
                }
            }

            SettingsCard(title: settings.parametersAreCustom ? "\(settings.style.title), tuned" : settings.style.title) {
                ParameterRow(title: "Perspective", value: $settings.parameters.perspective)
                RowDivider()
                ParameterRow(title: "Variable blur", value: $settings.parameters.blur)
                RowDivider()
                ParameterRow(title: "Shadow", value: $settings.parameters.shadow)
                RowDivider()
                ParameterRow(title: "Bend", value: $settings.parameters.bend)
                RowDivider()
                ParameterRow(title: "Frost", value: $settings.parameters.frost)
                RowDivider()
                SettingsRow(title: "Reset to the \(settings.style.title) defaults") {
                    Button("Reset") { settings.resetParameters() }
                        .disabled(!settings.parametersAreCustom)
                }
            }

            SettingsCard(title: "Angles") {
                AngleRow(title: "Clears at", subtitle: "Above this hinge angle the desktop is flat and the fold is gone.",
                         value: $settings.curve.clearAngle, range: 60...130)
                RowDivider()
                AngleRow(title: "Folded at", subtitle: "At this angle the fold is complete. macOS sleeps a few degrees later.",
                         value: $settings.curve.foldedAngle, range: 5...50)
            }
            .onChange(of: settings.curve) { _, _ in controller.evaluate() }
        }
        .onChange(of: settings.parameters) { _, _ in controller.evaluate() }
    }

    private var followsLid: Bool {
        settings.previewFollowsLid && controller.sensorAvailable
    }

    private var dragHint: String {
        followsLid ? "Following the lid. Switch it off to drag the angle yourself." : "Drag below to open and close"
    }

    private var chipTitle: String {
        selectedChip?.title ?? "Foldable desktop."
    }

    private var chipBlurb: String {
        selectedChip?.blurb ?? "The fluid fold from iPhone Duo, for the lid you already have. Your desktop tilts, blurs and settles as it comes down."
    }

    private func select(_ chip: Chip) {
        selectedChip = chip
        if let style = chip.style {
            settings.style = style
            controller.evaluate()
        }
        if followsLid { settings.previewFollowsLid = false }
        settings.previewAngle = chip.angle(curve: settings.curve)
        // The slider's onChange clears the chip; put it back after the write lands.
        DispatchQueue.main.async { selectedChip = chip }
    }

    enum Chip: String, CaseIterable, Identifiable {
        case open, halfway, closed, silk, shade, frost
        var id: String { rawValue }

        var title: String {
            switch self {
            case .open: "Open."
            case .halfway: "Halfway."
            case .closed: "Closed."
            case .silk: "Silk."
            case .shade: "Shade."
            case .frost: "Frost."
            }
        }

        var blurb: String {
            switch self {
            case .open: "Lid all the way up. The desktop sits flat and sharp, nothing in the way."
            case .halfway: "The lid on its way down. The desktop tilts back and the top begins to blur."
            case .closed: "Almost shut. The desktop settles into its fold, soft and shaded, a breath before the Mac sleeps."
            case .silk: FoldStyle.silk.summary
            case .shade: FoldStyle.shade.summary
            case .frost: FoldStyle.frost.summary
            }
        }

        var style: FoldStyle? {
            switch self {
            case .silk: .silk
            case .shade: .shade
            case .frost: .frost
            default: nil
            }
        }

        func angle(curve: FoldCurve) -> Double {
            switch self {
            case .open: FoldCurve.fullyOpenAngle
            case .halfway: curve.angle(forFraction: 0.5)
            case .closed: curve.angle(forFraction: 0.97)
            case .silk, .shade, .frost: curve.angle(forFraction: 0.62)
            }
        }
    }
}

/// A pill with a plus in a circle, the way the iPhone Duo page lists its states.
struct ChipButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 15, weight: .medium))
                Text(title.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Capsule().fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06)))
            .overlay(Capsule().strokeBorder(selected ? Color.accentColor.opacity(0.6) : .clear))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.accentColor : .primary)
    }
}

struct StyleCard: View {
    var controller: AppController
    let style: FoldStyle
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Group {
                    if let graphics = controller.graphics {
                        FoldThumbnailView(graphics: graphics, parameters: controller.settings.parameters(for: style))
                    } else {
                        Color.black
                    }
                }
                .aspectRatio(MacBookScene.screenAspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1))
                HStack(spacing: 5) {
                    Text(style.title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .help(style.summary)
    }
}

struct ParameterRow: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .frame(width: 120, alignment: .leading)
            Slider(value: $value, in: 0...1)
            Text("\(Int((value * 100).rounded()))%")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct AngleRow: View {
    let title: String
    let subtitle: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                Text(title)
                    .frame(width: 120, alignment: .leading)
                Slider(value: $value, in: range, step: 1)
                Text("\(Int(value.rounded()))°")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
