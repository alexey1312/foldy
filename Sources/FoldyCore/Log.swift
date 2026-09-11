import Foundation
import os

/// Where the app's errors go when there is no one to show them to.
///
/// Foldy has one user-facing channel — the menu bar status line — and it is only read
/// when the menu is open. Anything that fails behind the user's back (a capture that
/// refuses to start, a sensor that stops answering) needs a trail in Console, or a bug
/// report from a laptop arrives with nothing attached. `log stream --predicate
/// 'subsystem == "app.foldy"'` shows it.
public enum FoldyLog {
    public static let capture = Logger(subsystem: subsystem, category: "capture")
    public static let sensor = Logger(subsystem: subsystem, category: "sensor")
    public static let graphics = Logger(subsystem: subsystem, category: "graphics")
    public static let app = Logger(subsystem: subsystem, category: "app")
    private static let subsystem = "app.foldy"
}
