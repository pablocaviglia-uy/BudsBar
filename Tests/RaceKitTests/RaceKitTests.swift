import XCTest
@testable import RaceKit

/// Every byte string below was captured from a JBL Tour Pro 3 over RFCOMM channel 21.
/// These tests pin the wire format against real hardware, not against an assumed spec.
final class RaceKitTests: XCTestCase {

    private func bytes(_ hex: String) -> [UInt8] {
        hex.split(separator: " ").map { UInt8($0, radix: 16)! }
    }

    private func singleFrame(_ hex: String, file: StaticString = #filePath, line: UInt = #line) -> RaceFrame {
        var parser = RaceFrameParser()
        let frames = parser.append(bytes(hex))
        XCTAssertEqual(frames.count, 1, file: file, line: line)
        return frames[0]
    }

    // MARK: Encoding

    func testReadNoiseModeMatchesTheFrameTheBudsAnswer() {
        XCTAssertEqual(RaceCommand.readNoiseMode.encoded, bytes("05 5a 04 00 01 09 05 00"))
    }

    func testSetNoiseModeMatchesTheFramesTheBudsAccepted() {
        XCTAssertEqual(RaceCommand.setNoiseMode(.anc).encoded, bytes("05 5a 05 00 06 0e 00 0a 01"))
        XCTAssertEqual(RaceCommand.setNoiseMode(.ambientAware).encoded, bytes("05 5a 05 00 06 0e 00 0a 0a"))
        XCTAssertEqual(RaceCommand.setNoiseMode(.talkThru).encoded, bytes("05 5a 05 00 06 0e 00 0a 09"))
    }

    func testOffHasNoSendableCommand() {
        XCTAssertNil(RaceCommand.setNoiseMode(.off).encoded)
    }

    // MARK: Parsing

    func testConnectBurstSplitsIntoTwoFrames() {
        var parser = RaceFrameParser()
        let frames = parser.append(bytes(
            "05 5c 06 00 01 09 67 00 00 64 05 5d 1e 00 82 00 00 01 01 00 01 01 01 01 01 01 05 03 00 00 00 00 00 00 00 01 01 01 01 01 01 01 01 01"))
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0], RaceFrame(type: 0x5C, opcode: 0x0901, body: bytes("67 00 00 64")))
        XCTAssertEqual(frames[1].type, 0x5D)
        XCTAssertEqual(frames[1].opcode, 0x0082)
        XCTAssertEqual(frames[1].body.count, 28)
    }

    func testFrameCutAcrossChunksAndLeadingNoise() {
        var parser = RaceFrameParser()
        XCTAssertEqual(parser.append(bytes("ff 00 05 5b 09 00 01")), [])
        let frames = parser.append(bytes("09 05 00 00 01 07 00 05"))
        XCTAssertEqual(frames, [RaceFrame(type: 0x5B, opcode: 0x0901, body: bytes("05 00 00 01 07 00 05"))])
    }

    // MARK: Events

    func testReadResponsesForEveryObservedMode() {
        XCTAssertEqual(singleFrame("05 5b 09 00 01 09 05 00 00 00 00 00 06").event, .noiseMode(.off, raw: 0x00))
        XCTAssertEqual(singleFrame("05 5b 09 00 01 09 05 00 00 01 07 00 05").event, .noiseMode(.anc, raw: 0x01))
        XCTAssertEqual(singleFrame("05 5b 09 00 01 09 05 00 00 0a 07 00 06").event, .noiseMode(.ambientAware, raw: 0x0A))
        XCTAssertEqual(singleFrame("05 5b 09 00 01 09 05 00 00 09 00 00 00").event, .noiseMode(.talkThru, raw: 0x09))
    }

    func testIndicationAfterAChangeCarriesTheNewMode() {
        XCTAssertEqual(singleFrame("05 5d 08 00 01 09 05 00 00 01 07 00").event, .noiseMode(.anc, raw: 0x01))
    }

    func testNotificationsSentOnConnectAreNotModes() {
        XCTAssertEqual(singleFrame("05 5c 06 00 01 09 65 00 00 64").event, .other)
    }

    func testSetAcceptedWhileWornAndRejectedOutOfTheEar() {
        XCTAssertEqual(singleFrame("05 5b 08 00 06 0e 00 0a 01 20 11 00").event,
                       .setNoiseModeResult(accepted: true, status: 0x00))
        XCTAssertEqual(singleFrame("05 5b 08 00 06 0e 01 0a 01 00 56 00").event,
                       .setNoiseModeResult(accepted: false, status: 0x01))
    }

    // MARK: Profiles

    func testProfilesMatchTheirBluetoothNames() {
        XCTAssertEqual(DeviceProfile.profile(forDeviceName: "JBL Tour Pro 3")?.id, "jbl-tour-pro-3")
        XCTAssertEqual(DeviceProfile.profile(forDeviceName: "JBL TUNE 770NC")?.id, "jbl-tune-770nc")
        XCTAssertEqual(DeviceProfile.profile(forDeviceName: "JBL Tune 670NC")?.id, "jbl-tune-670nc")
    }

    func testSameModelNumberInAnotherLineDoesNotMatch() {
        XCTAssertNil(DeviceProfile.profile(forDeviceName: "JBL Live 770NC"))
        XCTAssertNil(DeviceProfile.profile(forDeviceName: "JBL Tour Pro 2"))
    }
}
