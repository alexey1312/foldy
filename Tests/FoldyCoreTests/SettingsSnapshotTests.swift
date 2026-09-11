import Foundation
import Testing
@testable import FoldyCore

@Suite("SettingsSnapshot")
struct SettingsSnapshotTests {
    /// Exactly what Foldy 0.1.1 wrote: no onboarding keys at all.
    private let v0_1_1 = """
    {"style":"frost","styleParameters":{},"curve":{"clearAngle":90,"foldedAngle":25},
     "soundEnabled":false,"previewFollowsLid":true,"previewAngle":135,
     "sampleWallpaper":false,"showsAngleInMenuBar":true}
    """

    @Test("settings written by an older Foldy still load")
    func decodesOlderBlob() throws {
        let snapshot = try JSONDecoder().decode(SettingsSnapshot.self, from: Data(v0_1_1.utf8))
        #expect(snapshot.style == .frost)
        #expect(snapshot.curve == FoldCurve(clearAngle: 90, foldedAngle: 25))
        #expect(snapshot.soundEnabled == false)
        #expect(snapshot.showsAngleInMenuBar)
        // The fields 0.1.2 added take their defaults; nothing else resets.
        #expect(snapshot.onboardingCompleted == false)
        #expect(snapshot.onboardingStep == 0)
    }

    @Test("an unknown style keeps the rest of the settings")
    func survivesAnUnknownValue() throws {
        let json = #"{"style":"velvet","soundEnabled":false,"showsAngleInMenuBar":true}"#
        let snapshot = try JSONDecoder().decode(SettingsSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.style == .silk)
        #expect(snapshot.soundEnabled == false)
        #expect(snapshot.showsAngleInMenuBar)
    }

    @Test("an empty object is all defaults, not a failure")
    func decodesEmpty() throws {
        let snapshot = try JSONDecoder().decode(SettingsSnapshot.self, from: Data("{}".utf8))
        #expect(snapshot == SettingsSnapshot())
    }

    @Test("round-trips everything the user can change")
    func roundTrips() throws {
        var snapshot = SettingsSnapshot()
        snapshot.style = .shade
        snapshot.styleParameters = ["shade": FoldStyle.shade.parameters]
        snapshot.curve = FoldCurve(clearAngle: 112, foldedAngle: 14)
        snapshot.previewAngle = 101
        snapshot.onboardingCompleted = true
        snapshot.onboardingStep = 3
        let decoded = try JSONDecoder().decode(SettingsSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
    }
}
