import Combine
import FoldyCore
import SwiftUI

struct OnboardingView: View {
    static let width: CGFloat = 780
    static let height: CGFloat = 620

    var controller: AppController
    let onFinish: () -> Void
    @State private var step: Step
    @State private var direction: Edge = .trailing
    @Namespace private var footerGlass

    init(controller: AppController, initialStep: Int, onFinish: @escaping () -> Void) {
        self.controller = controller
        self.onFinish = onFinish
        _step = State(initialValue: Step(rawValue: min(max(initialStep, 0), Step.allCases.count - 1)) ?? .welcome)
    }

    enum Step: Int, CaseIterable {
        case welcome, lid, capture, style, done
    }

    private var settings: SettingsStore { controller.settings }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case .welcome: WelcomeStep(controller: controller)
                case .lid: LidStep(controller: controller)
                case .capture: CaptureStep(controller: controller)
                case .style: StyleStep(controller: controller)
                case .done: DoneStep(controller: controller)
                }
            }
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: direction).combined(with: .opacity),
                                    removal: .move(edge: direction == .trailing ? .leading : .trailing).combined(with: .opacity)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 48)
            .padding(.top, 36)
            .clipped()

            footer
        }
        .frame(width: Self.width, height: Self.height)
        .background(.background)
        // A screenshot run opens the tour at a given step and quits; persisting that
        // would leave the developer's own tour parked wherever `make shots` left it.
        .onChange(of: step) { _, new in
            guard !DevFlags.isScreenshotRun else { return }
            settings.onboardingStep = new.rawValue
        }
        .onAppear {
            controller.refreshPermission()
            guard !DevFlags.isScreenshotRun else { return }
            settings.onboardingStep = step.rawValue
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            HStack(spacing: 7) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Capsule()
                        .fill(s == step ? Color.primary : Color.primary.opacity(0.18))
                        .frame(width: s == step ? 22 : 7, height: 7)
                        .animation(.spring(duration: 0.35), value: step)
                }
            }
            Spacer()
            GlassGroup(spacing: 14) {
                HStack(spacing: 14) {
                    // Back is absent on the first step; the ids let its glass flow out
                    // of the button beside it rather than fade in on its own.
                    if step != .welcome {
                        Button("Back") { go(-1) }
                            .keyboardShortcut(.leftArrow, modifiers: [])
                            .glassButtonStyle()
                            .glassMorphID("back", in: footerGlass)
                    }
                    if step == .done {
                        Button("Finish") { finish() }
                            .keyboardShortcut(.defaultAction)
                            .glassButtonStyle(.prominent)
                            .glassMorphID("forward", in: footerGlass)
                    } else {
                        Button(continueTitle) { go(1) }
                            .keyboardShortcut(.defaultAction)
                            .glassButtonStyle(.prominent)
                            .glassMorphID("forward", in: footerGlass)
                            .disabled(step == .capture && controller.needsRelaunchForPermission)
                    }
                }
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 40)
        .padding(.vertical, 22)
        .overlay(alignment: .top) { Divider() }
    }

    private var continueTitle: String {
        switch step {
        case .capture where !controller.hasScreenPermission: "Skip for now"
        default: "Continue"
        }
    }

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        direction = delta > 0 ? .trailing : .leading
        withAnimation(.spring(duration: 0.45, bounce: 0.1)) { step = next }
    }

    private func finish() {
        settings.onboardingCompleted = true
        settings.onboardingStep = 0
        onFinish()
    }
}

// MARK: - Shared pieces

