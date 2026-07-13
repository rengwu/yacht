import Foundation
import UsageCore

/// Config persistence, discovery, and tap deployment — asserted on what lands
/// on disk, in fixture directories.
func runConfigTests(_ t: Harness) {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    // MARK: Config round-trip

    do {
        let url = root.appendingPathComponent("nested/config.json")
        let config = AppConfig(
            accounts: [
                Account(label: "john", configDir: URL(fileURLWithPath: "/Users/x/.claude")),
                Account(label: "jane", configDir: URL(fileURLWithPath: "/Users/x/.claude2")),
            ],
            warnThreshold: 80
        )
        try ConfigStore.save(config, to: url)
        t.checkEqual(ConfigStore.load(from: url), config, "config round-trips")
    } catch { t.check(false, "config save threw \(error)") }

    t.checkEqual(
        ConfigStore.load(from: root.appendingPathComponent("missing.json")),
        AppConfig(), "missing config → defaults"
    )
    do {
        let garbage = root.appendingPathComponent("garbage.json")
        try Data("not json".utf8).write(to: garbage)
        t.checkEqual(ConfigStore.load(from: garbage), AppConfig(), "garbage config → defaults")
    } catch { t.check(false, "garbage fixture setup threw \(error)") }

    // MARK: Discovery — .claude* directories only

    do {
        let home = root.appendingPathComponent("home")
        for dir in [".claude", ".claude2", ".config", "Documents"] {
            try fm.createDirectory(
                at: home.appendingPathComponent(dir), withIntermediateDirectories: true
            )
        }
        try Data("{}".utf8).write(to: home.appendingPathComponent(".claude.json"))  // a file, not a dir
        t.checkEqual(
            Discovery.claudeConfigDirs(home: home).map(\.lastPathComponent),
            [".claude", ".claude2"],
            "discovery finds .claude* directories, skips files and others"
        )
        t.checkEqual(
            Discovery.claudeConfigDirs(home: root.appendingPathComponent("nowhere")),
            [], "unreadable home → nothing discovered"
        )
    } catch { t.check(false, "discovery fixture setup threw \(error)") }

    // MARK: Tap deployment

    do {
        // The embedded script must be byte-identical to the canonical,
        // black-box-tested one in the repo.
        let repoScript = URL(fileURLWithPath: #filePath)          // Tests/UsageCoreTests/ConfigTests.swift
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tap/claude-usage-tap.sh")
        let canonical = try String(contentsOf: repoScript, encoding: .utf8)
        t.checkEqual(
            TapDeployment.script, canonical,
            "embedded tap script matches tap/claude-usage-tap.sh byte for byte"
        )

        let deployDir = root.appendingPathComponent("Application Support/ClaudeUsage")
        let command = try TapDeployment.deploy(to: deployDir)
        t.checkEqual(
            command, deployDir.appendingPathComponent("claude-usage-tap.sh").path,
            "deploy returns the command path"
        )
        t.checkEqual(
            try String(contentsOf: URL(fileURLWithPath: command), encoding: .utf8),
            TapDeployment.script, "deployed script content"
        )
        let perms = try fm.attributesOfItem(atPath: command)[.posixPermissions] as? Int
        t.checkEqual(perms, 0o755, "deployed script is executable")
        let again = try TapDeployment.deploy(to: deployDir)
        t.checkEqual(again, command, "deploy is idempotent")
    } catch { t.check(false, "deployment block threw \(error)") }
}
