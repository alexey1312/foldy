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
                do {
                    try await doomed.stopCapture()
                } catch {
                    // The stream may well still be live; say so rather than leaving the
                    // screen recording indicator lit with no explanation anywhere.
                    FoldyLog.capture.error("stopCapture failed: \(error.localizedDescription, privacy: .public)")
                }
                self.queue.async {
                    // A start that raced this stop owns the state now: its stream is either
                    // assigned already or still starting. Publishing .idle over it would tell
                    // the app to start a third one and drop the second, live, unstoppable.
                    guard self.stream == nil, self.state != .starting else { return }
                    self.set(.idle)
                }
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
            // SCDisplay.width and CGDisplayPixelsWide report points on Retina displays;
            // the display mode carries the real pixel size.
            let mode = CGDisplayCopyDisplayMode(display.displayID)
            let pixelWidth = Double(mode?.pixelWidth ?? CGDisplayPixelsWide(display.displayID))
            let pixelHeight = Double(mode?.pixelHeight ?? CGDisplayPixelsHigh(display.displayID))
            configuration.width = max(Int(pixelWidth * scale), 2)
            configuration.height = max(Int(pixelHeight * scale), 2)
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            configuration.queueDepth = 3
            // The real cursor stays above the overlay; a captured copy would double it.
            configuration.showsCursor = false
            configuration.capturesShadowsOnly = false

            nonisolated(unsafe) let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()

            queue.async {
                guard generation == self.generation else {
                    FoldyLog.capture.notice("stream superseded before it went live; stopping it")
                    Task {
                        try? await stream.stopCapture()
                        try? stream.removeStreamOutput(self, type: .screen)
                    }
                    return
                }
                self.stream = stream
                self.set(.running)
            }
        } catch {
            let message = error.localizedDescription
            FoldyLog.capture.error("startCapture failed: \(message, privacy: .public)")
            queue.async {
                // A stop() that raced this start already put the state back to idle.
                guard generation == self.generation else { return }
                self.set(.failed(message))
            }
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
        let message = error.localizedDescription
        FoldyLog.capture.error("stream stopped: \(message, privacy: .public)")
        nonisolated(unsafe) let stopped = stream
        queue.async {
            // A stream that was already replaced or stopped has nothing to report.
            guard self.stream === stopped else { return }
            self.stream = nil
            self.set(.failed(message))
        }
    }
}
