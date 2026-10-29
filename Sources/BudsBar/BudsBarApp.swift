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

extension BudsController {
    var menuBarImage: NSImage {
        let shownMode = isConnected ? (pendingMode ?? mode) : nil
        return MenuBarIcon.image(modeSymbol: shownMode?.symbolName,
                                 dimmed: !isConnected,
                                 modePending: pendingMode != nil,
                                 accessibilityLabel: "BudsBar — \(statusLine)")
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
            if let rawMode { return "\(name): unknown mode 0x\(String(rawMode, radix: 16))" }
            return "\(name): reading mode…"
        case .failed(let reason):
            return "Error: \(reason)"
        }
    }
}
