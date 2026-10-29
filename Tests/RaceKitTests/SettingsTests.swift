import XCTest
@testable import RaceKit

/// Frames from a btsnoop capture of JBL's Android app driving a JBL Tour Pro 3: the commands are
/// the ones the app sent, the replies the ones the earbuds returned.
final class SettingsTests: XCTestCase {

    private func bytes(_ hex: String) -> [UInt8] {
        hex.split(separator: " ").map { UInt8($0, radix: 16)! }
    }

    private func state(after hexFrames: String...) -> DeviceState {
        var parser = RaceFrameParser()
        var state = DeviceState()
        for hex in hexFrames {
            for frame in parser.append(bytes(hex)) { state.apply(frame) }
        }
        return state
    }

    // MARK: Commands match what the official app sent

    func testConfigReads() {
        XCTAssertEqual(RaceCommand.readConfig(.autoPlayPause).encoded, bytes("05 5a 04 00 83 2c 02 00"))
        XCTAssertEqual(RaceCommand.readConfig(.voiceAwareLevel).encoded, bytes("05 5a 04 00 83 2c 06 00"))
        XCTAssertEqual(RaceCommand.readConfig(.voiceAware).encoded, bytes("05 5a 04 00 83 2c 07 00"))
        XCTAssertEqual(RaceCommand.readConfig(.voicePrompts).encoded, bytes("05 5a 04 00 83 2c 09 00"))
    }

    func testConfigWrites() {
        XCTAssertEqual(RaceCommand.writeConfig(.voiceAware(true)).encoded, bytes("05 5a 05 00 82 2c 07 00 01"))
        XCTAssertEqual(RaceCommand.writeConfig(.voiceAware(false)).encoded, bytes("05 5a 05 00 82 2c 07 00 00"))
        XCTAssertEqual(RaceCommand.writeConfig(.voiceAwareLevel(3)).encoded, bytes("05 5a 06 00 82 2c 06 00 03 00"))
        XCTAssertEqual(RaceCommand.writeConfig(.autoPlayPause(false)).encoded, bytes("05 5a 05 00 82 2c 02 00 00"))
        XCTAssertEqual(RaceCommand.writeConfig(.autoPlayPause(true)).encoded, bytes("05 5a 05 00 82 2c 02 00 01"))
        XCTAssertEqual(RaceCommand.writeConfig(.voicePrompts(false)).encoded, bytes("05 5a 05 00 82 2c 09 00 ff"))
        XCTAssertEqual(RaceCommand.writeConfig(.voicePrompts(true)).encoded, bytes("05 5a 05 00 82 2c 09 00 00"))
    }

    func testOutOfRangeValuesAreNotSendable() {
        XCTAssertNil(RaceCommand.writeConfig(.voiceAwareLevel(0)).encoded)
        XCTAssertNil(RaceCommand.writeConfig(.voiceAwareLevel(4)).encoded)
        XCTAssertNil(RaceCommand.setSmartTalk(SmartTalk(isEnabled: true, seconds: 7)).encoded)
    }

    func testSpatialSound() {
        XCTAssertEqual(RaceCommand.readSpatialSound.encoded, bytes("05 5a 09 00 93 00 aa 06 03 00 01 00 2e"))
        XCTAssertEqual(RaceCommand.setSpatialSound(.off).encoded, bytes("05 5a 0c 00 93 00 aa 06 06 00 00 00 2e 02 00 ff"))
        XCTAssertEqual(RaceCommand.setSpatialSound(.fixed).encoded, bytes("05 5a 0c 00 93 00 aa 06 06 00 00 00 2e 02 01 01"))
        XCTAssertEqual(RaceCommand.setSpatialSound(.headTracking).encoded, bytes("05 5a 0c 00 93 00 aa 06 06 00 00 00 2e 02 01 02"))
    }

