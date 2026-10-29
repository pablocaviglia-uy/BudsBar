enum RaceOpcode {
    static let readNoiseMode: UInt16 = 0x0901
    static let setNoiseMode: UInt16 = 0x0E06
    static let readConfig: UInt16 = 0x2C83
    static let writeConfig: UInt16 = 0x2C82
    /// Tunnel for JBL's own "AA" command set, carried inside RACE.
    static let jblTunnel: UInt16 = 0x0093
    static let readSmartTalk: UInt16 = 0x0060
    static let setSmartTalk: UInt16 = 0x0061
    static let readAutoAnswer: UInt16 = 0x0087
    static let setAutoAnswer: UInt16 = 0x0088
}

/// The complete set of frames this app can send. Anything else RACE offers (memory and flash
/// access, firmware update, factory reset, the EQ's persistent filter writes) is deliberately
/// unrepresentable here: on unpatched Airoha firmware those commands are unauthenticated and can
/// brick the device. Parameters are range-checked; out-of-range values encode to nil.
public enum RaceCommand: Equatable, Sendable {
    case readNoiseMode
    case setNoiseMode(NoiseMode)
    case readConfig(ConfigSetting)
    case writeConfig(ConfigValue)
    case readSpatialSound
    case setSpatialSound(SpatialSound)
    case readSmartTalk
    case setSmartTalk(SmartTalk)
    case readAutoAnswer
    case setAutoAnswer(Bool)

    /// JBL "AA" config id for Spatial Sound, inside the 0x0093 tunnel.
    static let spatialSoundID: UInt8 = 0x2E

    /// Wire bytes, or nil for a command that was never verified on hardware.
    public var encoded: [UInt8]? {
        switch self {
        case .readNoiseMode:
            return RaceFrame.encodeCommand(opcode: RaceOpcode.readNoiseMode, payload: [0x05, 0x00])
        case .setNoiseMode(let mode):
            guard NoiseMode.settable.contains(mode) else { return nil }
            return RaceFrame.encodeCommand(opcode: RaceOpcode.setNoiseMode, payload: [0x00, 0x0A, mode.rawValue])
        case .readConfig(let setting):
            return RaceFrame.encodeCommand(opcode: RaceOpcode.readConfig, payload: setting.rawValue.littleEndianBytes)
        case .writeConfig(let value):
            guard let wire = value.wire else { return nil }
            return RaceFrame.encodeCommand(opcode: RaceOpcode.writeConfig,
                                           payload: value.setting.rawValue.littleEndianBytes + wire)
        case .readSpatialSound:
            return RaceFrame.encodeCommand(opcode: RaceOpcode.jblTunnel,
                                           payload: [0xAA, 0x06, 0x03, 0x00, 0x01, 0x00, Self.spatialSoundID])
        case .setSpatialSound(let mode):
            return RaceFrame.encodeCommand(opcode: RaceOpcode.jblTunnel,
                                           payload: [0xAA, 0x06, 0x06, 0x00, 0x00, 0x00, Self.spatialSoundID, 0x02] + mode.wire)
        case .readSmartTalk:
            return RaceFrame.encodeCommand(opcode: RaceOpcode.readSmartTalk, payload: [])
        case .setSmartTalk(let smartTalk):
            guard SmartTalk.allowedSeconds.contains(smartTalk.seconds) else { return nil }
            return RaceFrame.encodeCommand(opcode: RaceOpcode.setSmartTalk,
                                           payload: [smartTalk.isEnabled ? 0x01 : 0x00, smartTalk.seconds])
        case .readAutoAnswer:
            return RaceFrame.encodeCommand(opcode: RaceOpcode.readAutoAnswer, payload: [])
        case .setAutoAnswer(let on):
            return RaceFrame.encodeCommand(opcode: RaceOpcode.setAutoAnswer, payload: [on ? 0x01 : 0x00])
        }
    }
}

extension UInt16 {
    var littleEndianBytes: [UInt8] { [UInt8(self & 0xFF), UInt8(self >> 8)] }
}
