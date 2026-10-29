/// Noise-control modes as the buds report them in the mode byte.
public enum NoiseMode: UInt8, CaseIterable, Sendable {
    case off = 0x00
    case anc = 0x01
    case talkThru = 0x09
    case ambientAware = 0x0A

    /// Modes with a set command verified on hardware. `off` has no known command: the buds
    /// report it, but nobody has captured the frame that sets it, so it is not sendable.
    public static let settable: [NoiseMode] = [.anc, .ambientAware, .talkThru]
}

/// Replies the controller reacts to beyond keeping `DeviceState` current.
public enum RaceEvent: Equatable, Sendable {
    /// Current mode, from a read response or from the indication the buds send after a set.
    /// `mode` is nil when the raw byte is not a known mode.
    case noiseMode(NoiseMode?, raw: UInt8)
    /// Reply to a noise-mode set. The first body byte is a status: 0x00 accepted. The buds answer
    /// 0x01 while they are not worn, because noise control is disabled out of the ear.
    case setNoiseModeResult(accepted: Bool, status: UInt8)
    /// Reply to any other setting write; the first body byte is the status, 0x00 accepted.
    case settingWriteResult(accepted: Bool, status: UInt8)
    case other
}

extension RaceFrame {
    public var event: RaceEvent {
        let isResponse = type == RaceFrameType.response.rawValue
        if opcode == RaceOpcode.readNoiseMode,
           isResponse || type == RaceFrameType.indication.rawValue,
           body.count >= 4, body[0] == 0x05, body[1] == 0x00 {
            return .noiseMode(NoiseMode(rawValue: body[3]), raw: body[3])
        }
        // The 0x5C notifications on the same opcode (`65|66|67 00 00 <pct>`) are battery levels,
        // handled by `DeviceState`, and excluded by the body[0] check above.
        guard isResponse, let status = body.first else { return .other }
        switch opcode {
        case RaceOpcode.setNoiseMode:
            return .setNoiseModeResult(accepted: status == 0x00, status: status)
        case RaceOpcode.writeConfig, RaceOpcode.setSmartTalk, RaceOpcode.setAutoAnswer:
            return .settingWriteResult(accepted: status == 0x00, status: status)
        default:
            return .other
        }
    }
}
