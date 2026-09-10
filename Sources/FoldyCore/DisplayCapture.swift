import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

/// Streams the built-in display as BGRA pixel buffers with ScreenCaptureKit.
///
/// The app's own windows are left out of the stream, so the overlay never captures
/// itself. Frames are delivered on a private queue; hand them to the renderer.
public final class DisplayCapture: NSObject, @unchecked Sendable {
    public enum State: Sendable, Equatable {
        case idle
        case starting
        case running
        case failed(String)
    }

    public var onFrame: (@Sendable (CVPixelBuffer) -> Void)?
    public var onState: (@Sendable (State) -> Void)?

    private let queue = DispatchQueue(label: "app.foldy.capture", qos: .userInteractive)
    private var stream: SCStream?
    private var generation = 0
    private(set) public var state: State = .idle

    /// Whether Screen Recording has been granted. Does not prompt.
    public static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Prompts for Screen Recording if it has never been asked. Returns the current answer.
    @discardableResult
    public static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Starts capturing `displayID` at `scale` × its pixel size.
    public func start(displayID: CGDirectDisplayID, scale: Double = 1.0) {
        queue.async {
            guard self.state == .idle || self.state.isFailure else { return }
            self.generation += 1
            let generation = self.generation
            self.set(.starting)
            Task { await self.startStream(displayID: displayID, scale: scale, generation: generation) }
        }
    }

    public func stop() {
        queue.async {
            self.generation += 1
            guard let stream = self.stream else {
                self.set(.idle)
                return
            }
            self.stream = nil
            nonisolated(unsafe) let doomed = stream
            Task {
                try? await doomed.stopCapture()
                self.queue.async { self.set(.idle) }
            }
        }
    }

    private func startStream(displayID: CGDirectDisplayID, scale: Double, generation: Int) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                queue.async { self.set(.failed("No display to capture.")) }
                return
            }
            let pid = ProcessInfo.processInfo.processIdentifier
            let ownApps = content.applications.filter { $0.processID == pid }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

            let configuration = SCStreamConfiguration()
            let pixelWidth = Double(CGDisplayPixelsWide(display.displayID))
            let pixelHeight = Double(CGDisplayPixelsHigh(display.displayID))
            configuration.width = max(Int(pixelWidth * scale), 2)
            configuration.height = max(Int(pixelHeight * scale), 2)
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            configuration.queueDepth = 3
            configuration.showsCursor = true
            configuration.capturesShadowsOnly = false

            nonisolated(unsafe) let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()

            queue.async {
                guard generation == self.generation else {
                    Task { try? await stream.stopCapture() }
                    return
                }
                self.stream = stream
                self.set(.running)
            }
        } catch {
            queue.async { self.set(.failed(error.localizedDescription)) }
        }
    }

    private func set(_ state: State) {
        guard self.state != state else { return }
        self.state = state
        onState?(state)
    }
}

extension DisplayCapture.State {
    public var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

extension DisplayCapture: SCStreamOutput, SCStreamDelegate {
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let pixelBuffer = sampleBuffer.imageBuffer else { return }
        // Idle frames repeat the previous picture; skip them so the renderer keeps its last upload.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let rawStatus = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: rawStatus),
           status != .complete {
            return
        }
        onFrame?(pixelBuffer)
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async {
            self.stream = nil
            self.set(.failed(error.localizedDescription))
        }
    }
}
