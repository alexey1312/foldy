import Foundation
import IOKit
import IOKit.hid

/// Reads the hinge angle from the MacBook's own lid angle sensor.
///
/// The sensor is a HID device. It is asked for its feature report on a timer that
/// runs fast (60 Hz) while the lid is moving and slows to a heartbeat (10 Hz) once it
/// has settled, and it is also asked to push input reports; if the hardware does,
/// polling stays at the heartbeat and the angle arrives the moment it changes.
///
/// All work happens on a private queue. Callbacks are delivered on that queue.
public final class LidAngleSensor: @unchecked Sendable {
    public enum Availability: Sendable, Equatable {
        case searching
        case available
        case unavailable(reason: String)

        public var isAvailable: Bool {
            if case .available = self { return true }
            return false
        }
    }

    public var onAngle: (@Sendable (Double) -> Void)?
    public var onAvailability: (@Sendable (Availability) -> Void)?

    private let queue = DispatchQueue(label: "app.foldy.lid-sensor", qos: .userInteractive)
    private let options = IOOptionBits(kIOHIDOptionsTypeNone)
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var timer: DispatchSourceTimer?
    private var searchTimeout: DispatchWorkItem?
    private var featureReport = [UInt8](repeating: 0, count: LidAngleReport.reportLength)
    private var lastAngle: Double?
    private var lastMovement: TimeInterval = 0
    private var receivedInputReport = false
    private var pollingFast = true
    private var stopping = false
    private var restartWanted = false
    private var failedReads = 0
    private(set) public var availability: Availability = .searching

    private static let fastInterval: TimeInterval = 1.0 / 60.0
    private static let idleInterval: TimeInterval = 1.0 / 10.0
    private static let settleDelay: TimeInterval = 1.2
    /// Consecutive unanswered feature reports before the sensor is called lost. At the
    /// 10 Hz heartbeat that is two seconds of silence — long enough to ride out a hiccup,
    /// short enough that the menu bar stops reporting an angle that has stopped moving.
    private static let maxFailedReads = 20

    public init() {}

    public func start() {
        queue.async { self.startOnQueue() }
    }

    /// Cancels the HID manager. The sensor stays alive until IOKit confirms the
    /// cancellation, then lets go of itself; callbacks can never reach a freed object.
    public func stop() {
        queue.async { self.stopOnQueue() }
    }

    // MARK: - Queue-confined

