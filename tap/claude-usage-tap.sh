#!/bin/bash
# claude-usage-tap.sh — Claude Code status line command for the Yacht menu bar app.
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
