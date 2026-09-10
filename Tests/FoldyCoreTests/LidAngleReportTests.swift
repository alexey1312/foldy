import Testing
@testable import FoldyCore

@Suite("LidAngleReport")
struct LidAngleReportTests {
    @Test("reads a little-endian angle after the report ID")
    func parsesAngle() {
        #expect(LidAngleReport.angle(in: [0x01, 0x87, 0x00, 0, 0, 0, 0, 0]) == 135)
        #expect(LidAngleReport.angle(in: [0x01, 0x00, 0x00]) == 0)
        #expect(LidAngleReport.angle(in: [0x01, 0x2C, 0x01]) == 300)
    }

    @Test("rejects short or absurd reports")
    func rejects() {
        #expect(LidAngleReport.angle(in: [0x01, 0x40]) == nil)
        #expect(LidAngleReport.angle(in: []) == nil)
        #expect(LidAngleReport.angle(in: [0x01, 0xFF, 0xFF]) == nil)
    }
}

@Suite("MacModel")
struct MacModelTests {
    @Test("desktops are called out")
    func desktops() {
        #expect(MacModel(identifier: "Mac16,11").reasonWithoutLid != nil)
        #expect(MacModel(identifier: "Macmini9,1").reasonWithoutLid != nil)
        #expect(MacModel(identifier: "iMac21,1").reasonWithoutLid != nil)
    }

    @Test("laptops that carry the sensor are left to the probe")
    func laptops() {
        #expect(MacModel(identifier: "Mac16,1").reasonWithoutLid == nil)
        #expect(MacModel(identifier: "MacBookPro18,3").reasonWithoutLid == nil)
        #expect(MacModel(identifier: "Mac14,2").reasonWithoutLid == nil)
    }

    @Test("old laptops are called out")
    func oldLaptops() {
        #expect(MacModel(identifier: "MacBookPro15,1").reasonWithoutLid != nil)
        #expect(MacModel(identifier: "MacBookAir10,1").reasonWithoutLid != nil)
    }
}
