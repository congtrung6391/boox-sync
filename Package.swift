// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BooxSync",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BooxSync", targets: ["BooxSync"]),
    ],
    targets: [
        .target(name: "CVirtualDisplay"),
        .target(name: "BooxSyncCore", dependencies: ["CVirtualDisplay"]),
        .executableTarget(name: "BooxSync", dependencies: ["BooxSyncCore"]),
        // XCTest/Swift Testing are not in the Command Line Tools, so checks are an executable.
        .executableTarget(name: "CoreChecks", dependencies: ["BooxSyncCore"]),
    ]
)
