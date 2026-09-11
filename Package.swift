// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Sheep", platforms: [.macOS(.v13)], products: [
    .executable(name: "Sheep", targets: ["Sheep"]),
    .executable(name: "SheepProbe", targets: ["SheepProbe"])
], targets: [
    .target(name: "SheepCore", resources: [.copy("Resources/animations.xml")]),
    .target(name: "SheepMac", dependencies: ["SheepCore"]),
    .executableTarget(name: "Sheep", dependencies: ["SheepMac", "SheepCore"]),
    .executableTarget(name: "SheepProbe", dependencies: ["SheepMac", "SheepCore"]),
    .testTarget(name: "SheepCoreTests", dependencies: ["SheepCore", "SheepMac"])
], swiftLanguageModes: [.v5])
