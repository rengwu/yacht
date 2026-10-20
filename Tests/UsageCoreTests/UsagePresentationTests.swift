import Foundation
import UsageCore

func runUsagePresentationTests(_ t: Harness) {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let a = Account(label: "Work", configDir: URL(fileURLWithPath: "/profiles/work"))
    let b = Account(label: "Home", configDir: URL(fileURLWithPath: "/profiles/home"))
    let snapshot = Snapshot(rows: [
        UsageRow(window: .fiveHour, used: 80, limit: 100, resetsAt: now.addingTimeInterval(3600)),
        UsageRow(window: .weekly, used: 20, limit: 100, resetsAt: now.addingTimeInterval(86400)),
    ], updatedAt: now.addingTimeInterval(-1080))
    var config = AppConfig(accounts: [a, b])
    func show(_ state: AccountState, _ configuration: AppConfig = config, at date: Date = now) -> UsageAccountPresentation {
        presentUsage(accounts: [state], config: configuration, now: date)[0]
    }
    let state = AccountState(account: a, snapshot: snapshot, tapStatus: .installed)
    let normal = show(state)
    t.checkEqual(normal.windows.count, 2, "native: all reported windows")
    t.checkEqual(normal.menuBarFigure?.percentage, 80, "native: primary defaults")
    t.checkEqual(normal.menuBarFigure?.tone, .warn, "native: warning uses consumed quota")
    t.checkEqual(normal.windows[1].label, "Weekly", "native: weekly label")
    t.checkEqual(normal.windows[0].reset, "1h 0m", "native: countdown default")
    config.display.percentages = .remaining
    let remaining = show(state)
    t.checkEqual(remaining.menuBarFigure?.percentage, 20, "native: remaining inverts only the display")
    t.checkEqual(remaining.menuBarFigure?.tone, .warn, "native: remaining retains used threshold")
    let expired = show(state, at: now.addingTimeInterval(3600))
    t.checkEqual(expired.windows[0].percentage, nil, "native: reset boundary never claims a fresh zero")
    t.checkEqual(expired.windows[0].resetPassed, true, "native: reset boundary marked")
    t.checkEqual(expired.windows[0].reset, "", "native: past reset hides timestamp")
    t.checkEqual(expired.windows[0].tone, .dimmed, "native: past reset removes historical alarm")
    t.checkEqual(expired.windows[1].percentage, 80, "native: independent weekly window remains valid")
    let stale = show(AccountState(account: a, kimi: .stale(snapshot, reason: .unreachable)))
    t.checkEqual(stale.staleAge, "18m", "native: stale reading keeps its age")
    t.checkEqual(stale.windows[0].tone, .warn, "native: warning beats stale dimming")
    t.checkEqual(stale.windows[1].tone, .dimmed, "native: normal stale rows dim")
    t.check(stale.explanation?.contains("couldn't reach Kimi") == true, "native: failure stays available as help")
    let claudeStale = show(AccountState(account: a, snapshot: snapshot, tapStatus: .installed, stale: true))
    t.checkEqual(claudeStale.staleAge, "18m", "native: unreadable Claude snapshot keeps its saved age")
    t.checkEqual(claudeStale.windows[1].tone, .dimmed, "native: unreadable Claude snapshot dims")
    let absent = show(AccountState(account: a, kimi: .tokenExpired))
    t.checkEqual(absent.windows, [], "native: absent data invents no windows")
    t.checkEqual(absent.menuBarFigure, nil, "native: absent data invents no percentage")
    var selected = a
    selected.menuBarWindow = .weekly
    t.checkEqual(show(AccountState(account: selected, snapshot: snapshot, tapStatus: .installed)).menuBarFigure?.percentage,
                 80, "native: explicit weekly choice selects the weekly figure")
    selected.menuBarWindow = .other(minutes: 1440)
    t.checkEqual(show(AccountState(account: selected, snapshot: snapshot, tapStatus: .installed)).menuBarFigure,
                 nil, "native: missing selected window never falls back silently")
    config.accounts[0].showInMenuBar = false
    let hidden = presentUsage(accounts: [
        AccountState(account: config.accounts[0], snapshot: snapshot, tapStatus: .installed)
    ], config: config, now: now)
    t.checkEqual(hidden.count, 1, "native: Off does not remove dropdown account")
    t.checkEqual(hidden[0].windows.count, 2, "native: Off keeps all dropdown windows")
    config.display.resets = .exactTime
    t.check(!show(state).windows[0].reset.contains("h "), "native: exact mode does not include countdown")
    config.accounts[0].menuBarWindow = .weekly
    config.display.accounts = .icons
    config.relabel(configDir: a.configDir, to: "Renamed")
    t.checkEqual(config.accounts[0].menuBarWindow, .weekly, "native: rename preserves quota choice")
    t.checkEqual(config.accounts[0].showInMenuBar, false, "native: rename preserves Off")
    config.moveAccount(configDir: a.configDir, before: 2)
    t.checkEqual(config.accounts.map(\.label), ["Home", "Renamed"], "native: reorder moves account identity")
    config.moveAccount(configDir: a.configDir, before: 0)
    t.checkEqual(config.accounts.map(\.label), ["Renamed", "Home"], "native: reorder moves upward")
    config.moveAccount(configDir: a.configDir, before: 1)
    t.checkEqual(config.accounts.map(\.label), ["Renamed", "Home"], "native: adjacent drop is stable")
    t.check(!config.register(a), "native: duplicate folder rejected")
    let sibling = Account(label: "Client", configDir: URL(fileURLWithPath: "/profiles/client"))
    t.check(config.register(sibling), "native: same provider different folder accepted")
    do {
        let data = try JSONEncoder().encode(config)
        let restored = try JSONDecoder().decode(AppConfig.self, from: data)
        t.checkEqual(restored, config, "native: display preferences and order survive relaunch")
        let old = Data(#"{"accounts":[{"label":"Old","configDir":"/profiles/old"}],"warnThreshold":90,"rowTemplate":"custom"}"#.utf8)
        let migrated = try JSONDecoder().decode(AppConfig.self, from: old)
        t.checkEqual(migrated.display, DisplayPreferences(), "native: old configuration gets accepted defaults")
        t.checkEqual(migrated.accounts[0].showInMenuBar, true, "native: old account stays visible")
        t.checkEqual(migrated.accounts[0].menuBarWindow, nil, "native: old account follows provider primary")
        t.checkEqual(migrated.rowTemplate, "custom", "native: old customizations preserved in configuration")
        t.checkEqual(migrated.warnThreshold, 90, "native: old warning preference preserved")
    } catch { t.check(false, "native: configuration round trip: \(error)") }
}
