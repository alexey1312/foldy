import AppKit

extension NSWindow {
    /// Opens a window of a menu bar app in front of everything, in the middle of the
    /// screen the user is on.
    ///
    /// Foldy is an accessory app (LSUIElement): it has no Dock tile and macOS may refuse
    /// its activation request, so `NSApp.activate()` followed by `makeKeyAndOrderFront` —
    /// what this used to do — still left the window behind whatever the user was looking
    /// at. Coming up at the floating level and dropping back on the next main-actor hop
    /// puts it in front of other apps without leaving it hovering there for good;
    /// `orderFrontRegardless` is the part that works while the app is inactive.
    /// `.moveToActiveSpace` is a permanent change, unlike `level`: the window follows the
    /// user between Spaces from here on, which is what you want for a menu bar app's one
    /// window. A window already on screen only comes forward — re-centring one the user
    /// has placed, or one on its way out of the Dock, would yank it out from under them.
    func presentFront() {
        if !isVisible, !isMiniaturized { centerOnActiveScreen() }
        collectionBehavior.insert(.moveToActiveSpace)
        NSApp.activate()
        level = .floating
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        Task { @MainActor in self.level = .normal }
    }

    /// Centres the window on the screen holding the pointer, rather than on whichever
    /// screen AppKit thinks is main. With the pointer over no screen at all it falls back
    /// to `NSScreen.main`. The clamp is not decorative: `--window-height` can ask for a
    /// window taller than the visible frame, and a window is pinned inside it rather than
    /// centred when that happens. It centres the size the window has now, so give a window
    /// made around a SwiftUI view its content size first: the view may not be measured yet,
    /// and a zero-size window centred and then grown hangs off the bottom right.
    func centerOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let size = frame.size
        let x = min(max(visible.midX - size.width / 2, visible.minX), max(visible.maxX - size.width, visible.minX))
        let y = min(max(visible.midY - size.height / 2, visible.minY), max(visible.maxY - size.height, visible.minY))
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// Lets go of a window when the user closes it.
///
/// Both of Foldy's windows are `isReleasedWhenClosed = false` and were held in a stored
/// property forever, so closing Settings left its whole SwiftUI tree alive — including a
/// Metal preview whose body is invalidated at the lid sensor's report rate, competing
/// with the fold's own 60 Hz pass for the rest of the session.
@MainActor
final class WindowCloser: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
