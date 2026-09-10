import Foundation

/// The wire format of the lid angle sensor.
///
/// Apple silicon MacBooks (and the 2019 16-inch MacBook Pro) expose the hinge as a HID
/// device, vendor 0x05AC product 0x8104, on the Sensor usage page (0x20) with the
/// Orientation usage (0x8A). Feature report 1 carries the angle: byte 0 is the report ID,
/// bytes 1–2 a little-endian unsigned integer in whole degrees, 0 closed, ~135 open.
/// The layout is documented by the community, most thoroughly in
/// samhenrigold/LidAngleSensor.
public enum LidAngleReport {
    public static let vendorID = 0x05AC
    public static let productID = 0x8104
    public static let usagePage = 0x0020
    public static let usage = 0x008A
    public static let reportID: CFIndex = 1
    public static let reportLength = 8

    /// Parses an angle out of a feature or input report. `nil` when the report is too
    /// short or the value is outside anything a hinge can do.
    public static func angle(in bytes: UnsafeBufferPointer<UInt8>) -> Double? {
        guard bytes.count >= 3 else { return nil }
        let raw = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
        guard raw <= 360 else { return nil }
        return Double(raw)
    }

    public static func angle(in bytes: [UInt8]) -> Double? {
        bytes.withUnsafeBufferPointer { angle(in: $0) }
    }
}

/// What this Mac is, and whether it can be expected to carry the sensor.
public struct MacModel: Sendable, Equatable {
    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }

    /// This Mac. Read once; `hw.model` does not change while the process runs.
    public static let current: MacModel = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buffer = [UInt8](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        let identifier = String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
        return MacModel(identifier: identifier)
    }()

    /// A one-line reason the sensor is missing, or `nil` when the model might have one.
    /// Only the certain cases are listed; the HID probe has the final say.
    public var reasonWithoutLid: String? {
        let id = identifier
        if id.hasPrefix("Macmini") || id.hasPrefix("MacPro") || id.hasPrefix("iMac") {
            return "This is a desktop Mac. It has no lid."
        }
        // Mac Studio (M1, M2), Mac mini (M2, M4 Pro), Mac Pro (M2), iMac (M3, M4).
        // Anything not listed is left to the HID probe.
        let desktops: Set<String> = [
            "Mac13,1", "Mac13,2", "Mac14,3", "Mac14,8", "Mac14,12", "Mac14,13", "Mac14,14",
            "Mac15,4", "Mac15,5", "Mac16,2", "Mac16,3", "Mac16,11",
        ]
        if desktops.contains(id) {
            return "This is a desktop Mac. It has no lid."
        }
        if id.hasPrefix("MacBookAir") {
            return "Only MacBook Air models from M2 (2022) onward have a lid angle sensor."
        }
        if id.hasPrefix("MacBookPro") {
            let withSensor: Set<String> = [
                "MacBookPro16,1", "MacBookPro16,4",
                "MacBookPro18,1", "MacBookPro18,2", "MacBookPro18,3", "MacBookPro18,4",
            ]
            if !withSensor.contains(id) {
                return "This MacBook Pro has no lid angle sensor; the 2019 16-inch and the 2021 14- and 16-inch onward do."
            }
        }
        return nil
    }
}
