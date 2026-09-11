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
    let isAvailable: Bool
    private(set) var canCheck = false

    init(enabled: Bool) {
        let bundle = Bundle.main
        let configured = enabled
            && bundle.object(forInfoDictionaryKey: "SUFeedURL") != nil
            && bundle.object(forInfoDictionaryKey: "SUPublicEDKey") != nil
        isAvailable = configured
        controller = configured ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil) : nil
        canCheck = controller?.updater.canCheckForUpdates ?? false
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastCheck: Date? {
        controller?.updater.lastUpdateCheckDate
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
        canCheck = controller?.updater.canCheckForUpdates ?? false
    }
}
