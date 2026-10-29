/// Settings decoded from a capture of JBL's own Android app driving a Tour Pro 3.
/// Each wire value below is what that app sent and what the earbuds echoed back.

public enum SpatialSound: CaseIterable, Equatable, Sendable {
    case off
    case fixed
    case headTracking

    var wire: [UInt8] {
        switch self {
        case .off: return [0x00, 0xFF]
        case .fixed: return [0x01, 0x01]
        case .headTracking: return [0x01, 0x02]
        }
    }

    init?(wire: [UInt8]) {
        guard let match = Self.allCases.first(where: { $0.wire == wire }) else { return nil }
        self = match
    }
}

/// Smart Talk pauses music while you speak, for a chosen time.
public struct SmartTalk: Equatable, Sendable {
    public var isEnabled: Bool
    public var seconds: UInt8

    /// The only durations the app offers.
    public static let allowedSeconds: [UInt8] = [5, 15, 20]

    public init(isEnabled: Bool, seconds: UInt8) {
        self.isEnabled = isEnabled
        self.seconds = seconds
    }
}

/// Settings stored in the generic config table (get `2C83 <id>`, set `2C82 <id> <value>`).
public enum ConfigSetting: UInt16, CaseIterable, Sendable {
    case autoPlayPause = 0x0002
    case voiceAwareLevel = 0x0006
    case voiceAware = 0x0007
    case voicePrompts = 0x0009
}

public enum ConfigValue: Equatable, Sendable {
    case autoPlayPause(Bool)
    case voiceAware(Bool)
    /// 1 (low) to 3 (high).
    case voiceAwareLevel(Int)
    case voicePrompts(Bool)

    public static let voiceAwareLevels = 1...3

    var setting: ConfigSetting {
        switch self {
        case .autoPlayPause: return .autoPlayPause
        case .voiceAware: return .voiceAware
        case .voiceAwareLevel: return .voiceAwareLevel
        case .voicePrompts: return .voicePrompts
        }
    }

    /// Wire value, or nil when out of the range the app offers.
    var wire: [UInt8]? {
        switch self {
        case .autoPlayPause(let on), .voiceAware(let on):
            return [on ? 0x01 : 0x00]
        case .voiceAwareLevel(let level):
            guard Self.voiceAwareLevels.contains(level) else { return nil }
            return [UInt8(level), 0x00]
        case .voicePrompts(let on):
            // Inverted on the wire: 0x00 is on, 0xFF is off.
            return [on ? 0x00 : 0xFF]
        }
    }
}

public enum EarbudSide: UInt8, CaseIterable, Sendable {
    case left = 0x65
    case right = 0x66
    case chargingCase = 0x67
}
