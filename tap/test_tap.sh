#!/bin/bash
# Black-box tests for claude-usage-tap.sh — the tap seam.
#
# Fixtures piped in; snapshot file, exit status, and output asserted. No real
# home directory is touched: HOME and CLAUDE_CONFIG_DIR point into a temp root.

set -u
tap="$(cd "$(dirname "$0")" && pwd)/claude-usage-tap.sh"
root=$(mktemp -d) || exit 1
trap 'rm -rf "$root"' EXIT

pass=0 fail=0
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); echo "FAIL: $1"; }
check() { # check <description> <condition...>
  local desc=$1; shift
  if "$@"; then ok; else bad "$desc"; fi
}

good_payload='{"session_id":"x","rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1770000000},"seven_day":{"used_percentage":41.2,"resets_at":1770400000}}}'

# --- 1. well-formed payload: writes snapshot with rate_limits + updated_at ---
dir="$root/a"; mkdir -p "$dir"
out=$(echo "$good_payload" | CLAUDE_CONFIG_DIR="$dir" "$tap" 2>&1); rc=$?
check "writes on good payload: exit 0"            [ "$rc" -eq 0 ]
check "writes on good payload: prints nothing"    [ -z "$out" ]
check "writes on good payload: snapshot exists"   [ -f "$dir/usage-snapshot.json" ]
check "snapshot carries rate_limits"  jq -e '.rate_limits.five_hour.used_percentage == 23.5' "$dir/usage-snapshot.json" >/dev/null
check "snapshot carries updated_at"   jq -e '.updated_at | numbers' "$dir/usage-snapshot.json" >/dev/null

# --- 2. null rate_limits: does NOT clobber the good snapshot ---
before=$(cat "$dir/usage-snapshot.json")
out=$(echo '{"session_id":"x","rate_limits":null}' | CLAUDE_CONFIG_DIR="$dir" "$tap" 2>&1); rc=$?
check "null rate_limits: exit 0"                  [ "$rc" -eq 0 ]
check "null rate_limits: prints nothing"          [ -z "$out" ]
check "null rate_limits: snapshot untouched"      [ "$(cat "$dir/usage-snapshot.json")" = "$before" ]

# --- 3. missing rate_limits: does NOT clobber ---
out=$(echo '{"session_id":"x"}' | CLAUDE_CONFIG_DIR="$dir" "$tap" 2>&1); rc=$?
check "missing rate_limits: exit 0"               [ "$rc" -eq 0 ]
check "missing rate_limits: snapshot untouched"   [ "$(cat "$dir/usage-snapshot.json")" = "$before" ]

# --- 4. garbage input: survives, silent, no clobber ---
out=$(echo 'not json at all {{{' | CLAUDE_CONFIG_DIR="$dir" "$tap" 2>&1); rc=$?
check "garbage: exit 0"                           [ "$rc" -eq 0 ]
check "garbage: prints nothing"                   [ -z "$out" ]
check "garbage: snapshot untouched"               [ "$(cat "$dir/usage-snapshot.json")" = "$before" ]

# --- 5. empty input ---
out=$(printf '' | CLAUDE_CONFIG_DIR="$dir" "$tap" 2>&1); rc=$?
check "empty input: exit 0"                       [ "$rc" -eq 0 ]
check "empty input: snapshot untouched"           [ "$(cat "$dir/usage-snapshot.json")" = "$before" ]

# --- 6. no temp files left behind, any case ---
leftovers=$(find "$dir" -name 'usage-snapshot.json.*' | wc -l | tr -d ' ')
check "no temp files left"                        [ "$leftovers" = "0" ]

# --- 7. env routing: CLAUDE_CONFIG_DIR names the account ---
dirA="$root/homeA/.claude"; dirB="$root/b2"; mkdir -p "$dirA" "$dirB"
echo "$good_payload" | HOME="$root/homeA" CLAUDE_CONFIG_DIR="$dirB" "$tap"
check "env set: writes into named dir"            [ -f "$dirB/usage-snapshot.json" ]
check "env set: default dir untouched"            [ ! -f "$dirA/usage-snapshot.json" ]

# --- 8. env unset: defaults to ~/.claude ---
echo "$good_payload" | HOME="$root/homeA" env -u CLAUDE_CONFIG_DIR "$tap"
check "env unset: writes into ~/.claude"          [ -f "$dirA/usage-snapshot.json" ]

# --- 9. config dir missing entirely: silent no-op ---
out=$(echo "$good_payload" | CLAUDE_CONFIG_DIR="$root/nonexistent" "$tap" 2>&1); rc=$?
check "missing dir: exit 0"                       [ "$rc" -eq 0 ]
check "missing dir: prints nothing"               [ -z "$out" ]

echo "----"
echo "pass: $pass  fail: $fail"
[ "$fail" -eq 0 ]
