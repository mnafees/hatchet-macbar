// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HatchetBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "HatchetBar", path: "Sources/HatchetBar", resources: [.copy("hatchet.svg")])
    ]
)
