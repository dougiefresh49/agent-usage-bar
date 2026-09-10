# Plan: adopt T3 Code's usage-limits and Codex reset-credit approach

Research date: 2026-09-09. T3 Code source at commit `b7b3ef1e` (pingdotgg/t3code).
Key PRs: #9507 (Limits tab), #9534 (redeem reset credits), #10300 (pooling + restore math),
#10308 (keep credits across sparse updates), #10395 (hub HTTP path), #10458 (ignore Spark limits),
#9889 (show remaining instead of used).

## 1. What T3 Code actually does

### 1.1 Two data paths for Codex

**Native path (local `codex` login).** T3 never calls the ChatGPT web endpoints itself. It spawns
`codex app-server` (JSON-RPC over stdio) and uses:

| Step | Method | Notes |
|---|---|---|
| Handshake | `initialize` then `initialized` notification | `clientInfo`, `capabilities.experimentalApi: true` |
| Read | `account/rateLimits/read` | Returns `rateLimits{limitId, planType, primary, secondary}`, `rateLimitsByLimitId`, `rateLimitResetCredits{availableCount, credits[]}` |
| Redeem | `account/rateLimitResetCredit/consume` | Params `{idempotencyKey, creditId?}`. Result `outcome` is one of `reset`, `nothingToReset`, `noCredit`, `alreadyRedeemed` |
| Live | `account/rateLimits/updated` notification | Sparse partial snapshot pushed mid-turn; merged by window id |

Codex handles OAuth token refresh internally, so T3 never stores or refreshes a ChatGPT token.
Measured on this machine: handshake 0.22s, rate-limit read done at 0.85s total.

**Hub path (CLIProxyAPI).** For pooled accounts T3 proxies plain HTTP to OpenAI. This is the
path that matters for us because it is what our app already does with a pasted token:

| Purpose | Request |
|---|---|
| Usage | `GET https://chatgpt.com/backend-api/wham/usage` |
| List credits | `GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits` |
| Redeem | `POST https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume` with body `{"redeem_request_id": "<uuid>", "credit_id": "<id>"}`; response `{"code": "reset" \| "nothing_to_reset" \| "no_credit" \| "already_redeemed"}` |

Headers T3 sends on the Codex requests:

```
Authorization: Bearer <access_token>
Content-Type: application/json
OpenAI-Beta: codex-1
Originator: Codex Desktop
Chatgpt-Account-Id: <account id>   (when known)
```

Credits are filtered to `reset_type == "codex_rate_limits"`, `status == "available"`, and
`expires_at` in the future, sorted soonest-expiring first. The displayed "next" credit's id is
pinned into the redeem call so a retry from another client redeems the same one.

`redeem_request_id` is a deterministic UUIDv5 of `"<chatgpt_account_id>:<credit_id>"`, so
retries and duplicate clicks dedupe server-side instead of spending two credits.

Verified read-only on this machine with the token from `~/.codex/auth.json` and those headers:
both GETs return 200, and the credits list shows 3 available with the same 9/20 expiry as the
T3 screenshot. The `codex app-server` read returns the same data.

### 1.2 Claude

T3 uses the Claude Agent SDK's experimental usage control request during its capability probe,
plus the streamed `rate_limit_event` during turns. Both resolve to the same
`https://api.anthropic.com/api/oauth/usage` data we already fetch, with the same
`anthropic-beta: oauth-2025-04-20` header. Windows are `five_hour` and `seven_day`, plus
model-scoped weeklies from `rate_limits.model_scoped[]` (Fable today). Durations are hardcoded
to 300 and 10080 minutes. Claude has no reset credits, so nothing to redeem.

### 1.3 How T3 avoids hammering the providers

- **No dedicated usage poller.** Usage rides on the provider health probe the app already runs.
  Default interval is 5 minutes (`DEFAULT_PROVIDER_HEALTH_REFRESH_INTERVAL`).
- **Demand gating.** The probe only runs when `BackgroundPolicy.shouldRunScopeWork` says a
  connected client holds an activity lease (45s TTL, max 120s) and the host is not in a
  low-power state. No client looking means no requests.
- **Short timeouts, soft failure.** The rate-limit read has a 3s timeout and degrades to
  "no usage this probe" without failing the whole account probe. Hub calls use 15s.
