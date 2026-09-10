import CoreVideo
import Foundation
import Metal
import MetalKit
import simd

public enum FoldGraphicsError: Error, LocalizedError {
    case noDevice
    case noCommandQueue
    case shaderCompile(String)
    case textureCache

    public var errorDescription: String? {
        switch self {
        case .noDevice: "No Metal device."
        case .noCommandQueue: "Could not create a Metal command queue."
        case let .shaderCompile(message): "Shader compile failed: \(message)"
        case .textureCache: "Could not create the CoreVideo texture cache."
        }
    }
}

/// The Metal device, pipelines and texture cache shared by every renderer in the process.
public final class FoldGraphics: @unchecked Sendable {
    public static let pixelFormat: MTLPixelFormat = .bgra8Unorm
    public static let depthFormat: MTLPixelFormat = .depth32Float

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    let foldPipeline: MTLRenderPipelineState
    let scenePipeline: MTLRenderPipelineState
    let sceneDepthWrite: MTLDepthStencilState
    let sceneDepthRead: MTLDepthStencilState
    let textureCache: CVMetalTextureCache
    let textureLoader: MTKTextureLoader

    public init(device: MTLDevice? = nil) throws {
        guard let device = device ?? MTLCreateSystemDefaultDevice() else { throw FoldGraphicsError.noDevice }
        guard let queue = device.makeCommandQueue() else { throw FoldGraphicsError.noCommandQueue }
        self.device = device
        commandQueue = queue
        queue.label = "Foldy"

        let library: MTLLibrary
        do {
            let options = MTLCompileOptions()
            options.fastMathEnabled = true
            library = try device.makeLibrary(source: FoldShaders.source, options: options)
        } catch {
            throw FoldGraphicsError.shaderCompile(error.localizedDescription)
        }

        let fold = MTLRenderPipelineDescriptor()
        fold.label = "Fold"
        fold.vertexFunction = library.makeFunction(name: "fold_vertex")
        fold.fragmentFunction = library.makeFunction(name: "fold_fragment")
        fold.colorAttachments[0].pixelFormat = Self.pixelFormat
        Self.enablePremultipliedBlend(fold.colorAttachments[0])
        foldPipeline = try device.makeRenderPipelineState(descriptor: fold)

        let scene = MTLRenderPipelineDescriptor()
        scene.label = "MacBook scene"
        scene.vertexFunction = library.makeFunction(name: "scene_vertex")
        scene.fragmentFunction = library.makeFunction(name: "scene_fragment")
        scene.colorAttachments[0].pixelFormat = Self.pixelFormat
        scene.depthAttachmentPixelFormat = Self.depthFormat
        Self.enablePremultipliedBlend(scene.colorAttachments[0])
        scenePipeline = try device.makeRenderPipelineState(descriptor: scene)

        let depthWrite = MTLDepthStencilDescriptor()
        depthWrite.depthCompareFunction = .lessEqual
        depthWrite.isDepthWriteEnabled = true
        sceneDepthWrite = device.makeDepthStencilState(descriptor: depthWrite)!
        let depthRead = MTLDepthStencilDescriptor()
        depthRead.depthCompareFunction = .lessEqual
        depthRead.isDepthWriteEnabled = false
        sceneDepthRead = device.makeDepthStencilState(descriptor: depthRead)!

        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess, let cache else {
            throw FoldGraphicsError.textureCache
        }
        textureCache = cache
        textureLoader = MTKTextureLoader(device: device)
    }

    private static func enablePremultipliedBlend(_ attachment: MTLRenderPipelineColorAttachmentDescriptor) {
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }

    /// A render-target texture (shader-readable too, so the preview can sample it).
    public func makeTargetTexture(width: Int, height: Int, label: String) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.pixelFormat, width: max(width, 1), height: max(height, 1), mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }

    public func makeDepthTexture(width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.depthFormat, width: max(width, 1), height: max(height, 1), mipmapped: false
        )
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    /// A texture the fold pass can sample at any blur level.
    func makeMipmappedTexture(width: Int, height: Int, label: String) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.pixelFormat, width: max(width, 1), height: max(height, 1), mipmapped: true
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }
}
