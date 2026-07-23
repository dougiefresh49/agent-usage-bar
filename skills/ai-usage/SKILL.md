---
name: ai-usage
description: Check live AI provider usage and rate limits (Claude, OpenAI/Codex, Cursor) from the AgentUsageBar menu bar app. Use before choosing which model or provider to route work or subagents to, when deciding whether to conserve a nearly-exhausted quota, or when the user asks how much AI usage/quota they have left.
---

# AI provider usage

The AgentUsageBar menu bar app polls Claude, OpenAI/Codex, and Cursor usage APIs and writes a snapshot to disk. Read that snapshot instead of calling any provider API yourself.

## How to read usage

1. Read `~/Library/Application Support/AgentUsageBar/usage-snapshot.json`.
2. If the file is missing, or its `generatedAt` is more than 2 minutes old and you need current numbers, run the bundled script instead:

   ```bash
   bash "$(dirname "$SKILL_PATH")/scripts/get-usage.sh"
   ```

   (When invoking from a session where `$SKILL_PATH` is unavailable, the script lives at `scripts/get-usage.sh` next to this SKILL.md.)

   The script serves the cached snapshot when it is under 2 minutes old; otherwise it pings the running app to refresh (the app throttles refreshes to once per 2 minutes) and waits up to ~15s for new data. Never poll the script in a loop — one call per decision point is enough, and repeated calls within 2 minutes return the same cache.

3. If the script errors because the app is not running, say so and fall back to whatever the user tells you — do not attempt to fetch provider APIs or tokens directly.

## Snapshot format

```json
{
  "version": 1,
  "generatedAt": "2026-07-23T06:00:00Z",
  "providers": {
    "claude":  { "updatedAt": "…", "metrics": [ { "id": "five_hour", "label": "5-hour window", "percentUsed": 28, "resetsAt": "…" } ] },
    "openai":  { "updatedAt": "…", "metrics": [ { "id": "primary", "label": "7-day window", "percentUsed": 70, "resetsAt": "…" } ] },
    "cursor":  { "updatedAt": "…", "metrics": [ { "id": "models", "label": "First-party models", "percentUsed": 10, "resetsAt": "…" } ] }
  }
}
```

- `percentUsed` is 0–100; `null` means the provider did not report a number.
- A provider key that is absent means it is not connected in the app — treat it as "unknown", not "0% used".
- `resetsAt` (ISO 8601) is when that window resets; `updatedAt` is when that provider was last fetched.
- Metric ids — claude: `five_hour`, `seven_day`, `seven_day_opus`, `seven_day_sonnet`, `extra_usage`; openai: `primary`, `secondary`; cursor: `models`, `api`, `on_demand`.

## Using it for model routing

When choosing models for subagents or delegated work mid-task:

- Treat **≥90% used** as exhausted: route that work to a different provider's models until `resetsAt`.
- Treat **75–90%** as constrained: prefer another provider for heavy fan-out work (many subagents, long generations); light single calls are fine.
- The short window (Claude `five_hour`, OpenAI `primary`) matters for work right now; the long window (`seven_day`, `secondary`) matters for sustained heavy use — if the long window is nearly exhausted, conserve even when the short window looks fine.
- If all providers are constrained, tell the user instead of silently degrading, and mention the earliest `resetsAt`.
- Re-check at natural decision points (before spawning a batch of subagents), not continuously.
