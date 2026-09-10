import FoldyCore
import Foundation
import Observation
import ServiceManagement

/// Everything the user can change, persisted to UserDefaults as one JSON blob.
@MainActor
@Observable
final class SettingsStore {
    private struct Snapshot: Codable {
        var style: FoldStyle = .silk
        var styleParameters: [String: FoldParameters] = [:]
        var curve: FoldCurve = .default
        var soundEnabled = true
        var previewFollowsLid = true
        var previewAngle: Double = FoldCurve.fullyOpenAngle
        var sampleWallpaper = false
        var showsAngleInMenuBar = false
    }

    private static let key = "app.foldy.settings"
    private var loading = true

    var style: FoldStyle { didSet { save() } }
    /// Tuned parameters per style; a style with no entry uses its factory settings.
    private(set) var styleParameters: [String: FoldParameters] { didSet { save() } }
    var curve: FoldCurve { didSet { save() } }
    var soundEnabled: Bool { didSet { save() } }
    var previewFollowsLid: Bool { didSet { save() } }
    var previewAngle: Double { didSet { save() } }
    var sampleWallpaper: Bool { didSet { save() } }
    var showsAngleInMenuBar: Bool { didSet { save() } }

    init() {
        var snapshot = Snapshot()
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = stored
        }
        style = snapshot.style
        styleParameters = snapshot.styleParameters
        curve = snapshot.curve
        soundEnabled = snapshot.soundEnabled
        previewFollowsLid = snapshot.previewFollowsLid
        previewAngle = snapshot.previewAngle
        sampleWallpaper = snapshot.sampleWallpaper
        showsAngleInMenuBar = snapshot.showsAngleInMenuBar
        loading = false
    }

    /// The parameters in force for the selected style.
    var parameters: FoldParameters {
        get { parameters(for: style) }
        set { styleParameters[style.rawValue] = newValue.clamped() }
    }

    func parameters(for style: FoldStyle) -> FoldParameters {
        styleParameters[style.rawValue] ?? style.parameters
    }

    var parametersAreCustom: Bool {
        styleParameters[style.rawValue] != nil && styleParameters[style.rawValue] != style.parameters
    }

    func resetParameters() {
        styleParameters[style.rawValue] = nil
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Only works from an app bundle; `swift run` has nothing to register.
    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    // MARK: Persistence

    private func save() {
        guard !loading else { return }
        let snapshot = Snapshot(
            style: style, styleParameters: styleParameters, curve: curve, soundEnabled: soundEnabled,
            previewFollowsLid: previewFollowsLid, previewAngle: previewAngle,
            sampleWallpaper: sampleWallpaper, showsAngleInMenuBar: showsAngleInMenuBar
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
