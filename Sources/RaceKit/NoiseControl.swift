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

/// The complete set of frames this app can send. Anything else RACE offers (memory and flash
/// access, firmware update, factory reset) is deliberately unrepresentable here: on unpatched
/// Airoha firmware those commands are unauthenticated and can brick the device.
public enum RaceCommand: Equatable, Sendable {
    case readNoiseMode
    case setNoiseMode(NoiseMode)

    static let readNoiseModeOpcode: UInt16 = 0x0901
    static let setNoiseModeOpcode: UInt16 = 0x0E06

    /// Wire bytes, or nil for a command that was never verified on hardware.
    public var encoded: [UInt8]? {
        switch self {
        case .readNoiseMode:
            return RaceFrame.encodeCommand(opcode: Self.readNoiseModeOpcode, payload: [0x05, 0x00])
        case .setNoiseMode(let mode):
            guard NoiseMode.settable.contains(mode) else { return nil }
            return RaceFrame.encodeCommand(opcode: Self.setNoiseModeOpcode, payload: [0x00, 0x0A, mode.rawValue])
        }
    }
}

public enum RaceEvent: Equatable, Sendable {
    /// Current mode, from a read response or from the indication the buds send after a set.
    /// `mode` is nil when the raw byte is not a known mode.
    case noiseMode(NoiseMode?, raw: UInt8)
    /// Reply to a set. The first body byte is a status: 0x00 accepted. The buds answer 0x01
    /// while they are not worn, because noise control is disabled out of the ear.
    case setNoiseModeResult(accepted: Bool, status: UInt8)
    case other
}

extension RaceFrame {
    public var event: RaceEvent {
        if opcode == RaceCommand.readNoiseModeOpcode,
           type == RaceFrameType.response.rawValue || type == RaceFrameType.indication.rawValue,
           body.count >= 4, body[0] == 0x05, body[1] == 0x00 {
            return .noiseMode(NoiseMode(rawValue: body[3]), raw: body[3])
        }
        // The 0x5C notifications on the same opcode (`65|66|67 00 00 64` right after connecting)
        // carry something else and are ignored by the body[0] check above.
        if opcode == RaceCommand.setNoiseModeOpcode, type == RaceFrameType.response.rawValue, let status = body.first {
            return .setNoiseModeResult(accepted: status == 0x00, status: status)
        }
        return .other
    }
}
