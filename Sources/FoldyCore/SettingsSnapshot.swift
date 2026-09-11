import Foundation

/// Everything the user can change, as it is written to disk.
///
/// Decoded by hand, and that is the whole point. Swift's synthesized `Decodable`
/// ignores property defaults: a key that is missing throws, and the app's `try?` then
/// falls back to a brand new snapshot. So the first release to add a field here wiped
/// every existing user's settings — style, tuned parameters, curve, sound — and showed
/// them the welcome tour again. That shipped once, in 0.1.2. A new field must take its
/// default and leave everything else where it was; `SettingsSnapshotTests` holds the
/// line, using JSON as written by an older Foldy.
public struct SettingsSnapshot: Codable, Equatable, Sendable {
    public var style: FoldStyle = .silk
    public var styleParameters: [String: FoldParameters] = [:]
    public var curve: FoldCurve = .default
    public var soundEnabled = true
    public var previewFollowsLid = true
    public var previewAngle: Double = FoldCurve.fullyOpenAngle
    public var sampleWallpaper = false
    public var showsAngleInMenuBar = false
    public var onboardingCompleted = false
    public var onboardingStep = 0

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decode<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            // A value of the wrong shape is as good as a missing one: take the default
            // rather than throwing away every other setting alongside it.
            ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        style = decode(.style, FoldStyle.silk)
        styleParameters = decode(.styleParameters, [:])
        curve = decode(.curve, FoldCurve.default)
        soundEnabled = decode(.soundEnabled, true)
        previewFollowsLid = decode(.previewFollowsLid, true)
        previewAngle = decode(.previewAngle, FoldCurve.fullyOpenAngle)
        sampleWallpaper = decode(.sampleWallpaper, false)
        showsAngleInMenuBar = decode(.showsAngleInMenuBar, false)
        onboardingCompleted = decode(.onboardingCompleted, false)
        onboardingStep = decode(.onboardingStep, 0)
    }
}
