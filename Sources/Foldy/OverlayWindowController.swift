import AppKit
import FoldyCore
import MetalKit

/// The full-screen window that shows the folded desktop over everything else.
@MainActor
final class OverlayWindowController {
    let renderer: FoldRenderer
    var onDismiss: (() -> Void)?
    private(set) var isShown = false
    private(set) var hasSampleSource = false

    private let window: OverlayWindow
    private let view: OverlayMetalView
    private var hiding = false
    private var previousApp: NSRunningApplication?
    private var hideWatchdog: DispatchWorkItem?

    init(graphics: FoldGraphics) throws {
        renderer = try FoldRenderer(graphics: graphics)
        renderer.smoothing = 0.12
        renderer.cornerRadius = 0.02

        let frame = Self.targetScreen()?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window = OverlayWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Left out of every screen capture, so the desktop underneath is what gets folded.
        window.sharingType = .none

        view = OverlayMetalView(frame: NSRect(origin: .zero, size: frame.size), device: graphics.device)
        view.renderer = renderer
        view.commandQueue = graphics.commandQueue
        view.colorPixelFormat = FoldGraphics.pixelFormat
        view.preferredFramesPerSecond = 60
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.autoresizingMask = [.width, .height]
        window.contentView = view

        view.onDismiss = { [weak self] in self?.onDismiss?() }
        view.onFrame = { [weak self] progress in self?.frameDrawn(progress: progress) }
    }

    // MARK: Screens

    /// The built-in display, or the best stand-in. `nil` while every display is asleep
    /// or the last one has just been unplugged — `NSScreen.screens` really is empty then,
    /// and this is called straight from the notification that says so.
    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(number) != 0
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    static func targetDisplayID() -> CGDirectDisplayID {
        (targetScreen()?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
    }

    func screenChanged() {
        guard let screen = Self.targetScreen() else { return }
        window.setFrame(screen.frame, display: true)
    }

    /// The window is normally invisible to screen capture (`sharingType = .none`), so it
    /// never captures itself. The `--screenshot-fold` switch lifts that to take a picture.
    func setCapturable(_ capturable: Bool) {
        window.sharingType = capturable ? .readOnly : .none
    }

    // MARK: Source

    /// Drops whatever the sheet shows; the next show waits for a fresh frame or wallpaper.
    func clearSource() {
        renderer.clearSource()
        hasSampleSource = false
    }

    func useSampleWallpaper() {
        let frame = Self.targetScreen()?.frame ?? window.frame
        let scale = Self.targetScreen()?.backingScaleFactor ?? 2
        let width = Int(frame.width * scale), height = Int(frame.height * scale)
        // Marked before the attempt: drawing the wallpaper costs a full-screen CoreGraphics
        // pass, and evaluate() comes back up to 60 times a second while the lid moves.
        hasSampleSource = true
        guard let image = WallpaperArt.image(width: width, height: height) else {
            FoldyLog.graphics.error("sample wallpaper could not be drawn")
            return
        }
        do {
            try renderer.setSource(cgImage: image)
        } catch {
            FoldyLog.graphics.error("sample wallpaper would not upload: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Show and hide

    func show() {
        hiding = false
        hideWatchdog?.cancel()
        hideWatchdog = nil
        guard !isShown else { return }
        isShown = true
        if let screen = Self.targetScreen() { window.setFrame(screen.frame, display: false) }
        window.alphaValue = 0
        view.isPaused = false
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            window.animator().alphaValue = 1
        }
    }

    /// Lets the fold ease back to flat, then takes the window down.
    ///
    /// The teardown rides on drawn frames, and `draw` returns early when there is no
    /// drawable — a sleeping or disconnected display. The watchdog is what stops a
    /// full-screen window at `.screenSaver` level from staying up over everything when
    /// the frames never come.
    func hideWhenSettled() {
        guard isShown, !hiding else { return }
        hiding = true
        hideWatchdog?.cancel()
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self, hiding else { return }
            FoldyLog.app.notice("fold did not settle; hiding the overlay anyway")
            hideNow()
        }
        hideWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: watchdog)
    }

    func hideNow() {
        hiding = false
        hideWatchdog?.cancel()
        hideWatchdog = nil
        guard isShown else { return }
        isShown = false
        view.isPaused = true
        window.orderOut(nil)
        // Only give the focus back if Foldy still has it. The user may have Cmd-Tabbed
        // away while the fold was up, and yanking them back to the app that happened to
        // be frontmost when the lid moved is worse than doing nothing.
        if NSApp.isActive, let previousApp, previousApp != NSRunningApplication.current {
            previousApp.activate()
        }
        previousApp = nil
    }

    private func frameDrawn(progress: Double) {
        if hiding, progress < 0.004 {
            hideNow()
        }
    }
}

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class OverlayMetalView: MTKView {
    var renderer: FoldRenderer?
    var commandQueue: MTLCommandQueue?
    var onDismiss: (() -> Void)?
    var onFrame: ((Double) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        onDismiss?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onDismiss?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let renderer, let commandQueue, let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        renderer.step()
        renderer.encode(into: commandBuffer, target: drawable.texture, clearColor: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1))
        commandBuffer.present(drawable)
        commandBuffer.commit()
        onFrame?(renderer.progress)
    }
}
