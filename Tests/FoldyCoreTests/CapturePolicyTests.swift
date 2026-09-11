import Testing
@testable import FoldyCore

@Suite("CapturePolicy")
struct CapturePolicyTests {
    /// A lid resting in the band above the fold, with nothing on screen.
    private func resting(_ angle: Double, curve: FoldCurve = .default) -> CapturePolicy.Input {
        CapturePolicy.Input(angle: angle, curve: curve)
    }

    @Test("a capture parked for being idle is not restarted by the next decision")
    func parkedStaysParked() {
        // The bug: stopping the stream published .idle, which re-entered the decision,
        // which wanted the stream again — a four-second flash of the screen recording
        // indicator for as long as the lid sat still. One call passing proves nothing;
        // the property is idempotence under the same input.
        var policy = CapturePolicy()
        #expect(policy.decide(resting(110)).wantsCapture)
        #expect(policy.decide(resting(110)).isIdle)
        policy.park(at: 110)
        for _ in 0..<50 {
            #expect(!policy.decide(resting(110)).wantsCapture)
        }
    }

    @Test("the park wakes only when the lid really closes")
    func wakesOnClosing() {
        var policy = CapturePolicy()
        policy.park(at: 110)
        #expect(!policy.decide(resting(109)).wantsCapture)   // inside the deadband
        #expect(policy.decide(resting(108)).wantsCapture)    // through it
        #expect(policy.parkedAngle == nil)
    }

    @Test("the park follows the lid up, so a dismissed fold still gets a warm stream")
    func parkRatchets() {
        var policy = CapturePolicy()
        policy.park(at: 60)                                   // fold dismissed down here
        _ = policy.decide(CapturePolicy.Input(angle: 100, isDismissed: true))
        #expect(policy.parkedAngle == 100)                    // not stuck at 60
        #expect(!policy.decide(resting(100)).wantsCapture)
        let waking = policy.decide(resting(98))
        #expect(waking.wantsCapture)
        #expect(!waking.wantsFold)                            // and with the fold still to come
    }

    @Test("a lid jittering across the edge of the band does not wake the capture")
    func noFlapAtTheBandEdge() {
        var policy = CapturePolicy()
        policy.park(at: 114.5)
        for angle in [115.5, 114.5, 115.5, 114.6, 115.4] {
            #expect(!policy.decide(resting(angle)).wantsCapture)
        }
    }

    @Test("a running capture is always idle-stoppable when nothing is folded")
    func idleAboveTheBand() {
        // 115…125 is neither in the pre-warm band nor far enough out to be torn down,
        // and a still lid sends no further reports — so the stream ran forever here.
        var policy = CapturePolicy()
        for angle in [116.0, 120.0, 124.0] {
            let decision = policy.decide(resting(angle))
            #expect(decision.isIdle)
            #expect(!decision.wantsFold)
        }
    }

    @Test("the capture starts before the fold is due, for every curve the sliders allow")
    func captureLeadsTheFold() {
        // The sliders permit clear 60…130 and folded 5…50, so the narrowest fold is 10°.
        for clear in stride(from: 60.0, through: 130.0, by: 10) {
            for folded in stride(from: 5.0, through: 50.0, by: 15) where folded < clear {
                let curve = FoldCurve(clearAngle: clear, foldedAngle: folded)
                for parkedAt in stride(from: clear, through: clear + CapturePolicy.preWarmBand, by: 2.5) {
                    var policy = CapturePolicy()
                    policy.park(at: parkedAt)
                    var warm = false
                    for step in stride(from: parkedAt, through: folded, by: -0.5) {
                        let decision = policy.decide(resting(step, curve: curve))
                        warm = warm || decision.wantsCapture
                        if decision.wantsFold {
                            #expect(warm, "fold due at \(step)° with the capture still parked")
                        }
                    }
                    #expect(warm, "the capture never woke on the way down from \(parkedAt)°")
                }
            }
        }
    }

    @Test("pause, the sample wallpaper and a dismissal each hold the stream off")
    func flagsWin() {
        var policy = CapturePolicy()
        #expect(!policy.decide(CapturePolicy.Input(angle: 60, isPaused: true)).wantsCapture)
        #expect(!policy.decide(CapturePolicy.Input(angle: 60, isPaused: true)).wantsFold)
        #expect(!policy.decide(CapturePolicy.Input(angle: 60, usesSampleWallpaper: true)).wantsCapture)
        #expect(!policy.decide(CapturePolicy.Input(angle: 60, isDismissed: true)).wantsFold)
    }

    @Test("a dismissal clears when the lid opens past the clear angle")
    func dismissalClears() {
        var policy = CapturePolicy()
        #expect(!policy.decide(CapturePolicy.Input(angle: 99, isDismissed: true)).clearsDismissal)
        let opened = policy.decide(CapturePolicy.Input(angle: 100, isDismissed: true))
        #expect(opened.clearsDismissal)
    }

    @Test("the overlay shows above the threshold and hides only at flat")
    func overlayHysteresis() {
        var policy = CapturePolicy()
        let curve = FoldCurve.default
        let justInside = curve.angle(forFraction: 0.07)       // progress below 0.02
        #expect(!policy.decide(resting(justInside)).wantsFold)
        #expect(policy.decide(CapturePolicy.Input(angle: justInside, overlayShown: true)).wantsFold)
        #expect(!policy.decide(CapturePolicy.Input(angle: curve.clearAngle, overlayShown: true)).wantsFold)
    }

    @Test("the sweep gets a stream even with the lid wide open")
    func sweepWarmsUp() {
        var policy = CapturePolicy()
        #expect(!policy.decide(resting(FoldCurve.fullyOpenAngle)).wantsCapture)
        #expect(policy.decide(CapturePolicy.Input(angle: FoldCurve.fullyOpenAngle, isSweeping: true)).wantsCapture)
    }
}

@Suite("FoldRenderer smoothing")
struct FoldSmoothingTests {
    @Test("the easing is per unit time, not per frame")
    func frameRateIndependent() {
        let perFrame = FoldRenderer.factor(0.12, dt: 1.0 / 60.0)
        #expect(abs(perFrame - 0.12) < 1e-9)
        // Two 60 Hz frames must move as far as one 30 Hz frame.
        let doubled = FoldRenderer.factor(0.12, dt: 1.0 / 30.0)
        let twoSteps = 1 - (1 - perFrame) * (1 - perFrame)
        #expect(abs(doubled - twoSteps) < 1e-9)
        #expect(FoldRenderer.factor(1, dt: 1.0 / 60.0) == 1)
        #expect(FoldRenderer.factor(0, dt: 1.0 / 60.0) == 0)
    }
}
