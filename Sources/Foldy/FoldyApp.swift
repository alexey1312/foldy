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

        Settings {
            SettingsView(controller: AppController.shared)
        }
        .windowResizability(.contentSize)
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


/// Command-line switches for development. None of them are needed to use the app.
///
///   --settings [--pane general|appearance|about] [--window-height N]   open Settings at launch
///   --screenshot-settings <png>      open Settings, capture the window, quit
///   --screenshot-fold <png>          fold the sample wallpaper, capture the overlay, quit
///
/// Capturing our own windows needs no Screen Recording permission, so this works on a
/// fresh machine and on a Mac without a lid.
@MainActor
enum DevFlags {
    static func apply() {
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
            return args[index + 1]
        }
        if args.contains("--settings") || value(after: "--screenshot-settings") != nil {
            // SwiftUI wires the Settings scene into the responder chain just after launch.
            // The SwiftUI Settings scene claims the selector but shows nothing when the
            // process is started from a shell, so host the same view in a plain window.
            let pane = value(after: "--pane").flatMap(SettingsView.Pane.init(rawValue:)) ?? .appearance
            let height = value(after: "--window-height").flatMap(Double.init)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                AppController.shared.openSettings(hosted: true, pane: pane, height: height)
            }
        }
        if let path = value(after: "--screenshot-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                let window = NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) }
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