    private func startOnQueue() {
        guard manager == nil else {
            // A cancel is still in flight; the cancel handler will start us again.
            restartWanted = stopping
            return
        }
        stopping = false
        restartWanted = false
        failedReads = 0

        if let reason = MacModel.current.reasonWithoutLid {
            publish(.unavailable(reason: reason))
            // Keep looking anyway: the model table is a hint, the HID probe is the truth.
        }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, options)
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: LidAngleReport.vendorID,
            kIOHIDProductIDKey as String: LidAngleReport.productID,
            kIOHIDPrimaryUsagePageKey as String: LidAngleReport.usagePage,
            kIOHIDPrimaryUsageKey as String: LidAngleReport.usage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        // The manager holds a strong reference to the sensor until its cancel handler
        // runs, so the raw context pointer in the C callbacks is always valid.
        let retained = Unmanaged.passRetained(self)
        let context = retained.toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<LidAngleSensor>.fromOpaque(context).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<LidAngleSensor>.fromOpaque(context).takeUnretainedValue().detach(device)
        }, context)
        // Input reports must be registered on the manager before it is activated;
        // devices it matches are scheduled with it and must not be registered again.
        IOHIDManagerRegisterInputReportCallback(manager, { context, result, _, _, reportID, report, length in
            guard let context, result == kIOReturnSuccess, reportID == UInt32(LidAngleReport.reportID) else { return }
            let sensor = Unmanaged<LidAngleSensor>.fromOpaque(context).takeUnretainedValue()
            guard let angle = LidAngleReport.angle(in: UnsafeBufferPointer(start: report, count: length)) else { return }
            sensor.receivedInputReport = true
            sensor.deliver(angle)
        }, context)
        IOHIDManagerSetCancelHandler(manager) {
            // Runs on the queue once IOKit has stopped calling back. Only now may the
            // manager be released and the sensor let go of.
            let sensor = retained.takeUnretainedValue()
            sensor.manager = nil
            sensor.stopping = false
            let restart = sensor.restartWanted
            sensor.restartWanted = false
            retained.release()
            if restart { sensor.startOnQueue() }
        }
        IOHIDManagerSetDispatchQueue(manager, queue)
        // Open before activating so matched devices are usable from the callback.
        // A device that fails to open is reported in attach(); the manager's own
        // result is not decisive, so it is not checked here.
        IOHIDManagerOpen(manager, options)
        IOHIDManagerActivate(manager)
        self.manager = manager

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, device == nil, availability == .searching else { return }
            publish(.unavailable(reason: "No lid angle sensor found on this Mac."))
        }
        searchTimeout = timeout
        queue.asyncAfter(deadline: .now() + 2.5, execute: timeout)
    }

    private func stopOnQueue() {
        timer?.cancel()
        timer = nil
        searchTimeout?.cancel()
        if let device {
            IOHIDDeviceClose(device, options)
        }
        device = nil
        lastAngle = nil
        lastMovement = 0
        receivedInputReport = false
        pollingFast = true
        failedReads = 0
        if let manager {
            stopping = true
            IOHIDManagerClose(manager, options)
            IOHIDManagerCancel(manager) // the cancel handler clears `manager`
        }
    }

    private func attach(_ device: IOHIDDevice) {
        guard self.device == nil else { return }
        guard IOHIDDeviceOpen(device, options) == kIOReturnSuccess else {
            publish(.unavailable(reason: "The lid angle sensor is there but could not be opened."))
            return
        }
        self.device = device
        searchTimeout?.cancel()

        let angle: Double
        switch readFeature() {
        case let .angle(value):
            angle = value
        case let .ioError(result):
            IOHIDDeviceClose(device, options)
            self.device = nil
            let code = String(UInt32(bitPattern: result), radix: 16)
            FoldyLog.sensor.error("IOHIDDeviceGetReport failed with 0x\(code, privacy: .public)")
            publish(.unavailable(reason: "The lid angle sensor refused to answer (IOKit 0x\(code))."))
            return
        case let .unparsable(length):
            IOHIDDeviceClose(device, options)
            self.device = nil
            FoldyLog.sensor.error("unparsable lid report, \(length) bytes: \(self.reportBytes(length), privacy: .public)")
            publish(.unavailable(reason: "The lid angle sensor answered with a \(length)-byte report this build does not understand."))
            return
        }

        failedReads = 0
        publish(.available)
        deliver(angle)
        startPolling()
    }

    private func detach(_ removed: IOHIDDevice) {
        guard let device, device == removed else { return }
        timer?.cancel()
        timer = nil
        IOHIDDeviceClose(device, options)
        self.device = nil
        receivedInputReport = false
        failedReads = 0
        publish(.searching)
        // Without this the app says "Looking for the lid sensor…" for the rest of the
        // session when a device goes away and never comes back.
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, device == nil, availability == .searching else { return }
            publish(.unavailable(reason: "The lid angle sensor stopped answering."))
        }
        searchTimeout = timeout
        queue.asyncAfter(deadline: .now() + 2.5, execute: timeout)
    }

    /// One feature report, with the reason it failed kept — "no answer" and "an answer
    /// this build cannot parse" send a bug report in completely different directions.
    private enum ReadOutcome {
        case angle(Double)
        case ioError(IOReturn)
        case unparsable(Int)
    }

    private func readFeature() -> ReadOutcome {
        guard let device else { return .ioError(kIOReturnNoDevice) }
        var length = CFIndex(featureReport.count)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, LidAngleReport.reportID, &featureReport, &length)
        guard result == kIOReturnSuccess else { return .ioError(result) }
        let angle = featureReport.withUnsafeBufferPointer { buffer in
            LidAngleReport.angle(in: UnsafeBufferPointer(rebasing: buffer.prefix(Int(length))))
        }
        guard let angle else { return .unparsable(Int(length)) }
        return .angle(angle)
    }

    private func reportBytes(_ length: Int) -> String {
        featureReport.prefix(max(min(length, featureReport.count), 0)).map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    private func startPolling() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.schedule(deadline: .now(), repeating: Self.fastInterval, leeway: .milliseconds(2))
        timer.activate()
        self.timer = timer
        pollingFast = true
    }

    private func poll() {
        switch readFeature() {
        case let .angle(angle):
            if failedReads > 0 {
                failedReads = 0
                publish(.available)
            }
            deliver(angle)
        case let .ioError(result):
            noteFailedRead(detail: "0x" + String(UInt32(bitPattern: result), radix: 16))
        case let .unparsable(length):
            noteFailedRead(detail: "\(length) unparsable bytes")
        }
    }

    /// A silent or unreadable sensor must not leave the menu bar reporting the angle it
    /// froze at; say it is lost instead, and let a good read take it back.
    private func noteFailedRead(detail: String) {
        failedReads += 1
        guard failedReads == Self.maxFailedReads else { return }
        FoldyLog.sensor.error("lid sensor stopped answering (\(detail, privacy: .public))")
        publish(.unavailable(reason: "Lost contact with the lid angle sensor (\(detail))."))
    }

    private func deliver(_ angle: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        if let lastAngle, abs(lastAngle - angle) < 0.5 {
            // Settled. Drop to the heartbeat once nothing has moved for a while.
            if pollingFast, now - lastMovement > Self.settleDelay {
                setPollingInterval(Self.idleInterval)
            }
            return
        }
        lastAngle = angle
        lastMovement = now
        // Input reports make the fast poll redundant; the heartbeat only guards against
        // a report that never came.
        if !pollingFast, !receivedInputReport {
            setPollingInterval(Self.fastInterval)
        }
        onAngle?(angle)
    }

    private func setPollingInterval(_ interval: TimeInterval) {
        pollingFast = interval == Self.fastInterval
        timer?.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(2))
    }

    private func publish(_ availability: Availability) {
        guard self.availability != availability else { return }
        self.availability = availability
        onAvailability?(availability)
    }
}
