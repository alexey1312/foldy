import AppKit
import FoldyCore
import Observation
import SwiftUI

/// Ties the sensor, the capture and the overlay together, and decides what shows when.
@MainActor
@Observable
final class AppController {
    static let shared = AppController()

    let settings = SettingsStore()
    let graphics: FoldGraphics?
    let graphicsError: String?
    /// The overlay could not be built. Without this the fold simply never appeared and
    /// the status line cheerfully reported the lid angle.
    private(set) var overlayError: String?
    /// Sparkle. Dormant in screenshot runs and outside an app bundle.
    let updater = Updater(enabled: !DevFlags.isScreenshotRun)

    @ObservationIgnored private let sensor = LidAngleSensor()
    @ObservationIgnored private let capture = DisplayCapture()
    @ObservationIgnored private let sound = FoldSound()
    @ObservationIgnored private var overlay: OverlayWindowController?
    @ObservationIgnored private var sweepTimer: Timer?
    @ObservationIgnored private var sweepStart: Date?
    @ObservationIgnored private var soundArmed = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var lastCaptureFailure: Date?
    @ObservationIgnored private var captureIdleTimer: DispatchWorkItem?
    /// Every capture and overlay decision, in one testable place. See `CapturePolicy`.
    @ObservationIgnored private var policy = CapturePolicy()
    /// Re-evaluates after a capture failure, since a still lid reports no angles and
    /// would otherwise never call `evaluate()` again to retry.
    @ObservationIgnored private var captureRetryTimer: DispatchWorkItem?
    /// Development only (`--screenshot-fold`): never persisted, unlike the setting.
    @ObservationIgnored var forcesSampleWallpaper = false
    private static let captureRetryDelay: TimeInterval = 5
    /// How long the desktop may sit flat with nothing folded before the capture is
    /// stopped. It stays stopped until the lid closes `CapturePolicy.wakeDegrees` below
    /// where it came to rest, or the fold is wanted.
    private static let captureIdleTimeout: TimeInterval = 4

    /// The hinge angle from the sensor, degrees.
    private(set) var lidAngle: Double = FoldCurve.fullyOpenAngle
    private(set) var sensorAvailability: LidAngleSensor.Availability = .searching
    private(set) var captureState: DisplayCapture.State = .idle
    private(set) var hasScreenPermission = DisplayCapture.hasPermission()
    /// Screen Recording was granted while Foldy was running; macOS applies it to a
    /// fresh process, so the live desktop needs a relaunch.
    private(set) var needsRelaunchForPermission = false
    @ObservationIgnored private var lastPermissionCheck = Date.distantPast
    @ObservationIgnored private let onboarding = OnboardingWindowController()
    /// Set from the menu. Nothing folds until resumed.
    private(set) var isPaused = false
    /// Set by a click or Esc on the fold. Clears once the lid opens past the clear angle.
    private(set) var isDismissed = false
    /// "Try it" is sweeping the lid angle down and back up.
    private(set) var isSweeping = false
    private var sweepAngle: Double = FoldCurve.fullyOpenAngle

    private init() {
        do {
            graphics = try FoldGraphics()
            graphicsError = nil
        } catch {
            graphics = nil
            graphicsError = error.localizedDescription
        }
    }

    var sensorAvailable: Bool { sensorAvailability.isAvailable }

    /// The angle the fold follows: the sweep while it runs, else the sensor.
    var effectiveAngle: Double {
        if isSweeping { return sweepAngle }
        return sensorAvailable ? lidAngle : FoldCurve.fullyOpenAngle
    }

    /// What the settings preview should show when it follows the lid.
    var previewAngle: Double {
        if isSweeping { return sweepAngle }
        if settings.previewFollowsLid, sensorAvailable { return lidAngle }
        return settings.previewAngle
    }

    var usesSampleWallpaper: Bool {
        forcesSampleWallpaper || settings.sampleWallpaper || !hasScreenPermission || needsRelaunchForPermission
    }

