import Foundation

/// Deploys the tap script to a stable location the settings files can point at.
/// The canonical, black-box-tested script lives at tap/claude-usage-tap.sh in
/// the repo; this constant must match it byte for byte — the test suite checks.
public enum TapDeployment {

    public static let script = """
    #!/bin/bash
    # claude-usage-tap.sh — Claude Code status line command for the ClaudeUsage menu bar app.
    #
    # Reads the status line JSON payload on stdin and captures its rate_limits block to
    # usage-snapshot.json inside the config directory of whichever account is running
    # (CLAUDE_CONFIG_DIR, defaulting to ~/.claude). One shared script, N accounts: the
    # environment names the account, so two subscriptions can never overwrite each
    # other's snapshot.
    #
    # Contract: prints nothing (so no status line appears), always exits 0 (so it can
    # never break the session that hosts it), writes atomically (the app may read at
    # any moment), and declines to write when the payload carries no rate_limits —
    # those payloads are normal before an account's first API response, and treating
    # them as data would clobber a good snapshot with nothing.

    snapshot="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/usage-snapshot.json"

    tmp=$(mktemp "${snapshot}.XXXXXX" 2>/dev/null) || exit 0
    if jq -ce 'select(.rate_limits != null)
               | {rate_limits: .rate_limits, updated_at: now}' >"$tmp" 2>/dev/null; then
      mv -f "$tmp" "$snapshot" 2>/dev/null    # atomic replace
    else
      rm -f "$tmp" 2>/dev/null                # nothing to record — write nothing
    fi
    exit 0

    """

    public static func scriptURL(in directory: URL) -> URL {
        directory.appendingPathComponent("claude-usage-tap.sh")
    }

    /// Writes the script (idempotently) and marks it executable. Returns the
    /// command string the installer should put into settings.json.
    @discardableResult
    public static func deploy(to directory: URL) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = scriptURL(in: directory)
        try Data(script.utf8).write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }
}
