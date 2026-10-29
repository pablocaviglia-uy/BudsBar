import AppKit
import RaceKit
import SwiftUI

@main
struct BudsBarApp: App {
    @StateObject private var buds = BudsController()
    @StateObject private var loginItem = LoginItem()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(buds: buds, loginItem: loginItem)
        } label: {
            Image(nsImage: buds.menuBarImage)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuContent: View {
    @ObservedObject var buds: BudsController
    @ObservedObject var loginItem: LoginItem

    var body: some View {
        Text(buds.statusLine)
        if let battery = buds.batteryLine {
            Text(battery)
        }
        if let notice = buds.notice {
            Text(notice)
        }
        if let profile = buds.profile, buds.isConnected {
            Divider()
            ForEach(profile.settableModes, id: \.self) { mode in
                Toggle(mode.displayName, isOn: Binding(
                    get: { buds.mode == mode },
                    set: { _ in buds.set(mode) }
                ))
            }
            Text("To turn noise control off, use the case or the earbuds")
            SettingsSection(buds: buds)
        }
        Divider()
        Button("Refresh") { buds.refresh() }
            .keyboardShortcut("r")
        Toggle("Open at Login", isOn: Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.set($0) }
        ))
        if loginItem.needsApproval {
            Button("Allow BudsBar in Login Items…") { loginItem.openSystemSettings() }
        }
        if let error = loginItem.error {
            Text("Login item: \(error)")
        }
        Button("Quit BudsBar") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Settings beyond noise control, shown only for models whose profile lists them.
private struct SettingsSection: View {
    @ObservedObject var buds: BudsController

    var body: some View {
        let state = buds.state
        if DeviceProfile.Feature.allCases.contains(where: { $0 != .battery && buds.supports($0) }) {
            Divider()
        }
        if buds.supports(.spatialSound) {
            Menu("Spatial Sound: \(state.spatialSound?.displayName ?? "…")") {
                ForEach(SpatialSound.allCases, id: \.self) { mode in
                    Toggle(mode.displayName, isOn: Binding(
                        get: { state.spatialSound == mode },
                        set: { _ in buds.setSpatialSound(mode) }
                    ))
                }
            }
        }
        if buds.supports(.voiceAware) {
            Menu("VoiceAware: \(voiceAwareSummary(state))") {
                Toggle("On", isOn: Binding(
                    get: { state.voiceAware == true },
                    set: { buds.setVoiceAware($0) }
                ))
                Divider()
                ForEach(ConfigValue.voiceAwareLevels, id: \.self) { level in
                    Toggle(Self.levelName(level), isOn: Binding(
                        get: { state.voiceAwareLevel == level },
                        set: { _ in buds.setVoiceAwareLevel(level) }
                    ))
                }
            }
        }
        if buds.supports(.smartTalk) {
            Menu("Smart Talk: \(smartTalkSummary(state))") {
                Toggle("Off", isOn: Binding(
                    get: { state.smartTalk?.isEnabled == false },
                    set: { _ in buds.setSmartTalk(enabled: false) }
                ))
                ForEach(SmartTalk.allowedSeconds, id: \.self) { seconds in
                    Toggle("\(seconds) seconds", isOn: Binding(
                        get: { state.smartTalk?.isEnabled == true && state.smartTalk?.seconds == seconds },
                        set: { _ in buds.setSmartTalk(enabled: true, seconds: seconds) }
                    ))
                }
            }
        }
        if buds.supports(.autoPlayPause) {
            Toggle("Auto Play & Pause", isOn: Binding(
                get: { state.autoPlayPause == true },
                set: { buds.setAutoPlayPause($0) }
            ))
        }
        if buds.supports(.autoAnswer) {
            Toggle("Answer Calls Automatically", isOn: Binding(
                get: { state.autoAnswer == true },
                set: { buds.setAutoAnswer($0) }
            ))
        }
        if buds.supports(.voicePrompts) {
            Toggle("Voice Prompts", isOn: Binding(
                get: { state.voicePrompts == true },
                set: { buds.setVoicePrompts($0) }
            ))
        }
    }

    static func levelName(_ level: Int) -> String {
        switch level {
        case 1: return "Low"
        case 2: return "Medium"
        default: return "High"
        }
    }

    private func voiceAwareSummary(_ state: DeviceState) -> String {
        guard let on = state.voiceAware else { return "…" }
        guard on else { return "Off" }
        return state.voiceAwareLevel.map(Self.levelName) ?? "On"
    }

    private func smartTalkSummary(_ state: DeviceState) -> String {
        guard let smartTalk = state.smartTalk else { return "…" }
        return smartTalk.isEnabled ? "\(smartTalk.seconds) s" : "Off"
    }
}

extension NoiseMode {
    var displayName: String {
        switch self {
        case .off: return "Off"
        case .anc: return "Noise Cancelling"
        case .ambientAware: return "Ambient Aware"
        case .talkThru: return "TalkThru"
        }
    }

    /// Glyph shown next to the earbuds in the menu bar; off shows the earbuds alone.
    var symbolName: String? {
        switch self {
        case .off: return nil
        case .anc: return "waveform.slash"
        case .ambientAware: return "ear"
        case .talkThru: return "person.wave.2"
        }
    }
}

extension SpatialSound {
    var displayName: String {
        switch self {
        case .off: return "Off"
        case .fixed: return "Fixed"
        case .headTracking: return "Head Tracking"
        }
    }
}

extension BudsController {
    var menuBarImage: NSImage {
        let shownMode = isConnected ? (pendingMode ?? mode) : nil
        return MenuBarIcon.image(modeSymbol: shownMode?.symbolName,
                                 dimmed: !isConnected,
                                 modePending: pendingMode != nil,
                                 accessibilityLabel: "BudsBar — \(statusLine)")
    }

    var batteryLine: String? {
        guard isConnected, !state.battery.isEmpty else { return nil }
        let parts: [(EarbudSide, String)] = [(.left, "L"), (.right, "R"), (.chargingCase, "Case")]
        let text = parts.compactMap { side, label in state.battery[side].map { "\(label) \($0)%" } }
        return "Battery: " + text.joined(separator: " · ")
    }

    var statusLine: String {
        switch status {
        case .searching:
            return "Looking for earbuds…"
        case .noDevice:
            return "No supported earbuds paired with this Mac"
        case .unsupported(let name):
            return "\(name) is not supported yet"
        case .disconnected(let name):
            return "\(name): not connected to this Mac"
        case .connecting(let name):
            return "\(name): connecting…"
        case .connected(let name):
            if let pendingMode { return "\(name): switching to \(pendingMode.displayName)…" }
            if let mode { return "\(name): \(mode.displayName)" }
            if let raw = state.rawNoiseMode { return "\(name): unknown mode 0x\(String(raw, radix: 16))" }
            return "\(name): reading mode…"
        case .failed(let reason):
            return "Error: \(reason)"
        }
    }
}
