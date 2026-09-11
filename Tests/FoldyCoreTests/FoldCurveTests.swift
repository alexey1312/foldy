import Foundation
import Testing
@testable import FoldyCore

@Suite("FoldCurve")
struct FoldCurveTests {
    let curve = FoldCurve.default

    @Test("flat above the clear angle, folded at the folded angle")
    func endpoints() {
        #expect(curve.progress(forAngle: 135) == 0)
        #expect(curve.progress(forAngle: 100) == 0)
        #expect(curve.progress(forAngle: 20) == 1)
        #expect(curve.progress(forAngle: 0) == 1)
    }

    @Test("eases through the middle")
    func middle() {
        let mid = curve.progress(forAngle: 60)
        #expect(abs(mid - 0.5) < 1e-9)
        #expect(curve.progress(forAngle: 90) < 0.1)
        #expect(curve.progress(forAngle: 30) > 0.9)
    }

    @Test("progress never decreases as the lid closes")
    func monotonic() {
        var last = -1.0
        for angle in stride(from: 135.0, through: 0.0, by: -1.0) {
            let p = curve.progress(forAngle: angle)
            #expect(p >= last)
            last = p
        }
    }

    @Test("angle(forFraction:) inverts fraction(forAngle:)")
    func inverse() {
        for fraction in stride(from: 0.0, through: 1.0, by: 0.125) {
            let angle = curve.angle(forFraction: fraction)
            #expect(abs(curve.fraction(forAngle: angle) - fraction) < 1e-9)
        }
    }

    @Test("a degenerate curve still answers")
    func degenerate() {
        let flat = FoldCurve(clearAngle: 50, foldedAngle: 50)
        #expect(flat.progress(forAngle: 60) == 0)
        #expect(flat.progress(forAngle: 40) == 1)
    }
}

@Suite("FoldStyle")
struct FoldStyleTests {
    @Test("every style's parameters are in range")
    func parametersInRange() {
        for style in FoldStyle.allCases {
            #expect(style.parameters == style.parameters.clamped())
        }
    }

    @Test("clamping actually clamps")
    func clampingClamps() {
        let wild = FoldParameters(perspective: 2, blur: -1, shadow: 0.5, bend: 1.5, frost: -0.2).clamped()
        #expect(wild == FoldParameters(perspective: 1, blur: 0, shadow: 0.5, bend: 1, frost: 0))
    }

    @Test("round-trips through Codable")
    func codable() throws {
        let encoded = try JSONEncoder().encode(FoldStyle.frost.parameters)
        let decoded = try JSONDecoder().decode(FoldParameters.self, from: encoded)
        #expect(decoded == FoldStyle.frost.parameters)
    }
}
