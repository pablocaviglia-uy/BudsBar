/// A model the app knows how to drive. RACE is Airoha's chip-level protocol, so many brands
/// expose it, but the noise-control payloads are chosen by each headphone maker: a model is only
/// listed here once its commands are confirmed on real hardware.
public struct DeviceProfile: Equatable, Sendable, Identifiable {
    public enum Evidence: Equatable, Sendable {
        /// Commands exercised against this model by this project.
        case testedHere
        /// Commands confirmed on this model by another public project.
        case reportedBy(String)
    }

    public let id: String
    public let displayName: String
    /// Case-insensitive substrings of the Bluetooth name. Kept specific on purpose:
    /// "Live 770NC" shares a model number with "Tune 770NC" but speaks a different protocol.
    public let bluetoothNames: [String]
    public let settableModes: [NoiseMode]
    /// Everything beyond noise control, each confirmed on this model.
    public let features: Set<Feature>
    public let evidence: Evidence

    public enum Feature: CaseIterable, Sendable {
        case battery, spatialSound, voiceAware, smartTalk, autoPlayPause, autoAnswer, voicePrompts
    }

    public func matches(deviceName: String) -> Bool {
        let name = deviceName.lowercased()
        return bluetoothNames.contains { name.contains($0.lowercased()) }
    }

    public static let all: [DeviceProfile] = [
        DeviceProfile(id: "jbl-tour-pro-3", displayName: "JBL Tour Pro 3",
                      bluetoothNames: ["Tour Pro 3"], settableModes: NoiseMode.settable,
                      features: Set(Feature.allCases), evidence: .testedHere),
        DeviceProfile(id: "jbl-tune-770nc", displayName: "JBL Tune 770NC",
                      bluetoothNames: ["Tune 770NC"], settableModes: NoiseMode.settable,
                      features: [], evidence: .reportedBy("https://github.com/davedumto/Hush")),
        DeviceProfile(id: "jbl-tune-670nc", displayName: "JBL Tune 670NC",
                      bluetoothNames: ["Tune 670NC"], settableModes: NoiseMode.settable,
                      features: [], evidence: .reportedBy("https://github.com/davedumto/Hush")),
    ]

    public static func profile(forDeviceName name: String) -> DeviceProfile? {
        all.first { $0.matches(deviceName: name) }
    }
}
