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

    @ObservationIgnored private let sensor = LidAngleSensor()
    @ObservationIgnored private let capture = DisplayCapture()
    @ObservationIgnored private let sound = FoldSound()
    @ObservationIgnored private var overlay: OverlayWindowController?
    @ObservationIgnored private var sweepTimer: Timer?
    @ObservationIgnored private var sweepStart: Date?
    @ObservationIgnored private var soundArmed = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// The hinge angle from the sensor, degrees.
    private(set) var lidAngle: Double = FoldCurve.fullyOpenAngle
    private(set) var sensorAvailability: LidAngleSensor.Availability = .searching
    private(set) var captureState: DisplayCapture.State = .idle
    private(set) var hasScreenPermission = DisplayCapture.hasPermission()
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
        settings.sampleWallpaper || !hasScreenPermission
    }

    var statusLine: String {
        if let graphicsError { return "Metal unavailable: \(graphicsError)" }
        if isPaused { return "Paused" }
        switch sensorAvailability {
        case .searching: return "Looking for the lid sensor…"
        case let .unavailable(reason): return reason
        case .available:
            if case let .failed(message) = captureState { return "Capture failed: \(message)" }
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
            }
        }

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppController.shared.systemWillSleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppController.shared.evaluate() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppController.shared.overlay?.screenChanged() }
        })

        sensor.start()
        evaluate()
    }

    func stop() {
        sweepTimer?.invalidate()
        overlay?.hideNow()
        capture.stop()
        sensor.stop()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    // MARK: Actions

    func togglePause() {
        isPaused.toggle()
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
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            MainActor.assumeIsolated { AppController.shared.advanceSweep() }
        }
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
        hasScreenPermission = DisplayCapture.hasPermission()
        evaluate()
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

    /// Opens Settings from AppKit code. The menu uses `SettingsLink`; this is for the
    /// command-line switches, where the SwiftUI scene may not answer, so it falls back
    /// to hosting the same view in a window of its own.
    func openSettings(hosted: Bool = false, pane: SettingsView.Pane = .appearance) {
        NSApp.activate()
        if !hosted {
            for name in ["showSettingsWindow:", "showPreferencesWindow:"] where NSApp.sendAction(Selector(name), to: nil, from: nil) {
                return
            }
        }
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: SettingsView(controller: self, initialPane: pane))
        let window = NSWindow(contentViewController: host)
        window.title = "Foldy Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    // MARK: Decisions

    /// Re-reads every input and makes the overlay, the capture and the sound match.
    func evaluate() {
        let curve = settings.curve
        let angle = effectiveAngle
        if isDismissed, angle >= curve.clearAngle { isDismissed = false }

        let progress = curve.progress(forAngle: angle)
        let wantsFold = !isPaused && !isDismissed && progress > 0
        let nearFold = angle < curve.clearAngle + 15
        let wantsCapture = !isPaused && !usesSampleWallpaper && (nearFold || wantsFold)

        updateCapture(wanted: wantsCapture, farFromFold: angle > curve.clearAngle + 25)
        updateOverlay(wantsFold: wantsFold, progress: progress)
        updateSound(progress: progress)
    }

    private func updateCapture(wanted: Bool, farFromFold: Bool) {
        switch (wanted, captureState) {
        case (true, .idle), (true, .failed):
            guard hasScreenPermission else { return }
            capture.start(displayID: OverlayWindowController.targetDisplayID())
        case (false, .running), (false, .starting):
            if farFromFold || isPaused || usesSampleWallpaper {
                capture.stop()
                overlay?.renderer.clearSource()
            }
        default:
            break
        }
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
        overlay?.renderer.clearSource()
    }
}
