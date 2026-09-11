import Foundation
import Metal
import simd

/// Mirrors `SceneUniforms` in the shader.
struct SceneUniforms {
    var mvp: simd_float4x4
    var model: simd_float4x4
    var color: SIMD4<Float>
    var params: SIMD4<Float>
    var params2: SIMD4<Float>
    var eye: SIMD4<Float>
}

/// A small 3D MacBook whose lid opens and closes, with the folding desktop on its screen.
///
/// This is the preview in Settings and the "drag to open and close" demo. The screen
/// content is rendered by the same `FoldRenderer` the overlay uses, into a texture,
/// so what the preview shows is exactly what the lid will show.
public final class MacBookScene: @unchecked Sendable {
    public let graphics: FoldGraphics
    public let fold: FoldRenderer

    /// Hinge angle the lid is heading to, in degrees. 0 closed, 135 fully open.
    public var targetLidAngle: Double = FoldCurve.fullyOpenAngle
    /// Hinge angle now, after smoothing.
    public private(set) var lidAngle: Double = FoldCurve.fullyOpenAngle
    /// Lerp factor for the lid per 1/60 s. 1 disables smoothing.
    public var smoothing: Double = 0.14
    public var curve: FoldCurve = .default
    /// Background behind the MacBook. Set to the window colour so it blends in.
    public var backgroundColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

    // Geometry, in units of lid height.
    public static let screenAspect: Double = 1.54
    static let bezelSide = 0.045
    static let bezelBottom = 0.055
    static let bezelTop = 0.045
    static let lidWidth = Float(screenAspect + 2 * bezelSide)
    static let lidHeight = Float(1 + bezelBottom + bezelTop)
    static let baseDepth: Float = 0.74
    static let baseWidth: Float = lidWidth * 1.01
    static let baseThickness: Float = 0.03

    private let quadBuffer: MTLBuffer
    private var foldTexture: MTLTexture?
    private var depthTexture: MTLTexture?

