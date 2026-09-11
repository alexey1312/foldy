import Foundation
import Observation
import Sparkle

/// Sparkle, wrapped so the rest of the app never imports it.
///
/// Runs only from a bundle that carries `SUFeedURL` and `SUPublicEDKey`; the bare
/// `swift run` binary has neither and gets a dormant updater. The feed is
/// `site/appcast.xml`, published to GitHub Pages by the release workflow.
@MainActor
@Observable
final class Updater {
    private let controller: SPUStandardUpdaterController?
    /// Whether this copy of Foldy can update itself — a property of the bundle alone, so
    /// a screenshot run photographs the card users actually see, with only the network
    /// side of Sparkle held back.
    let isAvailable: Bool
    private(set) var canCheck = false
    private(set) var lastCheck: Date?

    /// Mirrored rather than read through: `@Observable` tracks stored properties, so a
    /// computed passthrough to Sparkle left the switch in Settings unable to redraw
    /// itself — it stayed where it was until something else invalidated the view.
    var automaticallyChecks: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    init(enabled: Bool) {
        let bundle = Bundle.main
        isAvailable = bundle.object(forInfoDictionaryKey: "SUFeedURL") != nil
            && bundle.object(forInfoDictionaryKey: "SUPublicEDKey") != nil
        controller = isAvailable && enabled
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
        automaticallyChecks = controller?.updater.automaticallyChecksForUpdates ?? true
        canCheck = controller?.updater.canCheckForUpdates ?? false
        lastCheck = controller?.updater.lastUpdateCheckDate
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
        canCheck = controller?.updater.canCheckForUpdates ?? false
        lastCheck = controller?.updater.lastUpdateCheckDate
    }
}
