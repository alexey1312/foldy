import AVFoundation
import Foundation

/// The soft click that plays when the lid opens and the desktop clears.
///
/// Synthesised on the spot, so the app ships no audio file: a short 1.8 kHz ping with
/// a burst of noise, both dying away in under a tenth of a second.
public final class FoldSound: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let buffer: AVAudioPCMBuffer?
    private let lock = NSLock()

    public var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    public init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        buffer = Self.makeClick(format: format)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.volume = 0.5
        // The first start() negotiates with the audio HAL and costs tens of milliseconds.
        // click() is called from evaluate(), on the main thread, on the last frames of the
        // fold — the worst possible place for that. Pay it at launch, off the main thread.
        DispatchQueue.global(qos: .utility).async { [engine, lock] in
            lock.lock()
            defer { lock.unlock() }
            engine.prepare()
            do { try engine.start() } catch {
                FoldyLog.app.error("audio engine would not start: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func click() {
        lock.lock()
        defer { lock.unlock() }
        guard let buffer else { return }
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            FoldyLog.app.error("audio engine would not start: \(error.localizedDescription, privacy: .public)")
            return
        }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    private static func makeClick(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frames = AVAudioFrameCount(sampleRate * 0.085)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        var seed: UInt32 = 0x9E37_79B9
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Double(seed >> 8) / Double(1 << 24) * 2 - 1
            let attack = min(t / 0.0015, 1)
            let ping = sin(2 * .pi * 1_800 * t) * exp(-t * 55) * 0.55
            let tick = noise * exp(-t * 260) * 0.45
            let body = sin(2 * .pi * 420 * t) * exp(-t * 40) * 0.25
            samples[i] = Float((ping + tick + body) * attack)
        }
        return buffer
    }
}
