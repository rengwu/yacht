import Foundation
import UsageCore

/// The installer seam: given a settings file, install and assert on what results.

let t = Harness()
let tap = "/Users/x/Library/Application Support/ClaudeUsage/claude-usage-tap.sh"

/// The real shape of the user's hand-maintained ~/.claude/settings.json —
/// model, permissions, plugins, effort level. The load-bearing fixture.
let richSettings = """
{
  "attribution": { "commit": "" },
  "permissions": { "allow": ["mcp__pencil"] },
  "model": "claude-fable-5[1m]",
  "enabledPlugins": {
    "gopls-lsp@claude-plugins-official": true,
    "rust-analyzer-lsp@claude-plugins-official": true
  },
  "effortLevel": "high",
  "skipDangerousModePermissionPrompt": true,
  "theme": "auto"
}
""".data(using: .utf8)!

func json(_ data: Data) -> NSDictionary {
    try! JSONSerialization.jsonObject(with: data) as! NSDictionary
}

// MARK: Preservation — the load-bearing test

do {
    let out = json(try TapInstaller.install(settings: richSettings, tapCommand: tap))
    let original = json(richSettings)
    for key in original.allKeys {
        t.check(
            (out[key] as? NSObject) == (original[key] as? NSObject),
            "install preserves key \(key)"
        )
    }
    t.checkEqual(out.count, original.count + 1, "install adds exactly one key")
    t.checkEqual(
        out["statusLine"] as? NSDictionary,
        ["type": "command", "command": tap] as NSDictionary,
        "install writes our statusLine"
    )
} catch {
    t.check(false, "install over rich settings threw \(error)")
}

// MARK: Detection tells the truth

t.checkEqual(
    TapInstaller.detect(settings: richSettings, tapCommand: tap), .notInstalled,
    "detect: no status line → notInstalled"
)
t.checkEqual(
    TapInstaller.detect(settings: nil, tapCommand: tap), .notInstalled,
    "detect: missing file → notInstalled"
)
do {
    let installed = try TapInstaller.install(settings: richSettings, tapCommand: tap)
    t.checkEqual(
        TapInstaller.detect(settings: installed, tapCommand: tap), .installed,
        "detect: our tap → installed"
    )
} catch { t.check(false, "install threw \(error)") }

let foreign = """
{"statusLine": {"type": "command", "command": "/usr/local/bin/sketchybar-line.sh"}}
""".data(using: .utf8)!
t.checkEqual(
    TapInstaller.detect(settings: foreign, tapCommand: tap),
    .foreign(command: "/usr/local/bin/sketchybar-line.sh"),
    "detect: foreign status line reported as foreign"
)

// MARK: Idempotence

do {
    let once = try TapInstaller.install(settings: richSettings, tapCommand: tap)
    let twice = try TapInstaller.install(settings: once, tapCommand: tap)
    t.checkEqual(once, twice, "install is idempotent")
} catch { t.check(false, "idempotence check threw \(error)") }

// MARK: Edges

do {
    let out = json(try TapInstaller.install(settings: nil, tapCommand: tap))
    t.checkEqual(out.count, 1, "no file yet → minimal settings with one key")
    t.check(out["statusLine"] != nil, "no file yet → statusLine present")
} catch { t.check(false, "install into no file threw \(error)") }

t.checkThrows(TapInstallerError.unreadableSettings, "unparseable settings refused") {
    _ = try TapInstaller.install(settings: "{ model: oops,, }".data(using: .utf8)!, tapCommand: tap)
}
t.checkThrows(TapInstallerError.unreadableSettings, "non-object settings refused") {
    _ = try TapInstaller.install(settings: "[1, 2, 3]".data(using: .utf8)!, tapCommand: tap)
}

// MARK: File wrapper — malformed file on disk stays untouched

do {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let file = dir.appendingPathComponent("settings.json")
    let broken = "not json".data(using: .utf8)!
    try broken.write(to: file)

    do {
        try TapInstaller.install(configDir: dir, tapCommand: tap)
        t.check(false, "file install over broken settings should throw")
    } catch {
        t.check(true, "file install over broken settings throws")
    }
    t.checkEqual(try Data(contentsOf: file), broken, "refused file left untouched")

    // And the happy path on disk: install, then detect through the same wrapper.
    let goodDir = dir.appendingPathComponent("good")
    try FileManager.default.createDirectory(at: goodDir, withIntermediateDirectories: true)
    try richSettings.write(to: goodDir.appendingPathComponent("settings.json"))
    try TapInstaller.install(configDir: goodDir, tapCommand: tap)
    t.checkEqual(
        TapInstaller.detect(configDir: goodDir, tapCommand: tap), .installed,
        "file wrapper round-trip installs and detects"
    )
} catch {
    t.check(false, "file wrapper block threw \(error)")
}

t.finish()
