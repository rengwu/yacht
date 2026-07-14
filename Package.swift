// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Yacht",
    platforms: [.macOS(.v13)],
    targets: [
        // Core library: no AppKit, ever. Model, display logic, tap installer.
        .target(name: "UsageCore", path: "Sources/UsageCore"),
        // The app: a dumb projection of UsageCore's view model.
        .executableTarget(
            name: "Yacht",
            dependencies: ["UsageCore"],
            path: "Sources/Yacht"
        ),
        // Tests are a plain executable run with `swift run UsageCoreTests`:
        // this machine has Command Line Tools only, and XCTest ships with Xcode.
        .executableTarget(
            name: "UsageCoreTests",
            dependencies: ["UsageCore"],
            path: "Tests/UsageCoreTests"
        ),
    ]
)
