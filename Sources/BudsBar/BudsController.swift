import Foundation
import IOBluetooth
import os
import RaceKit

private let logger = Logger(subsystem: "io.github.pablocaviglia-uy.budsbar", category: "buds")

private func log(_ message: String) {
    logger.notice("\(message, privacy: .public)")
}

/// Owns the RACE channel to the paired earbuds and publishes their noise-control state.
///
/// IOBluetooth delivers every callback on the run loop that created the objects, which here is
/// the main one, so all state is touched on the main thread only.
final class BudsController: NSObject, ObservableObject, IOBluetoothRFCOMMChannelDelegate {

    enum Status: Equatable {
        case searching
        case noDevice
        case unsupported(name: String)
        case disconnected(name: String)
        case connecting(name: String)
        case connected(name: String)
        case failed(String)
    }

    @Published private(set) var status: Status = .searching
    @Published private(set) var mode: NoiseMode?
    @Published private(set) var rawMode: UInt8?
    @Published private(set) var pendingMode: NoiseMode?
    @Published private(set) var notice: String?
    @Published private(set) var profile: DeviceProfile?

    /// The SDP service name every Airoha RACE device seen so far uses for its RFCOMM channel.
    static let raceServiceName = "Airoha_APP"
    /// Channel the Tour Pro 3 and Tune 770NC advertise; used only when no SDP record is cached.
    static let fallbackChannel: BluetoothRFCOMMChannelID = 21
    static let maxRetries = 5

    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var parser = RaceFrameParser()
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotification: IOBluetoothUserNotification?
    private var retries = 0
    private var pendingTimeout: DispatchWorkItem?

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    override init() {
        super.init()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
        DispatchQueue.main.async { self.start() }
    }

    // MARK: Public actions

    func refresh() {
        if channel == nil {
            retries = 0
            start()
        } else {
            send(.readNoiseMode)
        }
    }

    func set(_ newMode: NoiseMode) {
        guard isConnected, profile?.settableModes.contains(newMode) == true,
              let frame = RaceCommand.setNoiseMode(newMode).encoded else { return }
        notice = nil
        pendingMode = newMode
        write(frame)
        pendingTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.pendingMode != nil else { return }
            self.pendingMode = nil
            self.notice = "No answer from the earbuds"
        }
        pendingTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: timeout)
    }

    // MARK: Device discovery

    private func start() {
        guard let found = Self.findDevice() else {
            device = nil
            profile = nil
            status = .noDevice
            log("no paired device exposes \(Self.raceServiceName)")
            return
        }
        let name = found.name ?? "?"
        device = found
        profile = DeviceProfile.profile(forDeviceName: name)
        guard profile != nil else {
            status = .unsupported(name: name)
            log("\(name) exposes RACE but has no verified profile; sending nothing")
            return
        }
        watchDisconnect(found)
        if found.isConnected() {
            openChannel()
        } else {
            status = .disconnected(name: name)
        }
    }

    /// Paired devices exposing the RACE RFCOMM service; known models first, connected ones first.
    private static func findDevice() -> IOBluetoothDevice? {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let candidates = paired.filter { device in
            DeviceProfile.profile(forDeviceName: device.name ?? "") != nil || raceChannel(of: device) != nil
        }
        func rank(_ device: IOBluetoothDevice) -> Int {
            (DeviceProfile.profile(forDeviceName: device.name ?? "") != nil ? 2 : 0) + (device.isConnected() ? 1 : 0)
        }
        return candidates.max { rank($0) < rank($1) }
    }

    private static func raceChannel(of device: IOBluetoothDevice) -> BluetoothRFCOMMChannelID? {
        let records = (device.services as? [IOBluetoothSDPServiceRecord]) ?? []
        for record in records where record.getServiceName() == raceServiceName {
            var id: BluetoothRFCOMMChannelID = 0
            if record.getRFCOMMChannelID(&id) == kIOReturnSuccess { return id }
        }
        return nil
    }

    private func watchDisconnect(_ device: IOBluetoothDevice) {
        disconnectNotification?.unregister()
        disconnectNotification = device.register(
            forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device connected: IOBluetoothDevice) {
        if let device, device.addressString != connected.addressString { return }
        log("connect notification for \(connected.name ?? "?")")
        retries = 0
        // Give the audio profiles a moment to settle before opening the control channel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            if self.device == nil { self.start() } else { self.openChannel() }
        }
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification, device disconnected: IOBluetoothDevice) {
        log("disconnected: \(disconnected.name ?? "?")")
        channel = nil
        mode = nil
        rawMode = nil
        clearPending()
        status = .disconnected(name: disconnected.name ?? "?")
    }

    // MARK: Channel

    private func openChannel() {
        guard let device, channel == nil else { return }
        let name = device.name ?? "?"
        if case .connecting = status { return }
        guard device.isConnected() else {
            status = .disconnected(name: name)
            return
        }
        status = .connecting(name: name)
        let id = Self.raceChannel(of: device) ?? Self.fallbackChannel
        var opened: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&opened, withChannelID: id, delegate: self)
        guard result == kIOReturnSuccess else {
            scheduleRetry("could not open RFCOMM channel \(id) (0x\(String(result, radix: 16)))")
            return
        }
        channel = opened
        log("opening RFCOMM channel \(id) on \(name)")
    }

    private func scheduleRetry(_ reason: String) {
        log(reason)
        channel = nil
        guard let device, device.isConnected(), retries < Self.maxRetries else {
            status = device?.isConnected() == true ? .failed(reason) : .disconnected(name: device?.name ?? "?")
            return
        }
        retries += 1
        status = .failed(reason)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.openChannel() }
    }

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard error == kIOReturnSuccess else {
            scheduleRetry("RFCOMM open failed (0x\(String(error, radix: 16)))")
            return
        }
        channel = rfcommChannel
        parser = RaceFrameParser()
        retries = 0
        status = .connected(name: device?.name ?? "?")
        log("RACE channel open")
        send(.readNoiseMode)
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        guard rfcommChannel === channel else { return }
        mode = nil
        rawMode = nil
        clearPending()
        scheduleRetry("RACE channel closed")
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = [UInt8](UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        for frame in parser.append(bytes) { handle(frame) }
    }

    private func handle(_ frame: RaceFrame) {
        switch frame.event {
        case .noiseMode(let reported, let raw):
            mode = reported
            rawMode = raw
            log("noise mode 0x\(String(raw, radix: 16))")
            if let pendingMode, pendingMode == reported { clearPending() }
        case .setNoiseModeResult(let accepted, let statusByte):
            log("set result 0x\(String(statusByte, radix: 16))")
            if accepted {
                // The buds also send an indication; reading back covers the case where it is missed.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.send(.readNoiseMode) }
            } else {
                clearPending()
                notice = "Rejected — are the earbuds in your ears?"
            }
        case .other:
            break
        }
    }

    private func clearPending() {
        pendingMode = nil
        pendingTimeout?.cancel()
        pendingTimeout = nil
    }

    private func send(_ command: RaceCommand) {
        guard let bytes = command.encoded else { return }
        write(bytes)
    }

    private func write(_ bytes: [UInt8]) {
        guard let channel, isConnected else { return }
        var frame = bytes
        let result = channel.writeSync(&frame, length: UInt16(frame.count))
        if result != kIOReturnSuccess {
            log("write failed (0x\(String(result, radix: 16)))")
            notice = "Could not send the command"
            clearPending()
        }
    }
}