- **Credits outage never hides usage.** The credits call is `orElseSucceed(undefined)`.
- **Keep last good bars.** A `probeFailed` result keeps the previous windows on screen; only
  `unsupported` (API key, Bedrock) clears them.
- **Sparse updates merge, never replace.** Mid-turn notifications merge by window id and
  preserve `resetCredits` from the last full probe (PR #10308).
- **Ignore model-specific buckets.** Snapshots whose `limitId != "codex"` (Spark) are dropped
  so they cannot overwrite the main allowance (PR #10458).
- **One refresh at a time.** A semaphore serialises refreshes so a slow read cannot overwrite
  a newer result or a just-completed redemption.

### 1.4 Redemption safety

- Confirmation dialog before anything is sent. Copy: "This redeems one credit on your account
  and clears the current rate-limit windows. It cannot be undone."
- Per-account lock keyed on the directory holding `auth.json`, one idempotency key kept until
  Codex reports an outcome. A retry after a timeout resends the same attempt.
- 20s timeout on the redeem call.
- After redemption, re-probe and require `checkedAt` to advance past the pre-redemption
  snapshot. Otherwise show "The reset was applied, but Codex could not confirm the new limits.
  Refresh to check."
- Outcome shown inline; `nothingToReset` and `noCredit` are not errors.

### 1.5 Presentation math (packages/shared/src/usageLimits.ts)

- Bars and headline show **remaining** percent, not used.
- `elapsedShare = (duration - (resetsAt - now)) / duration`, clamped 0..1. Needs
  `windowDurationMins`, which the HTTP usage endpoint gives us as `limit_window_seconds`.
- Pace: `gap = usedPercent - elapsed * 100`. Above +5 is "ahead" (may run dry), below -5 is
  "under", else "on". Shown as a small trend glyph next to the percent.
- A hairline on the bar at the elapsed share marks "where even spending would be".
- "+32% in 5d 3h" is what the next reset restores. For one account it equals that window's used
  percent; the hatched tail of the bar is that same amount.
- Countdown format: `5d 3h`, `2h 13m`, `12m`.
- Account popover: plan, signed-in machine, left %, reset time and countdown, "restores +X%",
  "N banked · expires in X", and the **Use reset** button.

## 2. Where we stand today

Already in agent-usage-bar:

- `ConnectedUsageService.swift` fetches `wham/usage` and `wham/rate-limit-reset-credits` with a
  pasted browser bearer token, keeps last-good usage on error, and does not blank usage when the
  credits call fails.
- `ConnectedUsageModel.swift` decodes windows including `limit_window_seconds` and `reset_at`,
  and decodes credits with id, status, expiry, title, description.
- Reset credits surface as a "Reset Credits" metric and an "Announcements" disclosure in
  `PopoverView.swift`, and `NotificationService.swift` can alert on the credit count.
- Claude has OAuth with refresh, 429 backoff with `Retry-After`, and model-scoped parsing.

Gaps versus T3:

1. The pasted ChatGPT token expires and needs manual re-paste. We do not read the local
   `codex` login, and we do not send the `OpenAI-Beta`, `Originator`, or `Chatgpt-Account-Id`
   headers.
2. No way to redeem a credit.
3. No per-request timeouts, no 429 backoff on the OpenAI or Cursor calls, and no sleep/wake or
   low-power awareness. The timer fires on a fixed interval regardless.
4. No pace, elapsed marker, or "restores +X% in Y" presentation.

## 3. Plan

### Phase 1. Codex credentials from the local CLI login

Goal: zero-setup Codex, no expiring pasted token.

- Add `CodexAuthFile` (new file in `macos/Sources/ClaudeUsageBar/`): read `$CODEX_HOME/auth.json`
  (default `~/.codex/auth.json`), require `auth_mode == "chatgpt"`, extract
  `tokens.access_token` and `tokens.account_id`. Re-read on every poll; the CLI rewrites the file
  when it refreshes.
- Credential precedence in `ConnectedUsageService`: pasted token (explicit override) →
  `auth.json` → `OPENAI_SESSION_TOKEN` env. Expose a source label for Settings
  ("Using Codex CLI login" vs "Using pasted token").
- Add the three headers above to `openAIResponseData`. Send `Chatgpt-Account-Id` when
  `account_id` is known.
- `SettingsView.swift`: the OpenAI section shows the detected source and a "Sign in with
  `codex login`" hint when neither is present. Token paste moves under an "Advanced" disclosure.
- On 401 with an `auth.json` token: surface "Codex login expired. Run any `codex` command or
  `codex login` to refresh." Phase 3 automates this.
- Tests: `auth.json` parsing with and without `CODEX_HOME`, precedence order, header set.

### Phase 2. Redeem a reset credit from the popover

- `ConnectedUsageService.consumeOpenAIResetCredit(credit:)`:
  - Compute `redeem_request_id` as UUIDv5 of `"<account_id or 'local'>:<credit_id>"` using
    CryptoKit `Insecure.SHA1`. Deterministic, so a retry reuses the id. (Using T3's exact
    namespace would make our retries and T3's collide into `already_redeemed`; not needed, use
    our own namespace constant.)
  - POST `…/rate-limit-reset-credits/consume`, 20s timeout, single-flight guard
    (`isRedeemingResetCredit`). Persist `(creditId, requestId)` in UserDefaults while pending so
    a relaunch retry sends the same attempt; clear on any decoded outcome.
  - Map `code` to an enum `OpenAIResetCreditOutcome` with user copy:
    reset → "Limits reset", nothing_to_reset → "Nothing to reset yet", no_credit → "No credit
    available", already_redeemed → "Already redeemed".
  - On `reset` or `already_redeemed`: call `fetchOpenAIUsage()` immediately and check that
    `openAILastUpdated` advanced. If not, show T3's "applied but could not confirm" copy.
- `PopoverView.swift` `OpenAIUsageView`: replace the "Announcements" disclosure with a credits
  row: "3 banked · next expires in 10d 22h" plus a **Use reset** button. Button opens
  `.confirmationDialog` with T3's copy; disabled while in flight; outcome text shows inline for
  a few seconds. Pin the soonest-expiring credit id into the request.
- Optional: dim the button and add "nothing to reset" hint when both windows are at 0% used.
- Keep the per-credit title/description available in a tooltip; the endpoint's "Thanks for
  using Codex" text is the announcement we show today.
- `NotificationService`: stretch goal, a "Use reset" `UNNotificationAction` on the
  weekly-threshold alert when credits are banked, routed through the same service method.
- Widgets: display the banked count only; redemption stays in the app.
- Tests: UUIDv5 determinism, outcome decoding, single-flight, pending-key persistence.
- Manual verification: one real redemption spends a credit. Do it when the weekly window is
  high so the reset is worth it.

### Phase 3. `codex app-server` as refresh fallback (optional, after 1 and 2)

- `CodexAppServerClient`: `Process` running `codex app-server`, newline-delimited JSON-RPC.
  Locate the binary via `CODEX_BINARY` override, then `/opt/homebrew/bin`, `/usr/local/bin`,
  `~/.npm-global/bin`, `$PATH`.
- Use it only when the direct HTTP call returns 401: call `account/read` with
  `{refreshToken: true}`, which makes Codex refresh and rewrite `auth.json`, then retry HTTP.
  This keeps polling cheap (no process spawn) while eliminating manual re-login.
- Alternative if the HTTP consume endpoint ever changes: `account/rateLimitResetCredit/consume`
  with the same idempotency key. Keep the client small enough that switching is one method.

### Phase 4. Polling hygiene (all providers)

- Set `URLRequest.timeoutInterval` (15s usage, 10s credits). Credits failure stays soft.
- Reuse `UsageService.backoffInterval` for OpenAI and Cursor 429s and honour `Retry-After`.
- Observe `NSWorkspace.willSleepNotification` / `didWakeNotification` and
  `screensDidWakeNotification`: pause the timer on sleep, fetch once on wake.
- Skip a scheduled fetch when the last successful one is under 60s old; manual refresh always
  runs but is debounced to one in-flight request per provider.
- Refresh on popover open when data is older than one polling interval, mirroring T3's
  refresh-on-Limits-tab behaviour.
- Honour `ProcessInfo.isLowPowerModeEnabled` by doubling the interval.
- Ignore Codex `additional_rate_limits` entries whose type is model-specific when computing the
  headline windows (T3's Spark rule); keep showing them as extra rows.

### Phase 5. Presentation borrowed from T3

Applies to Codex and Claude alike in `UsagePresentation.swift` and `PopoverView.swift`:

- Add `elapsedShare` and `pace` helpers (pure functions, unit-tested with fixed `now`).
  Codex duration comes from `limit_window_seconds`; Claude uses 300 and 10080 minutes.
- Show remaining percent as the headline ("68% left") with the pace glyph
  (`arrow.up.right`, `minus`, `arrow.down.right`).
- Draw an elapsed hairline on each bar and a hatched tail for the amount the next reset restores.
- Add the "+32% in 5d 3h" line under the headline using the window's used percent and the
  T3 duration format (`5d 3h`, `2h 13m`, `12m`).
- Codex account detail (hover or click): plan label from `plan_type`, email, reset time,
  restores, banked credits, Use reset. This replaces the Announcements disclosure.
- Menu bar icon and widgets keep their current semantics; only the popover changes.

### Phase 6. Claude specifics

- Nothing to redeem. Adopt Phase 5 presentation only.
- Optional zero-setup credential source, same idea as Phase 1: the Claude Code login is in the
  Keychain item `Claude Code-credentials` on this machine. Reading it triggers a Keychain
  prompt and gains no data over our existing OAuth flow, so this is low priority. Defer.
- Confirm we still parse both the legacy `seven_day_opus` style keys and the newer
  `limits[]` `weekly_scoped` entries with `scope.model.display_name`; T3 only reads the latter.

## 4. Sequencing and effort

| Phase | Scope | Rough size |
|---|---|---|
| 1 | Codex auth.json source, headers, settings copy | Small, half a day |
| 2 | Consume endpoint, confirm dialog, outcome UI, tests | Medium, one day |
| 4 | Timeouts, backoff, sleep/wake, debounce | Small, half a day |
| 5 | Pace, hairline, restores line, detail popover | Medium, one to two days |
| 3 | app-server refresh fallback | Medium, one day, optional |
| 6 | Claude presentation reuse | Small, folded into 5 |

Ship order: 1 → 2 → 4 → 5 → 3. Phases 1 and 2 together deliver the headline feature
(one-click reset with no token paste). Phase 3 only matters once someone hits a 401 in practice.

## 5. Decisions to confirm

1. Precedence when both a pasted token and `auth.json` exist. Recommendation: pasted token
   wins as an explicit override, `auth.json` is the default.
2. Whether to build Phase 3 now or wait for a real expired-token report. Recommendation: wait.
3. Whether the headline flips from "used" to "left" (T3 PR #9889). This changes the menu bar
   icon semantics if applied everywhere. Recommendation: popover only, icon unchanged.

## 7. Cursor: usage via the Cursor CLI login (probed 2026-09-09)

T3 Code reports nothing for Cursor. Probing the local `cursor-agent` CLI
(version 2026.09.02-c22c1a3, a bundled Node app under `~/.local/share/cursor-agent/versions/`)
found a clean path that removes the pasted `WorkosCursorSessionToken` cookie.

### 7.1 What the CLI exposes

- `cursor-agent status --format json` prints auth state, email, and user id. No usage.
- `cursor-agent about` prints "Subscription Tier Pro". Internally it calls two Connect-RPC
  methods on `api2.cursor.sh`: `GetMe` and `GetPlanInfo` (plan name).
- The bundle also defines, on the same `aiserver.v1.DashboardService`:
  `GetCurrentPeriodUsage`, `GetUsageLimitStatusAndActiveGrants`, `GetClientUsageData`,
  `GetAggregatedUsageEvents`, `GetTeamSpend`.

### 7.2 Credentials

The CLI stores tokens in the login Keychain through `/usr/bin/security`:

| Service | Account | Content |
|---|---|---|
| `cursor-access-token` | `cursor-user` | JWT, `scope: openid profile email offline_access`, roughly two-week lifetime (254h left at probe time) |
| `cursor-refresh-token` | `cursor-user` | refresh token |

Because the items were created by the `security` binary, a subprocess call to
`/usr/bin/security find-generic-password -s cursor-access-token -a cursor-user -w` returns the
token with no Keychain prompt. Calling `SecItemCopyMatching` directly from the app would prompt.
The CLI's own refresh route is not a literal string in the bundle and was not traced.

### 7.3 Verified live, read-only

`POST https://api2.cursor.sh/aiserver.v1.DashboardService/<Method>` with body `{}` and headers:

```
Authorization: Bearer <access token>
Content-Type: application/json
connect-protocol-version: 1
x-cursor-client-version: cli-2026.09.02-c22c1a3
x-cursor-client-type: cli
```

| Method | Result |
|---|---|
| `GetCurrentPeriodUsage` | 200. Same fields as `cursor.com/api/dashboard/get-current-period-usage`: `billingCycleStart/End` (ms epoch as strings), `planUsage{totalSpend, includedSpend, remaining, limit, autoPercentUsed, apiPercentUsed, totalPercentUsed}`, `spendLimitUsage{individualLimit, individualRemaining, limitType}`, `displayMessage`, plus `autoBucketModels[]` |
| `GetPlanInfo` | 200. `planInfo{planName: "Pro", includedAmountCents: 2000, price: "$20/mo", billingCycleEnd}` and `nextUpgrade{tier, name, price, description}` |
| `GetUsageLimitStatusAndActiveGrants` | 200. `usageLimitPolicyStatus{currentOnDemandLimitCents, onDemandMin/MaxCents, canAdjustOnDemand}` |
| `GetMe` | 200. email, user id, `isEnterpriseUser` |

Our existing `CursorUsageResponse` decoder already matches the `GetCurrentPeriodUsage` JSON
(camelCase keys, string epoch millis), so the parsing change is nil.

### 7.4 Plan for Cursor

- Add `CursorCLICredentials`: run `/usr/bin/security find-generic-password -s cursor-access-token
  -a cursor-user -w` via `Process` on each poll (cheap, no prompt). Decode the JWT `exp` to show
  "expires in Xd" and to warn before it lapses.
- Credential precedence, mirroring Codex: pasted cookie (explicit override) → CLI Keychain token
  → `CURSOR_SESSION_TOKEN` env. Settings shows the detected source.
- Switch the fetch to `api2.cursor.sh` Connect-RPC when the CLI token is the source; keep the
  `cursor.com` cookie path for pasted cookies. Reuse `CursorUsageResponse` as-is.
- Add a second call to `GetPlanInfo` for plan name, included amount, and price. Failure stays
  soft, like the Codex credits call.
- Unlike Codex there is no reset credit to redeem; the on-demand limit is adjustable server-side
  (`SetUserHardLimit` exists) but changing a spend limit from a menu bar app is out of scope.
- On 401: show "Cursor CLI login expired. Run `cursor-agent login`." Test whether running
  `cursor-agent status` alone refreshes the token; if it does, offer that as the one-click fix.
- Tests: Keychain subprocess wrapper with a stub, JWT expiry decode, precedence order, and a
  fixture from the live response above.

## 8. Plan and billing-cycle data per provider (probed 2026-09-09, read-only)

| Provider | Plan info | Billing cycle start / end | Source |
|---|---|---|---|
| Cursor | Yes: `planName`, `price` ("$20/mo"), `includedAmountCents`, `nextUpgrade{name, price, description}` | Yes: `billingCycleStart` and `billingCycleEnd` on `GetCurrentPeriodUsage`, `billingCycleEnd` on `GetPlanInfo` | `api2.cursor.sh` DashboardService with the CLI Keychain token |
| Claude | Yes: `organization.rate_limit_tier` (`default_claude_max_20x`), `organization_type`, `billing_type` (`stripe_subscription`), `subscription_status`, `subscription_created_at`, `has_claude_max/pro`; `extra_usage.monthly_limit` from usage | No. No period, renewal, or invoice field on `oauth/profile`, `oauth/usage`, or `oauth/account`. `subscription_created_at` gives the day of month for a monthly plan only as an inference | `https://api.anthropic.com/api/oauth/profile` with our existing OAuth token and the `oauth-2025-04-20` beta header |
| Codex | `plan_type` (`plus`) live on `wham/usage`; `credits.balance`, `spend_control` | No live source. The `id_token` in `~/.codex/auth.json` carries `chatgpt_subscription_active_start` and `chatgpt_subscription_active_until` claims, but `chatgpt_subscription_last_checked` was months old, so they are stale. `backend-api/accounts/check`, `me`, and `subscriptions` return 403 for both the Codex token and the pasted browser token | `wham/usage`, `auth.json` |

Implementation notes:

- Cursor: add `GetPlanInfo` (section 7.4) and show "Renews <date> · Pro $20/mo · used $X of $Y".
- Claude: add one `oauth/profile` call per poll (or once per hour, the data rarely changes) and
  show tier, subscription status, and extra-usage monthly cap. No renewal date to show.
- Codex: show plan type only. Optionally surface the `id_token` subscription window with a
  "last checked <date>" caveat, hidden when older than the current month. Do not present it as
  a renewal date.

## 9. Syncing to the Android app

Note: local `main` is 20 commits behind `origin/main`, which holds the Android app and the
device-sync code (PRs #29 to #43). Pull before implementing anything below.

### 9.1 The two models

**Ours today (origin/main).** The Mac runs `LocalDeviceSyncServer` on TCP 48321. The phone
scans a one-time QR (`agentusagebar://pair/v2?...`), the two sides do an ECDH key exchange, and
the Mac pushes an encrypted `DeviceSyncPayload` (settings, notification thresholds, and the
OpenAI, Cursor, and ElevenLabs tokens; 10 minute validity). The phone then calls the provider
endpoints itself from `UsageApiClient.kt`, does its own Claude OAuth, refreshes on a WorkManager
schedule (15 minute floor), and polls the Mac's `/v2/status` for sync or wipe commands. The
pairing code embeds the Mac's LAN IPv4, so pushes only land when both are on the same network.

**T3 Code.** The phone is a thin client of the desktop server over a websocket, reached by LAN
or tailnet pairing or by their hosted "T3 Connect" relay. The server owns every credential,
streams usage-limit snapshots to the phone, and executes reset-credit redemption as an RPC.
The phone never holds a provider token, but it shows nothing when the host is asleep or
unreachable.

Recommendation: keep our model. It already works off-network between syncs, needs no relay,
and the Android widgets already render from a local snapshot store. Borrow only T3's idea of
shipping a usage snapshot alongside, so the phone has data the instant it pairs.

### 9.2 Changes

1. **Payload v2** (`DeviceSyncPayload.swift`, `DeviceSyncPayload.kt`, codec test):
   - `codexAccessToken` and `codexAccountId` from `~/.codex/auth.json`. Never sync the Codex
     refresh token: it rotates on refresh, and a phone-side refresh would invalidate the Mac's
     CLI login.
   - `cursorAccessToken` from the Keychain item, and a `cursorSource` flag so the phone uses the
     `api2.cursor.sh` Connect-RPC path for CLI tokens and the cookie path for pasted cookies.
   - Optional `snapshot`: last usage per provider, plan info, billing cycle dates, credits.
     Lets the phone render immediately and serves as a fallback when its own fetch fails.
   - Bump `currentVersion` to 2; the Android decoder must accept version 1 payloads.
2. **Automatic re-sync on rotation** (`DeviceSyncManager.swift`): on each Mac poll, hash the
   Codex access token and the Cursor Keychain token. When either changes, queue a sync for every
   trusted device through the existing resync path (PR #30). The phone picks it up on its next
   `/v2/status` poll. Show "phone tokens expire in Xd" in the Mac's Devices settings using the
   JWT `exp` claims.
3. **Reach from anywhere with the tailnet.** Both this Mac and the Pixel 10 Pro are already on
   the same Tailscale network. `NWListener` binds all interfaces, so the server is reachable at
   the 100.x address today; only the advertised host is LAN-only. Change `beginPairing` to
   prefer the tailnet address when present and to include the LAN address as a fallback, and let
   `TrustedDeviceStore` keep both, trying tailnet first. Zero infrastructure, and rotation
   syncs land even when the phone is away.
4. **Reset credit from the phone.** Add the same `POST .../rate-limit-reset-credits/consume`
   to `UsageApiClient.kt` with the same confirm dialog and outcome copy. Use one shared UUIDv5
   namespace constant on both platforms so a Mac retry and a phone retry of the same credit
   produce the same `redeem_request_id` and dedupe server-side.
5. **Plan and billing on the phone.** Add `GetPlanInfo` for Cursor and `oauth/profile` for
   Claude to the Android client with the synced tokens, and pass the values into
   `WidgetSnapshotStore` so widgets can show "renews in 12d".
6. **Expiry handling on the phone.** On a 401 from a synced CLI token, show "Token expired.
   Open Agent Usage Bar on your Mac to re-sync" instead of the current "update it in Settings",
   since the fix now lives on the Mac.

### 9.3 When to revisit T3's model

Switch to Mac-as-source-of-truth only if you decide the phone must never hold a bearer token.
The cost is a relay or an always-awake Mac on the tailnet, a websocket or push channel for
snapshots, and redemption as a command the Mac executes. Not worth it for a single-user app.
