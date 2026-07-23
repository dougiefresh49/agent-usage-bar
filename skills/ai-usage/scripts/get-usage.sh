#!/bin/bash
# Prints the latest AI provider usage snapshot as JSON on stdout.
#
# Reads the snapshot written by the AgentUsageBar menu bar app. If the snapshot
# is older than MAX_AGE_SECONDS, asks the running app to refresh (throttled
# app-side to once per 2 minutes) and waits briefly for the rewrite. Never
# talks to provider APIs directly.
set -uo pipefail

SNAPSHOT="$HOME/Library/Application Support/AgentUsageBar/usage-snapshot.json"
MAX_AGE_SECONDS=120
REFRESH_WAIT_SECONDS=15
NOTIFICATION="com.agentusagebar.refresh"

snapshot_mtime() {
  stat -f %m "$SNAPSHOT" 2>/dev/null || echo 0
}

snapshot_age() {
  echo $(( $(date +%s) - $(snapshot_mtime) ))
}

print_snapshot() {
  cat "$SNAPSHOT"
  local age
  age=$(snapshot_age)
  if [ "$age" -ge "$MAX_AGE_SECONDS" ]; then
    echo "note: snapshot is ${age}s old$1" >&2
  fi
}

if [ -f "$SNAPSHOT" ] && [ "$(snapshot_age)" -lt "$MAX_AGE_SECONDS" ]; then
  print_snapshot ""
  exit 0
fi

if ! pgrep -xq AgentUsageBar; then
  if [ -f "$SNAPSHOT" ]; then
    print_snapshot " and the AgentUsageBar app is not running, so it cannot be refreshed"
    exit 0
  fi
  echo "error: AgentUsageBar app is not running and no cached snapshot exists at $SNAPSHOT" >&2
  echo "hint: launch the app (e.g. 'open -a AgentUsageBar') and connect providers in its Settings" >&2
  exit 1
fi

BEFORE=$(snapshot_mtime)
notifyutil -p "$NOTIFICATION"

deadline=$(( $(date +%s) + REFRESH_WAIT_SECONDS ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if [ "$(snapshot_mtime)" -gt "$BEFORE" ]; then
    # First provider landed; give the remaining providers a moment to write too.
    sleep 2
    break
  fi
  sleep 0.5
done

if [ -f "$SNAPSHOT" ]; then
  print_snapshot " (refresh request may have been throttled; data is still usable)"
  exit 0
fi

echo "error: no snapshot was produced at $SNAPSHOT — is any provider connected in AgentUsageBar?" >&2
exit 1
