/// Everything the app knows about the earbuds, folded from the frames they send.
/// A nil field means "not read yet".
public struct DeviceState: Equatable, Sendable {
    public var noiseMode: NoiseMode?
    public var rawNoiseMode: UInt8?
    public var battery: [EarbudSide: Int] = [:]
    public var spatialSound: SpatialSound?
    public var voiceAware: Bool?
    public var voiceAwareLevel: Int?
    public var voicePrompts: Bool?
    public var autoPlayPause: Bool?
    public var autoAnswer: Bool?
    public var smartTalk: SmartTalk?

    public init() {}

    public mutating func apply(_ frame: RaceFrame) {
        let body = frame.body
        let isResponse = frame.type == RaceFrameType.response.rawValue

        switch frame.opcode {
        case RaceOpcode.readNoiseMode:
            // Battery arrives unprompted as 0x5C notifications: `<side> 00 00 <percent>`,
            // on connect and whenever a level changes.
            if frame.type == RaceFrameType.notification.rawValue, body.count >= 4,
               let side = EarbudSide(rawValue: body[0]) {
                battery[side] = Int(body[3])
            } else if case .noiseMode(let mode, let raw) = frame.event {
                noiseMode = mode
                rawNoiseMode = raw
            }

        case RaceOpcode.readConfig where isResponse:
            // `00 <id u16> <value>`
            guard body.count >= 4, body[0] == 0x00,
                  let setting = ConfigSetting(rawValue: UInt16(body[1]) | UInt16(body[2]) << 8) else { return }
            let value = Array(body[3...])
            switch setting {
            case .autoPlayPause: autoPlayPause = value[0] == 0x01
            case .voiceAware: voiceAware = value[0] == 0x01
            case .voicePrompts: voicePrompts = value[0] == 0x00
            case .voiceAwareLevel: voiceAwareLevel = Int(value[0]) | (value.count > 1 ? Int(value[1]) << 8 : 0)
            }

        case RaceOpcode.jblTunnel where isResponse:
            // `00 aa 06 06 00 02 00 <id> 02 <v1 v2>`, both for reads and as the echo of a set.
            guard body.count >= 11, body[0] == 0x00, body[1] == 0xAA, body[2] == 0x06,
                  body[7] == RaceCommand.spatialSoundID, body[8] == 0x02 else { return }
            spatialSound = SpatialSound(wire: [body[9], body[10]])

        case RaceOpcode.readSmartTalk where isResponse:
            // `00 <enabled> <seconds>`
            guard body.count >= 3, body[0] == 0x00 else { return }
            smartTalk = SmartTalk(isEnabled: body[1] == 0x01, seconds: body[2])

        case RaceOpcode.readAutoAnswer where isResponse, RaceOpcode.setAutoAnswer where isResponse:
            // `00 <value>`; the set reply echoes the new value.
            guard body.count >= 2, body[0] == 0x00 else { return }
            autoAnswer = body[1] == 0x01

        default:
            break
        }
    }
}