    public init(graphics: FoldGraphics) throws {
        self.graphics = graphics
        fold = try FoldRenderer(graphics: graphics)
        fold.smoothing = 1 // the lid is what gets smoothed; the fold follows it exactly
        let quad: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(0, 1), SIMD2(1, 0),
            SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1),
        ]
        guard let buffer = graphics.device.makeBuffer(bytes: quad, length: quad.count * MemoryLayout<SIMD2<Float>>.stride) else {
            throw FoldGraphicsError.noDevice
        }
        buffer.label = "Scene quad"
        quadBuffer = buffer
    }

    /// Puts the lid at `angle` at once, without easing.
    public func lidAngleJump(to angle: Double) {
        targetLidAngle = angle
        lidAngle = angle
        fold.targetProgress = curve.progress(forAngle: angle)
        fold.step()
    }

    /// True once the lid and the fold have reached their targets; nothing will change
    /// until a new target is set, so a view can stop redrawing.
    public var isSettled: Bool {
        lidAngle == targetLidAngle && fold.progress == fold.targetProgress
    }

    public func step() {
        if smoothing >= 1 {
            lidAngle = targetLidAngle
        } else {
            lidAngle += (targetLidAngle - lidAngle) * smoothing
            if abs(targetLidAngle - lidAngle) < 0.02 { lidAngle = targetLidAngle }
        }
        fold.targetProgress = curve.progress(forAngle: lidAngle)
        fold.step()
    }

    /// Renders the fold to its texture, then the MacBook into `target`.
    /// `depth` must match `target` in size; pass `nil` to let the scene own one.
    public func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture, depth: MTLTexture?) {
        let foldWidth = 1024
        let foldHeight = Int(Double(foldWidth) / Self.screenAspect)
        if foldTexture == nil {
            foldTexture = graphics.makeTargetTexture(width: foldWidth, height: foldHeight, label: "Preview fold")
        }
        guard let foldTexture else { return }
        fold.encode(into: commandBuffer, target: foldTexture, clearColor: MTLClearColor(red: 0.07, green: 0.07, blue: 0.075, alpha: 1))

        let depthTarget: MTLTexture
        if let depth {
            depthTarget = depth
        } else {
            if depthTexture == nil || depthTexture?.width != target.width || depthTexture?.height != target.height {
                depthTexture = graphics.makeDepthTexture(width: target.width, height: target.height)
            }
            guard let depthTexture else { return }
            depthTarget = depthTexture
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = backgroundColor
        pass.depthAttachment.texture = depthTarget
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "MacBook"
        encoder.setRenderPipelineState(graphics.scenePipeline)
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(quadBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(foldTexture, index: 0)

        let aspect = Float(target.width) / Float(target.height)
        let camera = Self.camera(viewportAspect: aspect)
        let hinge = SIMD3<Float>(0, Self.baseThickness, 0)
        let angle = Float(lidAngle) * .pi / 180

        // Ground shadow, then base, then the lid's back and front.
        var shadow = SceneUniforms(
            mvp: .identity, model: .identity,
            color: SIMD4(0, 0, 0, 0.32),
            params: SIMD4(2, Self.baseWidth * 1.45, 0, Self.baseDepth * 1.9),
            params2: .zero, eye: camera.eye
        )
        shadow.model = .translation(SIMD3(0, 0.001, -Self.baseDepth * 0.45)) * .rotationX(.pi / 2)
        shadow.mvp = camera.viewProjection * shadow.model
        encoder.setDepthStencilState(graphics.sceneDepthRead)
        draw(encoder, &shadow)

        var base = SceneUniforms(
            mvp: .identity, model: .identity,
            color: SIMD4(0.55, 0.56, 0.58, 1),
            params: SIMD4(0, Self.baseWidth, 0.035, Self.baseDepth),
            params2: .zero, eye: camera.eye
        )
        base.model = .translation(hinge) * .rotationX(.pi / 2)
        base.mvp = camera.viewProjection * base.model
        encoder.setDepthStencilState(graphics.sceneDepthWrite)
        draw(encoder, &base)

        let lidModel = simd_float4x4.translation(hinge) * .rotationX(.pi / 2 - angle)
        var lidBack = SceneUniforms(
            mvp: .identity, model: lidModel * .translation(SIMD3(0, 0, -0.018)),
            color: SIMD4(0.58, 0.59, 0.61, 1),
            params: SIMD4(3, Self.lidWidth, 0.075, Self.lidHeight),
            params2: .zero, eye: camera.eye
        )
        lidBack.mvp = camera.viewProjection * lidBack.model
        draw(encoder, &lidBack)

        var lid = SceneUniforms(
            mvp: camera.viewProjection * lidModel, model: lidModel,
            color: SIMD4(0.58, 0.59, 0.61, 1),
            params: SIMD4(1, Self.lidWidth, 0.075, Self.lidHeight),
            params2: SIMD4(
                Float(Self.bezelSide) / Self.lidWidth,
                Float(Self.bezelBottom) / Self.lidHeight,
                Float(Self.bezelTop) / Self.lidHeight,
                0.27
            ),
            eye: camera.eye
        )
        draw(encoder, &lid)

        encoder.endEncoding()
    }

    private func draw(_ encoder: MTLRenderCommandEncoder, _ uniforms: inout SceneUniforms) {
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<SceneUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SceneUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }

    private struct Camera {
        var viewProjection: simd_float4x4
        var eye: SIMD4<Float>
    }

    private static func camera(viewportAspect: Float) -> Camera {
        let eye = SIMD3<Float>(0, 0.95, 3.6)
        let center = SIMD3<Float>(0, 0.5, 0.05)
        let view = simd_float4x4.lookAt(eye: eye, center: center, up: SIMD3(0, 1, 0))
        // 24° vertical fits the open lid and the deck in a 1.56:1 viewport with a little
        // air. Narrower viewports keep that horizontal extent instead, so the MacBook
        // is never cropped at the sides (the app icon is square).
        let baseFovy: Float = 24 * .pi / 180
        let baseAspect: Float = 1.56
        let fovy = viewportAspect >= baseAspect
            ? baseFovy
            : 2 * atan(tan(baseFovy / 2) * baseAspect / viewportAspect)
        let projection = simd_float4x4.perspective(fovyRadians: fovy, aspect: viewportAspect, near: 0.1, far: 20)
        return Camera(viewProjection: projection * view, eye: SIMD4(eye, 1))
    }
}

extension simd_float4x4 {
    static let identity = matrix_identity_float4x4

    static func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(t.x, t.y, t.z, 1)
        return m
    }

    /// Rotation about the x axis. Positive angles turn +y toward +z.
    static func rotationX(_ angle: Float) -> simd_float4x4 {
        let c = cos(angle), s = sin(angle)
        return simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0),
            SIMD4(0, c, s, 0),
            SIMD4(0, -s, c, 0),
            SIMD4(0, 0, 0, 1)
        ))
    }

    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = normalize(eye - center)
        let x = normalize(cross(up, z))
        let y = cross(z, x)
        return simd_float4x4(columns: (
            SIMD4(x.x, y.x, z.x, 0),
            SIMD4(x.y, y.y, z.y, 0),
            SIMD4(x.z, y.z, z.z, 0),
            SIMD4(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        ))
    }

    /// Right-handed perspective projection with Metal's 0…1 depth range.
    static func perspective(fovyRadians: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let ys = 1 / tan(fovyRadians * 0.5)
        let xs = ys / aspect
        let zs = far / (near - far)
        return simd_float4x4(columns: (
            SIMD4(xs, 0, 0, 0),
            SIMD4(0, ys, 0, 0),
            SIMD4(0, 0, zs, -1),
            SIMD4(0, 0, near * zs, 0)
        ))
    }
}
