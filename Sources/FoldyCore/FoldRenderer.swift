import CoreGraphics
import CoreVideo
import Foundation
import Metal
import MetalKit

/// Mirrors `FoldUniforms` in the shader, float for float.
struct FoldUniforms {
    var progress: Float = 0
    var perspective: Float = 1
    var blur: Float = 0.65
    var shadow: Float = 0.5
    var bend: Float = 0.35
    var frost: Float = 0
    var aspect: Float = 1.54
    var cornerRadius: Float = 0.03
    var cameraDistance: Float = 2.4
    var maxTilt: Float = 72 * .pi / 180
    var pad0: Float = 0
    var pad1: Float = 0
}

/// Draws the desktop as a sheet that tilts, bends, blurs and shades with the fold.
///
/// Feed it the desktop (a captured pixel buffer or an image), set `targetProgress`,
/// call `step()` once per frame to let the motion settle, then `encode`. Progress is
/// smoothed inside so a jumpy sensor still gives a fluid fold.
public final class FoldRenderer: @unchecked Sendable {
    public let graphics: FoldGraphics

    /// Where the fold is heading, 0 flat … 1 folded.
    public var targetProgress: Double = 0
    /// Where the fold is now, after smoothing.
    public private(set) var progress: Double = 0
    /// Per-frame lerp factor toward the target. 1 disables smoothing.
    public var smoothing: Double = 0.1
    public var parameters: FoldParameters = FoldStyle.silk.parameters
    /// Corner radius of the sheet in units of its height.
    public var cornerRadius: Double = 0.03
    /// Distance from the eye to the flat sheet, in units of sheet height. Larger is flatter.
    public var cameraDistance: Double = 2.4
    /// The full tilt at progress 1 with perspective 1, in degrees.
    public var maxTiltDegrees: Double = 72

    private let vertexBuffer: MTLBuffer
    private let indexBuffer: MTLBuffer
    private let indexCount: Int
    private let lock = NSLock()
    private var pendingPixelBuffer: CVPixelBuffer?
    private var source: MTLTexture?

    public static let gridResolution = 64

