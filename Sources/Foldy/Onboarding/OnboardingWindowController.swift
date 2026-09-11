import AppKit
import SwiftUI

/// The welcome tour: one window, five steps, shown on the first launch and on demand.
@MainActor
final class OnboardingWindowController {
    static let windowTitle = "Welcome to Foldy"
    private var window: NSWindow?
    private var closer: WindowCloser?

    func show(controller: AppController, step: Int? = nil) {
        if let window {
            // A requested step has to win: the view reads `initialStep` once, at build
            // time, so "Welcome Tour…" on a window left open at step 3 showed step 3.
            guard step != nil else {
                window.presentFront()
                return
            }
            close()
        }
        let view = OnboardingView(controller: controller, initialStep: step ?? controller.settings.onboardingStep) { [weak self] in
            self?.close()
        }
        let host = NSHostingController(rootView: view.screenshotControlState())
        let window = NSWindow(contentViewController: host)
        window.title = Self.windowTitle
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: OnboardingView.width, height: OnboardingView.height))
        window.presentFront()
        // The red button is a way out too; without this the window, its timer and its
        // previews stayed alive for the rest of the session.
        let closer = WindowCloser { [weak self] in self?.window = nil }
        window.delegate = closer
        self.closer = closer
        self.window = window
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}
