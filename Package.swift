// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AnotherClaudeTracker",
    platforms: [.macOS(.v13)],
    targets: [
        // Core library: no AppKit, ever. Model, display logic, tap installer.
        .target(name: "UsageCore", path: "Sources/UsageCore"),
        // The app: a dumb projection of UsageCore's view model.
        .executableTarget(
            name: "AnotherClaudeTracker",
            dependencies: ["UsageCore"],
            path: "Sources/AnotherClaudeTracker"
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
