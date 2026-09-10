import FoldyCore
import MetalKit
import SwiftUI

/// The 3D MacBook whose lid follows `lidAngle`, with the fold on its screen.
struct MacBookPreviewView: NSViewRepresentable {
    let graphics: FoldGraphics
    var lidAngle: Double
    var parameters: FoldParameters
    var curve: FoldCurve

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
        view.layer?.isOpaque = false
        (view.layer as? CAMetalLayer)?.isOpaque = false
        return view
    }

    func updateNSView(_ view: SceneMetalView, context: Context) {
        let scene = context.coordinator.scene
        scene?.targetLidAngle = lidAngle
        scene?.fold.parameters = parameters
        scene?.curve = curve
    }

    final class Coordinator {
        let scene: MacBookScene?

        init(graphics: FoldGraphics) {
            scene = try? MacBookScene(graphics: graphics)
            if let scene, let image = WallpaperArt.image() {
                try? scene.fold.setSource(cgImage: image)
                scene.lidAngleJump(to: FoldCurve.fullyOpenAngle)
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
    }
}

/// A still of the fold at 80 %, for the style cards. Redraws only when its parameters change.
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
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        return view
    }

    func updateNSView(_ view: ThumbnailMetalView, context: Context) {
        context.coordinator.renderer?.parameters = parameters
        view.needsDisplay = true
    }

    final class Coordinator {
        let renderer: FoldRenderer?

        init(graphics: FoldGraphics) {
            renderer = try? FoldRenderer(graphics: graphics)
            renderer?.smoothing = 1
            renderer?.targetProgress = 0.8
            if let renderer, let image = WallpaperArt.image(width: 640, height: 416) {
                try? renderer.setSource(cgImage: image)
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
        renderer.encode(into: commandBuffer, target: drawable.texture, clearColor: MTLClearColor(red: 0.07, green: 0.07, blue: 0.075, alpha: 1))
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