    public init(graphics: FoldGraphics) throws {
        self.graphics = graphics
        let (vertices, indices) = Self.makeGrid(resolution: Self.gridResolution)
        guard let vertexBuffer = graphics.device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<SIMD2<Float>>.stride),
              let indexBuffer = graphics.device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt32>.stride)
        else { throw FoldGraphicsError.noDevice }
        vertexBuffer.label = "Fold grid vertices"
        indexBuffer.label = "Fold grid indices"
        self.vertexBuffer = vertexBuffer
        self.indexBuffer = indexBuffer
        indexCount = indices.count
    }

    private static func makeGrid(resolution n: Int) -> ([SIMD2<Float>], [UInt32]) {
        var vertices: [SIMD2<Float>] = []
        vertices.reserveCapacity((n + 1) * (n + 1))
        for row in 0...n {
            for column in 0...n {
                vertices.append(SIMD2(Float(column) / Float(n), Float(row) / Float(n)))
            }
        }
        var indices: [UInt32] = []
        indices.reserveCapacity(n * n * 6)
        for row in 0..<n {
            for column in 0..<n {
                let a = UInt32(row * (n + 1) + column)
                let b = a + 1
                let c = a + UInt32(n + 1)
                let d = c + 1
                indices += [a, c, b, b, c, d]
            }
        }
        return (vertices, indices)
    }

    // MARK: - Source

    /// Queues a captured frame. Safe to call from the capture queue.
    public func setSource(pixelBuffer: CVPixelBuffer) {
        lock.lock()
        pendingPixelBuffer = pixelBuffer
        lock.unlock()
    }

    /// Uses a still image as the desktop.
    public func setSource(cgImage: CGImage) throws {
        let texture = try graphics.textureLoader.newTexture(cgImage: cgImage, options: [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .generateMipmaps: true,
            .SRGB: false,
        ])
        lock.lock()
        pendingPixelBuffer = nil
        source = texture
        lock.unlock()
    }

    public var hasSource: Bool {
        lock.lock()
        defer { lock.unlock() }
        return source != nil || pendingPixelBuffer != nil
    }

    /// The source's width over its height, or `nil` before anything has been set.
    public var sourceAspect: Double? {
        lock.lock()
        defer { lock.unlock() }
        if let pendingPixelBuffer {
            return Double(CVPixelBufferGetWidth(pendingPixelBuffer)) / Double(CVPixelBufferGetHeight(pendingPixelBuffer))
        }
        guard let source else { return nil }
        return Double(source.width) / Double(source.height)
    }

    // MARK: - Frame

    /// Moves `progress` toward `targetProgress`. Call once per frame.
    public func step() {
        let target = targetProgress.clamped()
        if smoothing >= 1 {
            progress = target
            return
        }
        progress += (target - progress) * smoothing
        if abs(target - progress) < 0.0005 { progress = target }
    }

    /// Drops the desktop so the next show waits for a fresh frame.
    public func clearSource() {
        lock.lock()
        pendingPixelBuffer = nil
        source = nil
        lock.unlock()
    }

    /// Uploads any pending frame, then draws the sheet into `target`.
    public func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture, clearColor: MTLClearColor) {
        uploadPendingFrame(commandBuffer: commandBuffer)
        lock.lock()
        let source = source
        lock.unlock()
        guard let source else {
            clear(target, with: clearColor, commandBuffer: commandBuffer)
            return
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = clearColor
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Fold"

        var uniforms = makeUniforms(aspect: Double(target.width) / Double(target.height))
        encoder.setRenderPipelineState(graphics.foldPipeline)
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<FoldUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FoldUniforms>.stride, index: 1)
        encoder.setFragmentTexture(source, index: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint32, indexBuffer: indexBuffer, indexBufferOffset: 0)
        encoder.endEncoding()
    }

    private func makeUniforms(aspect: Double) -> FoldUniforms {
        let p = parameters.clamped()
        return FoldUniforms(
            progress: Float(progress),
            perspective: Float(p.perspective),
            blur: Float(p.blur),
            shadow: Float(p.shadow),
            bend: Float(p.bend),
            frost: Float(p.frost),
            aspect: Float(aspect),
            cornerRadius: Float(cornerRadius),
            cameraDistance: Float(cameraDistance),
            maxTilt: Float(maxTiltDegrees * .pi / 180)
        )
    }

    private func clear(_ target: MTLTexture, with color: MTLClearColor, commandBuffer: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = color
        commandBuffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
    }

    /// Copies the newest captured frame into the mipmapped source texture and rebuilds
    /// its mip chain, so the fragment shader can blur by sampling coarser levels.
    private func uploadPendingFrame(commandBuffer: MTLCommandBuffer) {
        lock.lock()
        guard let pixelBuffer = pendingPixelBuffer else {
            lock.unlock()
            return
        }
        pendingPixelBuffer = nil
        lock.unlock()

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, graphics.textureCache, pixelBuffer, nil,
            FoldGraphics.pixelFormat, width, height, 0, &cvTexture
        )
        guard status == kCVReturnSuccess, let cvTexture, let frame = CVMetalTextureGetTexture(cvTexture) else { return }

        lock.lock()
        if source == nil || source?.width != width || source?.height != height || source?.mipmapLevelCount == 1 {
            source = graphics.makeMipmappedTexture(width: width, height: height, label: "Desktop")
        }
        let source = source
        lock.unlock()
        guard let source, let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.label = "Desktop upload"
        blit.copy(from: frame, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: source, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
        blit.generateMipmaps(for: source)
        blit.endEncoding()
        // Keep the CoreVideo texture alive until the GPU has read it.
        let retained = Retained(cvTexture)
        commandBuffer.addCompletedHandler { _ in _ = retained }
    }
}

/// Holds a reference across a `@Sendable` boundary for an object that is only kept alive, never touched.
private struct Retained: @unchecked Sendable {
    let value: AnyObject
    init(_ value: AnyObject) { self.value = value }
}