    func testSmartTalkAndAutoAnswer() {
        XCTAssertEqual(RaceCommand.readSmartTalk.encoded, bytes("05 5a 02 00 60 00"))
        XCTAssertEqual(RaceCommand.setSmartTalk(SmartTalk(isEnabled: true, seconds: 5)).encoded, bytes("05 5a 04 00 61 00 01 05"))
        XCTAssertEqual(RaceCommand.setSmartTalk(SmartTalk(isEnabled: true, seconds: 15)).encoded, bytes("05 5a 04 00 61 00 01 0f"))
        XCTAssertEqual(RaceCommand.setSmartTalk(SmartTalk(isEnabled: true, seconds: 20)).encoded, bytes("05 5a 04 00 61 00 01 14"))
        XCTAssertEqual(RaceCommand.setSmartTalk(SmartTalk(isEnabled: false, seconds: 5)).encoded, bytes("05 5a 04 00 61 00 00 05"))
        XCTAssertEqual(RaceCommand.readAutoAnswer.encoded, bytes("05 5a 02 00 87 00"))
        XCTAssertEqual(RaceCommand.setAutoAnswer(true).encoded, bytes("05 5a 03 00 88 00 01"))
        XCTAssertEqual(RaceCommand.setAutoAnswer(false).encoded, bytes("05 5a 03 00 88 00 00"))
    }

    // MARK: Replies fold into state

    func testBatteryNotificationsMatchWhatTheAppShowed() {
        // The app showed L 100 %, R 99 %, case 100 % when these arrived.
        let s = state(after: "05 5c 06 00 01 09 65 00 00 64", "05 5c 06 00 01 09 66 00 00 63", "05 5c 06 00 01 09 67 00 00 64")
        XCTAssertEqual(s.battery, [.left: 100, .right: 99, .chargingCase: 100])
        XCTAssertNil(s.noiseMode)
    }

    func testBatteryUpdatesReplaceOlderLevels() {
        let s = state(after: "05 5c 06 00 01 09 65 00 00 64", "05 5c 06 00 01 09 65 00 00 61")
        XCTAssertEqual(s.battery[.left], 97)
    }

    func testConfigReplies() {
        let s = state(after: "05 5b 06 00 83 2c 00 02 00 01", "05 5b 06 00 83 2c 00 07 00 00",
                      "05 5b 07 00 83 2c 00 06 00 02 00", "05 5b 06 00 83 2c 00 09 00 00")
        XCTAssertEqual(s.autoPlayPause, true)
        XCTAssertEqual(s.voiceAware, false)
        XCTAssertEqual(s.voiceAwareLevel, 2)
        XCTAssertEqual(s.voicePrompts, true)
    }

    func testUnknownConfigIdIsIgnored() {
        XCTAssertEqual(state(after: "05 5b 08 00 83 2c 00 13 00 00 04 08"), DeviceState())
    }

    func testSpatialSoundReplies() {
        XCTAssertEqual(state(after: "05 5b 0d 00 93 00 00 aa 06 06 00 02 00 2e 02 00 ff").spatialSound, .off)
        XCTAssertEqual(state(after: "05 5b 0d 00 93 00 00 aa 06 06 00 02 00 2e 02 01 01").spatialSound, .fixed)
        XCTAssertEqual(state(after: "05 5b 0d 00 93 00 00 aa 06 06 00 02 00 2e 02 01 02").spatialSound, .headTracking)
        // Another id in the same tunnel is not Spatial Sound.
        XCTAssertNil(state(after: "05 5b 0c 00 93 00 00 aa 06 05 00 02 00 17 01 01").spatialSound)
    }

    func testSmartTalkAndAutoAnswerReplies() {
        XCTAssertEqual(state(after: "05 5b 05 00 60 00 00 00 00").smartTalk, SmartTalk(isEnabled: false, seconds: 0))
        XCTAssertEqual(state(after: "05 5b 04 00 87 00 00 00").autoAnswer, false)
        XCTAssertEqual(state(after: "05 5b 04 00 88 00 00 01").autoAnswer, true)
    }

    func testWriteRepliesReportTheirStatus() {
        var parser = RaceFrameParser()
        XCTAssertEqual(parser.append(bytes("05 5b 05 00 82 2c 00 07 00")).first?.event, .settingWriteResult(accepted: true, status: 0))
        XCTAssertEqual(parser.append(bytes("05 5b 03 00 61 00 00")).first?.event, .settingWriteResult(accepted: true, status: 0))
        XCTAssertEqual(parser.append(bytes("05 5b 04 00 88 00 00 01")).first?.event, .settingWriteResult(accepted: true, status: 0))
    }

    func testOnlyTheTourPro3HasTheExtraFeatures() {
        XCTAssertEqual(DeviceProfile.profile(forDeviceName: "JBL Tour Pro 3")?.features, Set(DeviceProfile.Feature.allCases))
        XCTAssertEqual(DeviceProfile.profile(forDeviceName: "JBL Tune 770NC")?.features, [])
    }
}
