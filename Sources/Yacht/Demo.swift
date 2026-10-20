import Foundation
import UsageCore

/// Explicit, offline visual QA. --demo never loads/saves the user's configuration,
/// starts providers, installs taps, or changes login items.
enum Demo {
    static let capturedAt = Date()
    static var config: AppConfig {
        let providers: [Provider] = [.claude, .claude, .codex, .grok, .kimi, .claude, .codex, .grok]
        let names = ["Work", "Home", "Codex", "Grok", "Kimi", "Client", "Lab", "Grok 2"]
        return AppConfig(accounts: zip(providers, names).enumerated().map { i, pair in
            Account(provider: pair.0, label: pair.1, configDir: URL(fileURLWithPath: "/tmp/yacht-demo/\(i)"))
        })
    }

    static func states(_ accounts: [Account]) -> [AccountState] {
        accounts.map { account in
            let i = Int(account.configDir.lastPathComponent) ?? 0
            let primary = account.provider.defaultPrimaryWindow
            let used = [38.0, 12, 78, 30, 0, 41, 62, 100][min(i, 7)]
            var rows = [UsageRow(
                window: primary, used: used, limit: 100,
                resetsAt: capturedAt.addingTimeInterval(i == 3 ? -60 : 8040)
            )]
            if account.provider == .claude {
                rows.append(UsageRow(
                    window: .weekly, used: i == 5 ? 90 : 61, limit: 100,
                    resetsAt: capturedAt.addingTimeInterval(273600)
                ))
            }
            let snapshot = Snapshot(
                rows: rows, updatedAt: capturedAt.addingTimeInterval(i == 1 || i == 5 ? -1080 : 0),
                primary: primary
            )
            if i == 4 { return AccountState(account: account, kimi: .tokenExpired) }
            if i == 1 || i == 5 {
                return AccountState(account: account, snapshot: snapshot, tapStatus: .installed, stale: true)
            }
            return AccountState(account: account, snapshot: snapshot, tapStatus: .installed)
        }
    }
}
