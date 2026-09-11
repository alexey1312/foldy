import Foundation

/// Decides, from the lid angle and the app's flags, whether the desktop should be
/// captured and whether the fold should be shown.
///
/// It lives here rather than in `AppController` for one reason: it is the only part of
/// the app that can be tested. The two bugs it exists to prevent were both invisible on
/// a Mac without a lid sensor, and both shipped:
///
/// * a capture stopped for being idle was restarted by the very next decision, so the
///   screen recording indicator flashed every four seconds for as long as the lid sat
///   still;
/// * a lid resting between the pre-warm band and the stop band was never stopped at all,
///   so the indicator simply stayed lit.
///
/// `AppController` owns every decision in the sense that matters — it is the only caller,
/// and it alone acts on what comes back. Add conditions here, with a test, not there.
public struct CapturePolicy: Sendable, Equatable {
    /// Everything the decision depends on. No AppKit, no clock, no I/O.
    public struct Input: Sendable, Equatable {
        public var angle: Double
        public var curve: FoldCurve
        public var isPaused: Bool
        public var isDismissed: Bool
        public var isSweeping: Bool
        public var overlayShown: Bool
        public var usesSampleWallpaper: Bool

        public init(
            angle: Double,
            curve: FoldCurve = .default,
            isPaused: Bool = false,
            isDismissed: Bool = false,
            isSweeping: Bool = false,
            overlayShown: Bool = false,
            usesSampleWallpaper: Bool = false
        ) {
            self.angle = angle
            self.curve = curve
            self.isPaused = isPaused
            self.isDismissed = isDismissed
            self.isSweeping = isSweeping
            self.overlayShown = overlayShown
            self.usesSampleWallpaper = usesSampleWallpaper
        }
    }

    public struct Decision: Sendable, Equatable {
        /// Eased fold progress for the angle, 0…1.
        public var progress: Double
        /// The overlay should be up.
        public var wantsFold: Bool
        /// The stream should be running — during the fold, and a little before it.
        public var wantsCapture: Bool
        /// The lid is clear enough that a running stream should be torn down at once
        /// rather than waiting out the idle timer.
        public var farFromFold: Bool
        /// Nothing is folded, so a running stream is earning nothing.
        public var isIdle: Bool
        /// The lid has opened past the clear angle, so a dismissed fold comes back.
        public var clearsDismissal: Bool
    }

    /// The fold has to reach this much before the overlay is shown; once shown it stays
    /// until the fold is fully gone, so a lid resting at the clear angle does not
    /// flicker the window in and out.
    public static let showThreshold: Double = 0.02
    /// How far above the clear angle the stream is started, so a frame is ready by the
    /// time the fold is due.
    public static let preWarmBand: Double = 15
    /// How far above the clear angle a running stream is torn down immediately.
    public static let stopBand: Double = 25
    /// How far the lid has to close from where the capture parked before it is started
    /// again. Wider than the 0.5° filter in `LidAngleSensor.deliver`, the intent being
    /// that a desk bump does not wake it while a real close crosses it at once.
    public static let wakeDegrees: Double = 1.5

    /// The angle the capture was parked at, raised as the lid opens further. `nil` means
    /// the capture is free to start.
    public private(set) var parkedAngle: Double?

    public init() {}

    /// Records that a capture nothing was using has been stopped at `angle`.
    public mutating func park(at angle: Double) {
        parkedAngle = angle
    }

    /// Frees the capture to start again: the world the park described is gone.
    public mutating func unpark() {
        parkedAngle = nil
    }

    public mutating func decide(_ input: Input) -> Decision {
        let curve = input.curve
        let angle = input.angle
        let progress = curve.progress(forAngle: angle)
        let clearsDismissal = input.isDismissed && angle >= curve.clearAngle
        let dismissed = input.isDismissed && !clearsDismissal
        let wantsFold = !input.isPaused && !dismissed
            && progress > (input.overlayShown ? 0 : Self.showThreshold)
        let nearFold = angle < curve.clearAngle + Self.preWarmBand

        // The park has to follow the lid up, or it goes stale: a fold dismissed at 60°
        // parks there, and after the lid is opened back to a working angle no amount of
        // closing reaches 58.5° before the fold itself is due. Tracking the top of the
        // resting band keeps the wake ahead of the fold, and stops a lid jittering across
        // the edge of the band from waking the capture at all.
        if let parked = parkedAngle {
            if wantsFold || angle < parked - Self.wakeDegrees {
                parkedAngle = nil
            } else if angle > parked {
                parkedAngle = angle
            }
        }

        let wantsCapture = !input.isPaused && !input.usesSampleWallpaper && parkedAngle == nil
            && (nearFold || wantsFold || input.isSweeping)

        return Decision(
            progress: progress,
            wantsFold: wantsFold,
            wantsCapture: wantsCapture,
            farFromFold: angle > curve.clearAngle + Self.stopBand,
            isIdle: !wantsFold,
            clearsDismissal: clearsDismissal
        )
    }
}
