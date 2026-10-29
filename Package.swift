// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BudsBar",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure protocol code: framing, commands, device profiles. No Bluetooth, fully unit-tested.
        .target(name: "RaceKit"),
        // The menu bar app: IOBluetooth transport + SwiftUI.
        .executableTarget(
            name: "BudsBar",
            dependencies: ["RaceKit"],
            linkerSettings: [.linkedFramework("IOBluetooth")]
        ),
        .testTarget(name: "RaceKitTests", dependencies: ["RaceKit"]),
    ]
)
