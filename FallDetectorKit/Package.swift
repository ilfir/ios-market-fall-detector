// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "FallDetectorKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "DetectorCore", targets: ["DetectorCore"]),
        .library(name: "MarketData", targets: ["MarketData"]),
        .executable(name: "fdk-check", targets: ["fdk-check"]),
    ],
    targets: [
        // Pure logic: models, detector engine, alert dedup, market calendar, formatting.
        .target(name: "DetectorCore"),
        // Data providers, history cache and the monitoring orchestrator.
        .target(name: "MarketData", dependencies: ["DetectorCore"]),
        // Command-line runner for checking live data from a Mac.
        .executableTarget(name: "fdk-check", dependencies: ["DetectorCore", "MarketData"]),
        .testTarget(name: "DetectorCoreTests", dependencies: ["DetectorCore", "MarketData"]),
    ]
)
