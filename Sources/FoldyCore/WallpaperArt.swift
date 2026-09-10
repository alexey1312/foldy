import AppKit
import CoreGraphics
import CoreText
import Foundation

/// The sample desktop: a lock screen over dunes, drawn with CoreGraphics.
///
/// Used by the settings preview, the style thumbnails, the snapshot tool, and the
/// overlay when "sample wallpaper" is on or Screen Recording has not been granted.
public enum WallpaperArt {
    public static func image(width: Int = 1280, height: Int = 832, showsClock: Bool = true) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let w = CGFloat(width), h = CGFloat(height)
        ctx.interpolationQuality = .high

        // Sky: deep blue-grey at the top to pale at the horizon.
        drawGradient(ctx, in: CGRect(x: 0, y: 0, width: w, height: h),
                     from: CGPoint(x: 0, y: h), to: CGPoint(x: 0, y: 0),
                     colors: [(0.30, 0.35, 0.44), (0.76, 0.80, 0.85)])

        // Moon.
        ctx.setFillColor(CGColor(red: 0.94, green: 0.96, blue: 1.0, alpha: 0.85))
        let moonR = w * 0.039
        ctx.fillEllipse(in: CGRect(x: w * 0.76 - moonR, y: h * 0.73 - moonR, width: moonR * 2, height: moonR * 2))

        // Far dune.
        let far = CGMutablePath()
        far.move(to: CGPoint(x: 0, y: h * 0.36))
        far.addCurve(to: CGPoint(x: w * 0.68, y: h * 0.385),
                     control1: CGPoint(x: w * 0.14, y: h * 0.28), control2: CGPoint(x: w * 0.43, y: h * 0.45))
        far.addCurve(to: CGPoint(x: w, y: h * 0.47),
                     control1: CGPoint(x: w * 0.85, y: h * 0.34), control2: CGPoint(x: w * 0.93, y: h * 0.47))
        far.addLine(to: CGPoint(x: w, y: 0))
        far.addLine(to: CGPoint(x: 0, y: 0))
        far.closeSubpath()
        ctx.saveGState()
        ctx.addPath(far)
        ctx.clip()
        drawGradient(ctx, in: CGRect(x: 0, y: 0, width: w, height: h * 0.5),
                     from: CGPoint(x: w, y: h * 0.5), to: CGPoint(x: 0, y: 0),
                     colors: [(0.88, 0.90, 0.93), (0.52, 0.57, 0.62)])
        ctx.restoreGState()

        // Near dune.
        let near = CGMutablePath()
        near.move(to: CGPoint(x: 0, y: h * 0.28))
        near.addCurve(to: CGPoint(x: w * 0.54, y: h * 0.24),
                      control1: CGPoint(x: w * 0.14, y: h * 0.39), control2: CGPoint(x: w * 0.36, y: h * 0.38))
        near.addCurve(to: CGPoint(x: w, y: h * 0.16),
                      control1: CGPoint(x: w * 0.72, y: h * 0.10), control2: CGPoint(x: w * 0.86, y: h * 0.12))
        near.addLine(to: CGPoint(x: w, y: 0))
        near.addLine(to: CGPoint(x: 0, y: 0))
        near.closeSubpath()
        ctx.saveGState()
        ctx.addPath(near)
        ctx.clip()
        drawGradient(ctx, in: CGRect(x: 0, y: 0, width: w, height: h * 0.4),
                     from: CGPoint(x: 0, y: h * 0.4), to: CGPoint(x: w * 0.5, y: 0),
                     colors: [(0.80, 0.83, 0.87), (0.46, 0.53, 0.60)])
        ctx.restoreGState()

        if showsClock {
            let white = CGColor(red: 1, green: 1, blue: 1, alpha: 0.92)
            drawCentered(ctx, "Wednesday, September 9", font: NSFont.systemFont(ofSize: h * 0.036, weight: .medium),
                         color: white, y: h * 0.80)
            drawCentered(ctx, "9:41", font: NSFont.systemFont(ofSize: h * 0.22, weight: .thin), color: white, y: h * 0.575,
                         tracking: -h * 0.006)
        }

        // Home indicator.
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.7))
        let barW = w * 0.2, barH = h * 0.012
        let bar = CGPath(roundedRect: CGRect(x: (w - barW) / 2, y: h * 0.045, width: barW, height: barH),
                         cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil)
        ctx.addPath(bar)
        ctx.fillPath()

        return ctx.makeImage()
    }

    private static func drawGradient(_ ctx: CGContext, in rect: CGRect, from: CGPoint, to: CGPoint,
                                     colors: [(CGFloat, CGFloat, CGFloat)]) {
        let cgColors = colors.map { CGColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1) } as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil) else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    private static func drawCentered(_ ctx: CGContext, _ text: String, font: NSFont, color: CGColor, y: CGFloat, tracking: CGFloat = 0) {
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color,
            kCTKernAttributeName: tracking,
        ]
        let string = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attributes as CFDictionary)!
        let line = CTLineCreateWithAttributedString(string)
        let bounds = CTLineGetBoundsWithOptions(line, [.useOpticalBounds])
        ctx.saveGState()
        ctx.textPosition = CGPoint(x: (CGFloat(ctx.width) - bounds.width) / 2 - bounds.minX, y: y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