    var statusLine: String {
        if let graphicsError { return "Metal unavailable: \(graphicsError)" }
        if let overlayError { return "The fold can't be drawn: \(overlayError)" }
        if case let .failed(message) = captureState { return "Capture failed: \(message)" }
        if isPaused { return "Paused" }
        switch sensorAvailability {
        case .searching: return "Looking for the lid sensor…"
        case let .unavailable(reason): return reason
        case .available:
            if needsRelaunchForPermission { return "Screen Recording allowed · relaunch Foldy to use it" }
            if !hasScreenPermission, !settings.sampleWallpaper { return "Lid at \(Int(lidAngle.rounded()))° · Screen Recording needed" }
            return "Lid at \(Int(lidAngle.rounded()))°"
        }
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true

        sensor.onAngle = { angle in
            Task { @MainActor in
                AppController.shared.lidAngle = angle
                AppController.shared.evaluate()
            }
        }
        sensor.onAvailability = { availability in
            Task { @MainActor in
                AppController.shared.sensorAvailability = availability
                AppController.shared.evaluate()
            }
        }
        capture.onState = { state in
            Task { @MainActor in
                AppController.shared.captureState = state
                if state.isFailure { AppController.shared.lastCaptureFailure = Date() }
                AppController.shared.evaluate()
            }
        }

        if let graphics {
            do {
                let overlay = try OverlayWindowController(graphics: graphics)
                overlay.onDismiss = { [weak self] in self?.dismissFold() }
                self.overlay = overlay
                let renderer = overlay.renderer
                capture.onFrame = { pixelBuffer in
                    let first = !renderer.hasSource
                    renderer.setSource(pixelBuffer: pixelBuffer)
                    if first {
                        Task { @MainActor in AppController.shared.evaluate() }
                    }
                }
            } catch {
                overlay = nil
                overlayError = error.localizedDescription
                FoldyLog.app.error("overlay unavailable: \(error.localizedDescription, privacy: .public)")
            }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        let center = NotificationCenter.default
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppController.shared.systemWillSleep() }
        }))
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppController.shared.evaluate() }
        }))
        observers.append((center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppController.shared.screenChanged() }
        }))
        observers.append((center, center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppController.shared.refreshPermission() }
        }))

        sensor.start()
        evaluate()
        if !settings.onboardingCompleted, !DevFlags.isScreenshotRun {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.showOnboarding() }
        }
    }

    /// The welcome tour. Resumes at the saved step, so a relaunch for Screen
    /// Recording lands on the step after it.
    func showOnboarding(step: Int? = nil) {
        onboarding.show(controller: self, step: step)
    }

    func stop() {
        sweepTimer?.invalidate()
        sweepTimer = nil
        sweepStart = nil
        isSweeping = false
        captureIdleTimer?.cancel()
        captureIdleTimer = nil
        captureRetryTimer?.cancel()
        captureRetryTimer = nil
        overlay?.hideNow()
        capture.stop()
        sensor.stop()
        settings.flush()
        for (center, observer) in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        started = false
    }

    // MARK: Actions

    func togglePause() {
        isPaused.toggle()
        policy.unpark()
        evaluate()
    }

    func dismissFold() {
        isDismissed = true
        evaluate()
    }

    /// Runs the fold once on the real desktop: down over 1.6 s, a beat, then back up.
    func sweep() {
        guard !isSweeping else { return }
        isSweeping = true
        isDismissed = false
        sweepStart = Date()
        sweepAngle = FoldCurve.fullyOpenAngle
        sweepTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
            MainActor.assumeIsolated { AppController.shared.advanceSweep() }
        }
        // .default alone freezes the sweep mid-fold for the whole of a menu or a scroll.
        RunLoop.main.add(timer, forMode: .common)
        sweepTimer = timer
        evaluate()
    }

    private func advanceSweep() {
        guard let sweepStart else { return }
        let t = Date().timeIntervalSince(sweepStart)
        let down = 1.6, hold = 0.7, up = 1.4
        let open = FoldCurve.fullyOpenAngle
        let closed = max(settings.curve.foldedAngle - 6, 0)
        if t < down {
            sweepAngle = open - (open - closed) * smoothstep(t / down)
        } else if t < down + hold {
            sweepAngle = closed
        } else if t < down + hold + up {
            sweepAngle = closed + (open - closed) * smoothstep((t - down - hold) / up)
        } else {
            sweepTimer?.invalidate()
            sweepTimer = nil
            isSweeping = false
            sweepAngle = open
        }
        evaluate()
    }

    /// Development only: lets screen capture see the overlay. See `DevFlags`.
    func setOverlayCapturable(_ capturable: Bool) {
        overlay?.setCapturable(capturable)
    }

    func refreshPermission() {
        lastPermissionCheck = Date()
        let granted = DisplayCapture.hasPermission()
        if granted, !hasScreenPermission {
            // Granted since launch. The capture would still be refused in this process.
            needsRelaunchForPermission = true
        }
        if !granted {
            // Taken away again: stop claiming a relaunch would help, and let the menu
            // offer the button that fixes it.
            needsRelaunchForPermission = false
        }
        hasScreenPermission = granted
        evaluate()
    }

    /// Why the last relaunch attempt did not happen. Shown in the menu.
    private(set) var relaunchError: String?

    /// Starts a fresh copy of the app and quits this one.
    func relaunch() {
        relaunchError = nil
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                guard error == nil else {
                    // Quitting now would leave the user with no Foldy at all, on the one
                    // button the Screen Recording flow depends on.
                    AppController.shared.relaunchError = error?.localizedDescription
                    FoldyLog.app.error("relaunch failed: \(error?.localizedDescription ?? "", privacy: .public)")
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }

    func requestScreenPermission() {
        DisplayCapture.requestPermission()
        refreshPermission()
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @ObservationIgnored private var settingsWindow: NSWindow?
    @ObservationIgnored private var settingsCloser: WindowCloser?

    /// Foldy's own Settings window, rather than SwiftUI's `Settings` scene.
    ///
    /// The scene came with chrome we could not reach: an empty toolbar band and the
    /// split view's automatic sidebar toggle, which landed in the middle of the sidebar
    /// instead of beside the traffic lights. It also never opened for a process started
    /// from a shell, so the `--screenshot-settings` switch saw a different window from
    /// the one users get. One window, made here, fixes both.
    func openSettings(pane: SettingsView.Pane = .appearance, height: Double? = nil) {
        if let settingsWindow {
            settingsWindow.presentFront()
            return
        }
        let host = NSHostingController(rootView: SettingsView(controller: self, initialPane: pane).screenshotControlState())
        let window = NSWindow(contentViewController: host)
        window.title = "Foldy Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        // No toolbar: the titlebar is a bare drag strip with the window title, and the
        // sidebar's material runs up behind the traffic lights.
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        // Sized here rather than left to SwiftUI, which can hand over its view before it
        // has measured it. `presentFront` centred that zero-size window, and SwiftUI then
        // grew it down and to the right from the middle of the screen, half off the edge.
        // Screenshot runs never saw it: they always passed a height.
        window.setContentSize(NSSize(width: SettingsView.idealSize.width, height: height ?? SettingsView.idealSize.height))
        window.presentFront()
        let closer = WindowCloser { [weak self] in self?.settingsWindow = nil }
        window.delegate = closer
        settingsCloser = closer
        settingsWindow = window
    }

    // MARK: Decisions

    /// Re-reads every input and makes the overlay, the capture and the sound match.
    func evaluate() {
        // The switch in System Settings can move either way while Foldy runs, and an
        // .accessory app is not activated by its own menu, so this is the only place a
        // revocation is ever noticed.
        if Date().timeIntervalSince(lastPermissionCheck) > 3 {
            lastPermissionCheck = Date()
            let granted = DisplayCapture.hasPermission()
            if granted, !hasScreenPermission { needsRelaunchForPermission = true }
            if !granted { needsRelaunchForPermission = false }
            hasScreenPermission = granted
        }
        let decision = policy.decide(CapturePolicy.Input(
            angle: effectiveAngle,
            curve: settings.curve,
            isPaused: isPaused,
            isDismissed: isDismissed,
            isSweeping: isSweeping,
            overlayShown: overlay?.isShown == true,
            usesSampleWallpaper: usesSampleWallpaper
        ))
        if decision.clearsDismissal { isDismissed = false }

        updateCapture(decision)
        updateOverlay(wantsFold: decision.wantsFold, progress: decision.progress)
        updateSound(progress: decision.progress)
    }

    private func updateCapture(_ decision: CapturePolicy.Decision) {
        let wanted = decision.wantsCapture
        let farFromFold = decision.farFromFold
        // A lid resting anywhere above the fold would otherwise stream the display for
        // hours with nothing on screen — and between the band and `farFromFold` nothing
        // else ever stops it, since a still lid reports no angles. Stop after a quiet
        // spell; the policy's parked angle, not the next movement, decides when it returns.
        if decision.isIdle, captureState == .running {
            if captureIdleTimer == nil {
                let timer = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    captureIdleTimer = nil
                    guard captureState == .running, overlay?.isShown != true else { return }
                    policy.park(at: effectiveAngle)
                    capture.stop()
                    overlay?.clearSource()
                }
                captureIdleTimer = timer
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.captureIdleTimeout, execute: timer)
            }
        } else {
            captureIdleTimer?.cancel()
            captureIdleTimer = nil
        }

        switch (wanted, captureState) {
        case (true, .idle):
            // Lighting the screen recording indicator for a fold that cannot be drawn is
            // indefensible.
            guard hasScreenPermission, overlay != nil else { return }
            capture.start(displayID: OverlayWindowController.targetDisplayID())
        case (true, .failed):
            // Every lid movement calls evaluate(); a broken capture must not be restarted
            // at 60 Hz. A still lid reports nothing at all, so the wait needs its own timer
            // — otherwise the retry only ever happens if some other event comes along.
            guard hasScreenPermission, overlay != nil else { return }
            if let last = lastCaptureFailure, Date().timeIntervalSince(last) <= Self.captureRetryDelay {
                scheduleCaptureRetry(after: Self.captureRetryDelay - Date().timeIntervalSince(last))
                return
            }
            capture.start(displayID: OverlayWindowController.targetDisplayID())
        case (false, .running), (false, .starting):
            if farFromFold || isPaused || usesSampleWallpaper {
                capture.stop()
                overlay?.clearSource()
            }
        default:
            break
        }
    }

    private func scheduleCaptureRetry(after delay: TimeInterval) {
        guard captureRetryTimer == nil else { return }
        let timer = DispatchWorkItem { [weak self] in
            guard let self else { return }
            captureRetryTimer = nil
            evaluate()
        }
        captureRetryTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + max(delay, 0.1), execute: timer)
    }

    private func updateOverlay(wantsFold: Bool, progress: Double) {
        guard let overlay else { return }
        overlay.renderer.parameters = settings.parameters
        if wantsFold {
            overlay.renderer.targetProgress = progress
            if usesSampleWallpaper, !overlay.hasSampleSource {
                overlay.useSampleWallpaper()
            }
            if overlay.renderer.hasSource {
                overlay.show()
            }
        } else {
            overlay.renderer.targetProgress = 0
            overlay.hideWhenSettled()
        }
    }

    private func updateSound(progress: Double) {
        if progress > 0.8 {
            soundArmed = true
        } else if soundArmed, progress < 0.05 {
            soundArmed = false
            if settings.soundEnabled, !isPaused { sound.click() }
        }
    }

    private func systemWillSleep() {
        overlay?.hideNow()
        capture.stop()
        overlay?.clearSource()
        policy.unpark()
    }

    /// The stream's size is fixed at start, so a resolution or display change needs a
    /// fresh one; the next evaluate() restarts it if the lid is still near the fold.
    private func screenChanged() {
        overlay?.screenChanged()
        capture.stop()
        overlay?.clearSource()
        policy.unpark()
        evaluate()
    }
}
