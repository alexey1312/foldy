import FoldyCore
import MetalKit
import SwiftUI

/// The 3D MacBook whose lid follows `lidAngle`, with the fold on its screen.
struct MacBookPreviewView: NSViewRepresentable {
    let graphics: FoldGraphics
    var lidAngle: Double
    var parameters: FoldParameters
    var curve: FoldCurve
    /// Put the lid at `lidAngle` at once instead of easing there: the Reduce Motion
    /// path, where the swing from wherever the lid was is the motion being avoided.
    var immediate = false

    func makeCoordinator() -> Coordinator {
        Coordinator(graphics: graphics)
    }

    func makeNSView(context: Context) -> SceneMetalView {
        let view = SceneMetalView(frame: .zero, device: graphics.device)
        view.scene = context.coordinator.scene
        view.commandQueue = graphics.commandQueue
        view.colorPixelFormat = FoldGraphics.pixelFormat
        view.depthStencilPixelFormat = FoldGraphics.depthFormat
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.preferredFramesPerSecond = 60
        // Draws continuously only while the lid or the fold is moving; see draw(_:).
        view.enableSetNeedsDisplay = true
        view.layer?.isOpaque = false
        (view.layer as? CAMetalLayer)?.isOpaque = false
        return view
    }

    func updateNSView(_ view: SceneMetalView, context: Context) {
        guard let scene = context.coordinator.scene else { return }
        scene.fold.parameters = parameters
        scene.curve = curve
        if immediate {
            scene.lidAngleJump(to: lidAngle)
        } else {
            scene.targetLidAngle = lidAngle
        }
        view.isPaused = false
        view.needsDisplay = true
    }

    final class Coordinator {
        let scene: MacBookScene?

        init(graphics: FoldGraphics) {
            // A blank preview pane with nothing in Console is a support question nobody
            // can answer; these are the only places the Settings previews can fail.
            do {
                let scene = try MacBookScene(graphics: graphics)
                if let image = WallpaperArt.image() {
                    try scene.fold.setSource(cgImage: image)
                }
                scene.lidAngleJump(to: FoldCurve.fullyOpenAngle)
                self.scene = scene
            } catch {
                scene = nil
                FoldyLog.graphics.error("settings preview unavailable: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

final class SceneMetalView: MTKView {
    var scene: MacBookScene?
    var commandQueue: MTLCommandQueue?

    override func draw(_ dirtyRect: NSRect) {
        guard let scene, let commandQueue, let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        scene.step()
        scene.encode(into: commandBuffer, target: drawable.texture, depth: depthStencilTexture)
        commandBuffer.present(drawable)
        commandBuffer.commit()
        // Once everything has settled, stop the display link until a new target arrives.
        if scene.isSettled { isPaused = true }
    }
}

/// A still of the fold at 80 %, for the style cards. Redraws only when its parameters change.
///
/// Transparent, like the MacBook preview: the stage it sits on is whatever SwiftUI puts
/// behind it, so the card follows the appearance and the no-Metal fallback shares it.
struct FoldThumbnailView: NSViewRepresentable {
    let graphics: FoldGraphics
    var parameters: FoldParameters

    func makeCoordinator() -> Coordinator {
        Coordinator(graphics: graphics)
    }

    func makeNSView(context: Context) -> ThumbnailMetalView {
        let view = ThumbnailMetalView(frame: .zero, device: graphics.device)
        view.renderer = context.coordinator.renderer
        view.commandQueue = graphics.commandQueue
        view.colorPixelFormat = FoldGraphics.pixelFormat
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.layer?.isOpaque = false
        (view.layer as? CAMetalLayer)?.isOpaque = false
        return view
    }

    func updateNSView(_ view: ThumbnailMetalView, context: Context) {
        context.coordinator.renderer?.parameters = parameters
        view.needsDisplay = true
    }

    final class Coordinator {
        let renderer: FoldRenderer?

        init(graphics: FoldGraphics) {
            do {
                let renderer = try FoldRenderer(graphics: graphics)
                renderer.smoothing = 1
                renderer.targetProgress = 0.8
                if let image = WallpaperArt.image(width: 640, height: 416) {
                    try renderer.setSource(cgImage: image)
                }
                self.renderer = renderer
            } catch {
                renderer = nil
                FoldyLog.graphics.error("style thumbnail unavailable: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

final class ThumbnailMetalView: MTKView {
    var renderer: FoldRenderer?
    var commandQueue: MTLCommandQueue?

    override func draw(_ dirtyRect: NSRect) {
        guard let renderer, let commandQueue, let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        renderer.step()
        renderer.encode(into: commandBuffer, target: drawable.texture, clearColor: clearColor)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