private struct StepTitle: View {
    let eyebrow: String
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 30, weight: .semibold))
                .lineSpacing(2)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatusPill: View {
    enum Kind { case good, waiting, warning, bad }
    let kind: Kind
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            switch kind {
            case .good: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .waiting: ProgressView().controlSize(.small)
            case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .bad: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            }
            Text(text).font(.system(size: 14, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassBackground(in: Capsule())
    }
}

/// A lid angle that opens and closes on its own: open, pause, close, pause, open.
private func demoAngle(at time: TimeInterval) -> Double {
    let open = FoldCurve.fullyOpenAngle, closed = 14.0
    let down = 1.7, holdClosed = 0.7, up = 1.5, holdOpen = 1.4
    let period = down + holdClosed + up + holdOpen
    let t = time.truncatingRemainder(dividingBy: period)
    if t < down { return open - (open - closed) * smoothstep(t / down) }
    if t < down + holdClosed { return closed }
    if t < down + holdClosed + up { return closed + (open - closed) * smoothstep((t - down - holdClosed) / up) }
    return open
}

// MARK: - Steps

private struct WelcomeStep: View {
    var controller: AppController
    private let start = Date()

    var body: some View {
        VStack(spacing: 22) {
            if let graphics = controller.graphics {
                TimelineView(.periodic(from: start, by: 1.0 / 30.0)) { context in
                    MacBookPreviewView(
                        graphics: graphics,
                        lidAngle: demoAngle(at: context.date.timeIntervalSince(start)),
                        parameters: controller.settings.parameters,
                        curve: controller.settings.curve
                    )
                }
                .frame(height: 300)
            }
            VStack(spacing: 10) {
                Text("Your desktop bends as you close the lid.")
                    .font(.system(size: 30, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text("The fluid fold from iPhone Duo, for the lid you already have. As the lid comes down your desktop tilts, blurs and settles. A minute of setup and it just happens.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 520)
            }
        }
    }
}

private struct LidStep: View {
    var controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            StepTitle(eyebrow: "Step 1 of 4", title: "Your lid, measured.",
                      text: "MacBooks since 2019 carry a sensor that reports the hinge angle. Foldy reads it straight from the Mac, with no polling while the lid rests and no accessibility tricks.")
            HStack(alignment: .top, spacing: 28) {
                LidGauge(angle: controller.sensorAvailable ? controller.lidAngle : FoldCurve.fullyOpenAngle,
                         curve: controller.settings.curve, live: controller.sensorAvailable)
                    .frame(width: 300, height: 220)
                VStack(alignment: .leading, spacing: 14) {
                    switch controller.sensorAvailability {
                    case .searching:
                        StatusPill(kind: .waiting, text: "Looking for the sensor…")
                    case .available:
                        StatusPill(kind: .good, text: "Sensor found · \(Int(controller.lidAngle.rounded()))°")
                        Text("Tilt the lid a little. The gauge follows, and the fold begins below \(Int(controller.settings.curve.clearAngle))°.")
                            .foregroundStyle(.secondary)
                    case let .unavailable(reason):
                        StatusPill(kind: .warning, text: "No lid angle sensor")
                        Text(reason).foregroundStyle(.secondary)
                        Text("Foldy still works here: Try It Now in the menu bar folds the desktop on demand, and the preview in Settings lets you drag the angle yourself.")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// A hinge drawn as an arc: the deck flat, the lid at the live angle, the fold zone shaded.
private struct LidGauge: View {
    let angle: Double
    let curve: FoldCurve
    let live: Bool

    var body: some View {
        Canvas { context, size in
            let hinge = CGPoint(x: size.width * 0.32, y: size.height * 0.72)
            let length = min(size.width, size.height) * 0.62
            func point(_ degrees: Double) -> CGPoint {
                let r = degrees * .pi / 180
                return CGPoint(x: hinge.x + cos(r) * length, y: hinge.y - sin(r) * length)
            }
            // The fold zone between the clear angle and the folded angle.
            var zone = Path()
            zone.move(to: hinge)
            zone.addArc(center: hinge, radius: length, startAngle: .degrees(-curve.clearAngle), endAngle: .degrees(-curve.foldedAngle), clockwise: false)
            zone.closeSubpath()
            context.fill(zone, with: .color(.accentColor.opacity(0.12)))
            // Ticks.
            for tick in stride(from: 0.0, through: 180.0, by: 15.0) {
                let inner = CGPoint(x: hinge.x + cos(tick * .pi / 180) * (length - 8), y: hinge.y - sin(tick * .pi / 180) * (length - 8))
                var t = Path(); t.move(to: inner); t.addLine(to: point(tick))
                context.stroke(t, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
            }
            // Deck.
            var deck = Path()
            deck.move(to: hinge)
            deck.addLine(to: CGPoint(x: hinge.x + length, y: hinge.y))
            context.stroke(deck, with: .color(.secondary), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            // Lid.
            var lid = Path()
            lid.move(to: hinge)
            lid.addLine(to: point(angle)) // 0° lies on the deck, 135° leans back
            context.stroke(lid, with: .color(live ? .primary : .secondary), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: hinge.x - 6, y: hinge.y - 6, width: 12, height: 12)), with: .color(.primary))
            // Readout.
            let label = Text("\(Int(angle.rounded()))°").font(.system(size: 26, weight: .semibold).monospacedDigit())
            context.draw(label, at: CGPoint(x: size.width * 0.78, y: size.height * 0.22))
        }
        .animation(.spring(duration: 0.35), value: angle)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.quaternary.opacity(0.4)))
    }
}

private struct CaptureStep: View {
    var controller: AppController
    @State private var timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            StepTitle(eyebrow: "Step 2 of 4", title: "Let Foldy see the screen.",
                      text: "To fold the real desktop Foldy captures the display with ScreenCaptureKit. Frames go straight to the GPU on this Mac; nothing is recorded, saved or sent anywhere. Without it Foldy folds a sample wallpaper instead.")
            VStack(alignment: .leading, spacing: 18) {
                if controller.needsRelaunchForPermission {
                    StatusPill(kind: .good, text: "Screen Recording allowed")
                    Text("macOS hands a new permission to a fresh process only. Relaunch Foldy and the tour continues from the next step.")
                        .foregroundStyle(.secondary)
                    Button {
                        controller.settings.onboardingStep = OnboardingView.Step.style.rawValue
                        controller.relaunch()
                    } label: {
                        Label("Relaunch Foldy", systemImage: "arrow.clockwise")
                    }
                    .glassButtonStyle(.prominent)
                    .controlSize(.large)
                } else if controller.hasScreenPermission {
                    StatusPill(kind: .good, text: "Screen Recording allowed")
                    Text("The live desktop is what will fold.").foregroundStyle(.secondary)
                } else {
                    StatusPill(kind: .bad, text: "Screen Recording not allowed")
                    GlassGroup(spacing: 12) {
                        HStack(spacing: 12) {
                            Button {
                                controller.requestScreenPermission()
                            } label: {
                                Label("Allow Screen Recording", systemImage: "rectangle.dashed.badge.record")
                            }
                            .glassButtonStyle(.prominent)
                            .controlSize(.large)
                            Button("Open System Settings…") { controller.openScreenRecordingSettings() }
                                .glassButtonStyle()
                                .controlSize(.large)
                        }
                    }
                    Text("macOS shows its own dialog once. If it has already been dismissed, switch Foldy on under Privacy & Security › Screen Recording. This page notices as soon as it is allowed.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 14))
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.quaternary.opacity(0.4)))
        }
        .onReceive(timer) { _ in controller.refreshPermission() }
    }
}

private struct StyleStep: View {
    var controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepTitle(eyebrow: "Step 3 of 4", title: "Pick a fold.",
                      text: "Three looks, all tunable later in Settings. Try It Now runs the fold once on the real display, down and back up.")
            HStack(spacing: 16) {
                ForEach(FoldStyle.allCases) { style in
                    StyleCard(controller: controller, style: style, selected: controller.settings.style == style) {
                        controller.settings.style = style
                        controller.evaluate()
                    }
                }
            }
            HStack(spacing: 14) {
                Button {
                    controller.sweep()
                } label: {
                    Label(controller.isSweeping ? "Folding…" : "Try It Now", systemImage: "play.fill")
                }
                .glassButtonStyle(.prominent)
                .controlSize(.large)
                .disabled(controller.isSweeping || controller.isPaused)
                Text(controller.usesSampleWallpaper
                     ? "Screen Recording is not active in this process, so this shows the sample wallpaper."
                     : "Watch the whole screen.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Text(controller.settings.style.summary)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }
}

private struct DoneStep: View {
    var controller: AppController
    @State private var launchAtLogin = false
    @State private var launchError: String?

    var body: some View {
        @Bindable var settings = controller.settings
        VStack(alignment: .leading, spacing: 26) {
            StepTitle(eyebrow: "Step 4 of 4", title: "That's it. Foldy lives in the menu bar.",
                      text: "Close the lid and the desktop folds; open it and the desktop clears with a soft click. Click the fold or press Esc to wave it off until the lid opens again.")
            HStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "laptopcomputer").font(.system(size: 15, weight: .medium))
                    Text("Pause · Try It Now · Settings…").font(.system(size: 13))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassBackground(in: Capsule())
                Text("the menu bar icon").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            SettingsCard {
                SettingsRow(title: "Launch at login") {
                    Toggle("", isOn: $launchAtLogin).labelsHidden().toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { _, enabled in
                            guard enabled != settings.launchAtLogin else { return }
                            do { try settings.setLaunchAtLogin(enabled); launchError = nil }
                            catch { launchError = error.localizedDescription; launchAtLogin = settings.launchAtLogin }
                        }
                }
                if let launchError {
                    Text(launchError).font(.system(size: 12)).foregroundStyle(.red).padding(.horizontal, 16).padding(.bottom, 10)
                }
                RowDivider()
                SettingsRow(title: "Sound", subtitle: "A soft click when the lid opens and the desktop clears.") {
                    Toggle("", isOn: $settings.soundEnabled).labelsHidden().toggleStyle(.switch)
                }
            }
        }
        .onAppear { launchAtLogin = settings.launchAtLogin }
    }
}
