import FoldyCore
import SwiftUI

@main
struct FoldyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(controller: AppController.shared)
        } label: {
            MenuBarLabel(controller: AppController.shared)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, no app menu: Foldy lives in the menu bar. The bundle also says
        // LSUIElement, this covers running the bare binary from `swift run`.
        NSApp.setActivationPolicy(.accessory)
        AppController.shared.start()
        DevFlags.apply()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppController.shared.stop()
    }
}


extension View {
    /// Pins SwiftUI's control state to "key" for a screenshot run.
    ///
    /// A process started from a shell that is not itself frontmost cannot bring the app
    /// to the front, so the captured window is always inactive — and an inactive window
    /// draws glass, switches and buttons dimmed. The doc images should show what a user
    /// sees, not what a background window looks like.
    @ViewBuilder
    func screenshotControlState() -> some View {
        if DevFlags.isScreenshotRun {
            environment(\.controlActiveState, .key)
        } else {
            self
        }
    }
}

/// Command-line switches for development. None of them are needed to use the app.
///
///   --settings [--pane general|appearance|about] [--window-height N]   open Settings at launch
///   --screenshot-settings <png> [--scroll N]   open Settings, capture the window, quit
///   --screenshot-fold <png>          fold the sample wallpaper, capture the overlay, quit
///   --onboarding                     open the welcome tour at launch
///   --screenshot-onboarding <png> [--step N]   open the tour at a step, capture, quit
///   --appearance dark|light          override the system appearance, for the doc images
///
/// Capturing our own windows needs no Screen Recording permission, so this works on a
/// fresh machine and on a Mac without a lid.
@MainActor
enum DevFlags {
    /// True when the process exists only to take a picture and quit.
    static var isScreenshotRun: Bool {
        CommandLine.arguments.contains { $0.hasPrefix("--screenshot-") }
    }

    static func apply() {
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
            return args[index + 1]
        }
        // The committed images are dark; this Mac need not be.
        switch value(after: "--appearance") {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        if args.contains("--settings") || value(after: "--screenshot-settings") != nil {
            let pane = value(after: "--pane").flatMap(SettingsView.Pane.init(rawValue:)) ?? .appearance
            let height = value(after: "--window-height").flatMap(Double.init)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                AppController.shared.openSettings(pane: pane, height: height)
            }
        }
        if let path = value(after: "--screenshot-settings") {
            let scroll = value(after: "--scroll").flatMap(Double.init) ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                let window = NSApp.windows.first { $0.isVisible && $0.title == "Foldy Settings" }
                if scroll > 0, let scrollView = window?.contentView.flatMap(firstScrollView) {
                    scrollView.contentView.scroll(to: NSPoint(x: 0, y: scroll))
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    capture(window, to: path)
                    NSApp.terminate(nil)
                }
            }
        }
        if args.contains("--onboarding") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { AppController.shared.showOnboarding(step: 0) }
        }
        if let path = value(after: "--screenshot-onboarding") {
            let step = value(after: "--step").flatMap(Int.init) ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { AppController.shared.showOnboarding(step: step) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                let window = NSApp.windows.first { $0.isVisible && $0.title == OnboardingWindowController.windowTitle }
                capture(window, to: path)
                NSApp.terminate(nil)
            }
        }
        if let path = value(after: "--screenshot-fold") {
            let controller = AppController.shared
            controller.forcesSampleWallpaper = true
            controller.setOverlayCapturable(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                controller.sweep()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                let window = NSApp.windows.first { $0 is OverlayWindow && $0.isVisible }
                capture(window, to: path)
                NSApp.terminate(nil)
            }
        }
    }

    private static func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for child in view.subviews {
            if let found = firstScrollView(in: child) { return found }
        }
        return nil
    }

    private static func capture(_ window: NSWindow?, to path: String) {
        guard let window else {
            let list = NSApp.windows.map { "\($0.className) title=\"\($0.title)\" visible=\($0.isVisible) mask=\($0.styleMask.rawValue)" }
            FileHandle.standardError.write("no window to capture; windows: \(list)\n".data(using: .utf8)!)
            return
        }
        let id = CGWindowID(window.windowNumber)
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution]) else {
            FileHandle.standardError.write("capture failed\n".data(using: .utf8)!)
            return
        }
        do {
            try FoldyCore.ImageExport.writePNG(image, to: URL(fileURLWithPath: path))
            print("wrote \(path) (\(image.width)×\(image.height))")
        } catch {
            FileHandle.standardError.write("\(error)\n".data(using: .utf8)!)
        }
    }
}
