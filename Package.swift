// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v13)],
    targets: [
        // Core library: no AppKit, ever. Model, display logic, tap installer.
        .target(name: "UsageCore", path: "Sources/UsageCore"),
        // Tests are a plain executable run with `swift run UsageCoreTests`:
        // this machine has Command Line Tools only, and XCTest ships with Xcode.
        .executableTarget(
            name: "UsageCoreTests",
            dependencies: ["UsageCore"],
            path: "Tests/UsageCoreTests"
        ),
        // The ClaudeUsage executable target (AppKit projection) arrives with the
        // UI tickets; until then the prototype lives in .plan/usage-menubar/assets/.
    ]
)
