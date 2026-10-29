/// Airoha RACE framing, as spoken on the "Airoha_APP" RFCOMM service of Airoha-based earbuds.
///
/// Layout: `header (0x05) | type | length (UInt16 LE) | opcode (UInt16 LE) | body`,
/// where `length` counts the opcode plus the body. Header 0x15 is used for firmware update
/// traffic; this package never sends it but tolerates it while parsing.
public enum RaceFrameType: UInt8, Sendable {
    case command = 0x5A
    case response = 0x5B
    case notification = 0x5C
    case indication = 0x5D
}

public struct RaceFrame: Equatable, Sendable {
    public let header: UInt8
    public let type: UInt8
    public let opcode: UInt16
    public let body: [UInt8]

    public init(header: UInt8 = 0x05, type: UInt8, opcode: UInt16, body: [UInt8]) {
        self.header = header
        self.type = type
        self.opcode = opcode
        self.body = body
    }

    /// Wire bytes of a command frame.
    static func encodeCommand(opcode: UInt16, payload: [UInt8]) -> [UInt8] {
        let length = UInt16(2 + payload.count)
        return [0x05, RaceFrameType.command.rawValue,
                UInt8(length & 0xFF), UInt8(length >> 8),
                UInt8(opcode & 0xFF), UInt8(opcode >> 8)] + payload
    }
}

/// Splits an RFCOMM byte stream into frames. Chunks may cut a frame anywhere, and one chunk
/// may carry several frames (the buds send a burst of three or four right after the channel opens).
public struct RaceFrameParser: Sendable {
    private var buffer: [UInt8] = []

    /// Longer declared lengths are treated as noise and skipped byte by byte to resync.
    static let maxFrameLength = 2048

    public init() {}

    public mutating func append(_ bytes: [UInt8]) -> [RaceFrame] {
        buffer += bytes
        var frames: [RaceFrame] = []
        while true {
            while let first = buffer.first, first != 0x05, first != 0x15 { buffer.removeFirst() }
            guard buffer.count >= 4 else { break }
            let length = Int(buffer[2]) | Int(buffer[3]) << 8
            guard length >= 2, length <= Self.maxFrameLength else {
                buffer.removeFirst()
                continue
            }
            guard buffer.count >= 4 + length else { break }
            let opcode = UInt16(buffer[4]) | UInt16(buffer[5]) << 8
            frames.append(RaceFrame(header: buffer[0], type: buffer[1], opcode: opcode,
                                    body: Array(buffer[6..<(4 + length)])))
            buffer.removeFirst(4 + length)
        }
        return frames
    }
}
