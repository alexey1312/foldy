import Foundation

/// One of the three looks the desktop can take as the lid comes down.
public enum FoldStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case silk
    case shade
    case frost

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .silk: "Silk"
        case .shade: "Shade"
        case .frost: "Frost"
        }
    }

    public var summary: String {
        switch self {
        case .silk: "A soft tilt with a light blur. Closest to the fold on iPhone Duo."
        case .shade: "The same tilt, with the top of the desktop falling into shadow."
        case .frost: "Heavier blur and a cool haze, like breath on glass."
        }
    }

    /// The factory settings for the style. Users tune from here.
    public var parameters: FoldParameters {
        switch self {
        case .silk: FoldParameters(perspective: 1.0, blur: 0.65, shadow: 0.5, bend: 0.35, frost: 0.0)
        case .shade: FoldParameters(perspective: 0.9, blur: 0.45, shadow: 1.0, bend: 0.25, frost: 0.0)
        case .frost: FoldParameters(perspective: 0.8, blur: 1.0, shadow: 0.3, bend: 0.45, frost: 0.7)
        }
    }
}

/// The knobs behind a style. Every value is 0…1; the shader scales them.
public struct FoldParameters: Codable, Sendable, Equatable, Hashable {
    /// How far the top of the desktop tilts away. 1 is the full 72° of the web demo.
    public var perspective: Double
    /// How strongly the blur grows toward the top edge.
    public var blur: Double
    /// How dark the top and the top corners get.
    public var shadow: Double
    /// 0 keeps the sheet rigid (a plain tilt); 1 curls it, so the base stays put
    /// and only the upper part folds back, like a page.
    public var bend: Double
    /// A cool, milky haze mixed into the blurred region.
    public var frost: Double

    public init(perspective: Double, blur: Double, shadow: Double, bend: Double, frost: Double) {
        self.perspective = perspective
        self.blur = blur
        self.shadow = shadow
        self.bend = bend
        self.frost = frost
    }

    public func clamped() -> FoldParameters {
        FoldParameters(
            perspective: perspective.clamped(),
            blur: blur.clamped(),
            shadow: shadow.clamped(),
            bend: bend.clamped(),
            frost: frost.clamped()
        )
    }
}

/// Maps the hinge angle to fold progress.
///
/// Above `clearAngle` the desktop is flat and the overlay is hidden. Between the two
/// angles the fold eases in with a smoothstep, so it never snaps. At or below
/// `foldedAngle` it is fully folded; macOS puts the Mac to sleep a few degrees later.
public struct FoldCurve: Codable, Sendable, Equatable, Hashable {
    public var clearAngle: Double
    public var foldedAngle: Double

    public static let `default` = FoldCurve(clearAngle: 100, foldedAngle: 20)

    /// The hinge angle of a MacBook opened all the way.
    public static let fullyOpenAngle: Double = 135

    public init(clearAngle: Double, foldedAngle: Double) {
        self.clearAngle = clearAngle
        self.foldedAngle = foldedAngle
    }

    /// Linear fraction of the way from `clearAngle` down to `foldedAngle`, 0…1.
    public func fraction(forAngle angle: Double) -> Double {
        guard clearAngle > foldedAngle else { return angle <= foldedAngle ? 1 : 0 }
        return ((clearAngle - angle) / (clearAngle - foldedAngle)).clamped()
    }

    /// Eased fold progress for a hinge angle, 0…1.
    public func progress(forAngle angle: Double) -> Double {
        smoothstep(fraction(forAngle: angle))
    }

    /// The hinge angle at a linear fraction of the fold. Inverse of `fraction(forAngle:)`.
    public func angle(forFraction fraction: Double) -> Double {
        clearAngle - fraction.clamped() * (clearAngle - foldedAngle)
    }
}

@inlinable
public func smoothstep(_ t: Double) -> Double {
    let c = t.clamped()
    return c * c * (3 - 2 * c)
}

extension Double {
    @inlinable
    public func clamped(_ lower: Double = 0, _ upper: Double = 1) -> Double {
        Swift.min(Swift.max(self, lower), upper)
    }
}
