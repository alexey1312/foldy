import Foundation
import IOKit
import IOKit.hid

/// Reads the hinge angle from the MacBook's own lid angle sensor.
///
/// The sensor is a HID device. It is asked for its feature report on a timer that
/// runs fast (60 Hz) while the lid is moving and slows to a heartbeat (4 Hz) once it
/// has settled, and it is also asked to push input reports; if the hardware does,
/// polling drops to the heartbeat and the angle arrives the moment it changes.
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
    private let inputReport = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var lastAngle: Double?
    private var lastMovement: TimeInterval = 0
    private var receivedInputReport = false
    private var pollingFast = true
    private(set) public var availability: Availability = .searching

    private static let fastInterval: TimeInterval = 1.0 / 60.0
    private static let idleInterval: TimeInterval = 1.0 / 4.0
    private static let settleDelay: TimeInterval = 1.2

    public init() {}

    deinit {
        inputReport.deallocate()
    }

    public func start() {
        queue.async { self.startOnQueue() }
    }

    public func stop() {
        queue.async { self.stopOnQueue() }
    }

    // MARK: - Queue-confined

    private func startOnQueue() {
        guard manager == nil else { return }

        if let reason = MacModel.current().reasonWithoutLid {
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

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<LidAngleSensor>.fromOpaque(context).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<LidAngleSensor>.fromOpaque(context).takeUnretainedValue().detach(device)
        }, context)
        IOHIDManagerSetDispatchQueue(manager, queue)
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
            IOHIDDeviceRegisterInputReportCallback(device, inputReport, 64, nil, nil)
            IOHIDDeviceClose(device, options)
        }
        device = nil
        if let manager {
            IOHIDManagerCancel(manager)
        }
        manager = nil
    }

    private func attach(_ device: IOHIDDevice) {
        guard self.device == nil else { return }
        guard IOHIDDeviceOpen(device, options) == kIOReturnSuccess else {
            publish(.unavailable(reason: "The lid angle sensor is there but could not be opened."))
            return
        }
        self.device = device
        searchTimeout?.cancel()

        guard let angle = readFeatureAngle() else {
            IOHIDDeviceClose(device, options)
            self.device = nil
            publish(.unavailable(reason: "The lid angle sensor answered with a report this build does not understand."))
            return
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, inputReport, 64, { context, result, _, _, reportID, report, length in
            guard let context, result == kIOReturnSuccess, reportID == UInt32(LidAngleReport.reportID) else { return }
            let sensor = Unmanaged<LidAngleSensor>.fromOpaque(context).takeUnretainedValue()
            let bytes = UnsafeBufferPointer(start: report, count: length)
            guard let angle = LidAngleReport.angle(in: bytes) else { return }
            sensor.receivedInputReport = true
            sensor.deliver(angle)
        }, context)

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
        publish(.searching)
    }

    private func readFeatureAngle() -> Double? {
        guard let device else { return nil }
        var length = CFIndex(featureReport.count)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, LidAngleReport.reportID, &featureReport, &length)
        guard result == kIOReturnSuccess else { return nil }
        return featureReport.withUnsafeBufferPointer { buffer in
            LidAngleReport.angle(in: UnsafeBufferPointer(rebasing: buffer.prefix(Int(length))))
        }
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
        guard let angle = readFeatureAngle() else { return }
        deliver(angle)
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
