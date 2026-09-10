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

    init(graphics: FoldGraphics) throws {
        renderer = try FoldRenderer(graphics: graphics)
        renderer.smoothing = 0.12
        renderer.cornerRadius = 0.02

        let screen = Self.targetScreen()
        window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
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

        view = OverlayMetalView(frame: NSRect(origin: .zero, size: screen.frame.size), device: graphics.device)
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

    static func targetScreen() -> NSScreen {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(number) != 0
        } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    static func targetDisplayID() -> CGDirectDisplayID {
        (targetScreen().deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
    }

    func screenChanged() {
        window.setFrame(Self.targetScreen().frame, display: true)
    }

    /// The window is normally invisible to screen capture (`sharingType = .none`), so it
    /// never captures itself. The `--screenshot-fold` switch lifts that to take a picture.
    func setCapturable(_ capturable: Bool) {
        window.sharingType = capturable ? .readOnly : .none
    }

    // MARK: Source

    func useSampleWallpaper() {
        let screen = Self.targetScreen()
        let scale = screen.backingScaleFactor
        let width = Int(screen.frame.width * scale), height = Int(screen.frame.height * scale)
        guard let image = WallpaperArt.image(width: width, height: height), (try? renderer.setSource(cgImage: image)) != nil else { return }
        hasSampleSource = true
    }

    // MARK: Show and hide

    func show() {
        hiding = false
        guard !isShown else { return }
        isShown = true
        window.setFrame(Self.targetScreen().frame, display: false)
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
    func hideWhenSettled() {
        guard isShown else { return }
        hiding = true
    }

    func hideNow() {
        hiding = false
        guard isShown else { return }
        isShown = false
        view.isPaused = true
        window.orderOut(nil)
        hasSampleSource = false
        if let previousApp, previousApp != NSRunningApplication.current {
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
