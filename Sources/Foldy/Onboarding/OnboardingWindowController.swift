import AppKit
import SwiftUI

/// The welcome tour: one window, five steps, shown on the first launch and on demand.
@MainActor
final class OnboardingWindowController {
    static let windowTitle = "Welcome to Foldy"
    private var window: NSWindow?

    func show(controller: AppController, step: Int? = nil) {
        NSApp.activate()
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = OnboardingView(controller: controller, initialStep: step ?? controller.settings.onboardingStep) { [weak self] in
            self?.close()
        }
        let host = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: host)
        window.title = Self.windowTitle
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: OnboardingView.width, height: OnboardingView.height))
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}
