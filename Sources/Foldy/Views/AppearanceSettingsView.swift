import FoldyCore
import SwiftUI

struct AppearanceSettingsView: View {
    var controller: AppController
    @State private var selectedChip: Chip?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var settings: SettingsStore { controller.settings }

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 24) {
            PaneHeader(title: "Appearance", symbol: "circle.lefthalf.filled", tint: .blue)

            previewStage

            VStack(alignment: .leading, spacing: 6) {
                (Text(chipTitle).bold() + Text(" ") + Text(chipBlurb))
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: selectedChip)
                Text(dragHint)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            // The pills move the preview and nothing else. The style, which is a saved
            // setting, is chosen from the thumbnails below; it used to be in this row too,
            // in the same pill as a lid position, and the two read as one kind of thing.
            // One container for the three: glass cannot sample glass, so without it each
            // one opens a backdrop of its own and they stop matching.
            GlassGroup(spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), alignment: .leading, spacing: 10) {
                    ForEach(Chip.allCases) { chip in
                        ChipButton(title: chip.title, selected: selectedChip == chip) {
                            select(chip)
                        }
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
                        .glassButtonStyle()
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

    /// The MacBook on a lit stage, with the lid control floating over it in glass.
    ///
    /// This is the one surface in Foldy with something worth refracting, so it is the
    /// one place the bar is glass rather than a card. The slider's thumb stays solid:
    /// glass inside glass cannot sample its neighbour and comes out flat.
    private var previewStage: some View {
        @Bindable var settings = settings
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return VStack(spacing: 0) {
            if let graphics = controller.graphics {
                MacBookPreviewView(
                    graphics: graphics,
                    lidAngle: controller.previewAngle,
                    parameters: settings.parameters,
                    curve: settings.curve
                )
                .frame(height: 320)
            } else {
                Text(controller.graphicsError ?? "Metal is not available.")
                    .foregroundStyle(.secondary)
                    .frame(height: 320)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 396)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.accentColor.opacity(0.20), .accentColor.opacity(0.05), .primary.opacity(0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .bottom) {
            GlassGroup(spacing: 20) {
                HStack(spacing: 14) {
                    FoldSlider(value: $settings.previewAngle, range: 0...FoldCurve.fullyOpenAngle)
                        .disabled(followsLid)
                        .onChange(of: settings.previewAngle) { _, angle in
                            if let chip = selectedChip, abs(chip.angle(curve: settings.curve) - angle) > 0.5 {
                                selectedChip = nil
                            }
                        }
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
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .glassBackground(in: Capsule())
            }
            .padding(14)
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(.primary.opacity(0.07)) }
    }

    private var followsLid: Bool {
        settings.previewFollowsLid && controller.sensorAvailable
    }

    private var dragHint: String {
        followsLid ? "Following the real lid. Switch it off to drag the angle yourself." : "Drag the bar over the preview to open and close the lid."
    }

    private var chipTitle: String {
        selectedChip?.title ?? "Foldable desktop."
    }

    private var chipBlurb: String {
        selectedChip?.blurb ?? "The fluid fold from iPhone Duo, for the lid you already have. Your desktop tilts, blurs and settles as it comes down."
    }

    private func select(_ chip: Chip) {
        selectedChip = chip
        if followsLid { settings.previewFollowsLid = false }
        settings.previewAngle = chip.angle(curve: settings.curve)
    }

    /// A lid position for the preview. Picking one only moves the lid; nothing is saved.
    enum Chip: String, CaseIterable, Identifiable {
        case open, halfway, closed
        var id: String { rawValue }

        var title: String {
            switch self {
            case .open: "Open."
            case .halfway: "Halfway."
            case .closed: "Closed."
            }
        }

        var blurb: String {
            switch self {
            case .open: "Lid all the way up. The desktop sits flat and sharp, nothing in the way."
            case .halfway: "The lid on its way down. The desktop tilts back and the top begins to blur."
            case .closed: "Almost shut. The desktop settles into its fold, soft and shaded, a breath before the Mac sleeps."
            }
        }

        func angle(curve: FoldCurve) -> Double {
            switch self {
            case .open: FoldCurve.fullyOpenAngle
            case .halfway: curve.angle(forFraction: 0.5)
            case .closed: curve.angle(forFraction: 0.97)
            }
        }
    }
}

/// A pill with a plus in a circle, the way the iPhone Duo page lists its states.
/// Glass on Tahoe; the one that is picked takes the accent-tinted prominent capsule.
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
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Glass only registers hits where there is content; without this the
            // padding around a short word is dead.
            .contentShape(.capsule)
        }
        .glassButtonStyle(selected ? .prominent : .standard)
        .buttonBorderShape(.capsule)
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
                // Whole degrees, but rounded on the way in rather than with `step:`,
                // which on macOS draws a tick for every step: seventy of them here.
                Slider(value: Binding(get: { value }, set: { value = $0.rounded() }), in: range)
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
