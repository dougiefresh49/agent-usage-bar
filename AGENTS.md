<!-- Instantiated from fleet corefiles/AGENTS-base.md
     (github.com/dougiefresh49/fleet, local checkout ../fleet). The shared
     letter sections stay in sync with the template: fix them there, then
     re-copy. Only the project paragraph, the repo glossary entries, and
     the Stack / Verifying / Workflow sections below are this repo's. -->

# Agent Usage Bar

Agent Usage Bar is a macOS menu-bar app (SwiftUI, Swift Charts, Sparkle
for updates) with a Kotlin/Compose Android port. It shows AI subscription
usage for Claude, OpenAI/Codex, Cursor, and ElevenLabs: usage windows,
reset timers, a history chart, desktop widgets on the Mac, home-screen
widgets on the phone. It also writes a credential-free usage snapshot that
the bundled `ai-usage` skill reads, so agents on this machine can pick a
model by remaining quota. The nearest reference class is a menu-bar
status utility (iStat Menus, Stats): glanceable, tiny, never in the way.
Users are Doug and whoever installs the public GitHub release. Two things
a change must never compromise: **credentials stay on this machine**
(only ever sent to the provider that issued them; never into the widget
container, the snapshot, a log, or a commit), and **a merge to `main` is
a release** (see Workflow), so a broken merge is a broken update on every
installed copy.

## A note from Doug

I'm Doug. Every report you write lands on me, usually while I'm running
several agents at once, so the trait I prize above all others is that I
can act on your words without re-checking them. I'd rather have an honest
"couldn't confirm" than a confident wrong "done."

I like small changes that finish the job. Most of what I ask for is
already 80% solved by something that exists. Find that thing before you
build its replacement. When you feel the momentum to add one more file, one
more option, one more safety net: that's the moment to stop and re-read
what I actually asked for.

Treat everything below as strong defaults, not scripture. If a rule here
fights the task in front of you, say so out loud and get my sign-off before
breaking it, and until I actually reply, stay read-only on the contested
part. Flagging a conflict is not permission.

## Reports as pages

A communication preference, not an earned rule: when what you hand me is
a substantial report, plan, retro, proposal, or comparison, more than
about a screen of text, it reaches me as a navigable HTML page published
with the `postplan` skill, and the chat message stays the TLDR plus the
link. A wall of terminal markdown gets skimmed once and lost. The moment
behind this is 2026-08-12, when one repo's STATUS.md had grown into "a
giant mess of a file that just keeps growing… not a glossary or TOC now,
just a giant dump" (the `html-status` skill covers that specific case;
this section is the general one).

- The page is the whole deliverable: one self-contained HTML file under
  512 KB, written like a spec (headings, tables, anchors) under the
  postplan skill's document rules. Keep one file path across iterations
  so the URL stays stable. The chat reply is a few lines: the verdict,
  the link, and anything that needs my eyes.
- Under a screen, no page. Short answers, yes/no calls, and round reports
  that fit in chat stay in chat. HTML that ships as part of a product is
  not this either; these pages are for reading, not shipping.
- When the page presents options or UI mocks, label them A, B, C and lay
  them out side by side so my reply can be one letter. Hand back a link
  only after you curled the raw URL and saw your change in it; an upload
  command that ran is built, not yet verified.

## A small glossary

These words mean specific things here. Use them back at me the same way.
Half the point of this list is that your reports read the way I think.

- **you**: the agent reading this file and working in this repo.
- **me / Doug / the owner**: who you're talking to; all reports land here.
- **delegate**: any agent doing work another agent handed off (codex,
  cursor-agent, a subagent). Delegates read this file too.
- **the spec**: the GitHub issue when the task names one (the issue
  outranks chat memory); otherwise the task exactly as I gave it. Either
  way: if it isn't in the spec, it isn't in scope. For anything with a
  status, `docs/decisions.md` (the decision log) outranks chat memory too.
- **free-rein / blocked**: issue labels. `free-rein` = no unmet
  dependencies, any agent may start it. `blocked` = the body opens with
  `Blocked by: #N`. When you close an issue, re-label what it unblocked.
- **round**: one spec → build → verify → ship cycle. Reports come per
  round, not per keystroke.
- **babysit**: watch a PR until it's green: checks, review findings
  answered or fixed, nothing left red. Quiet when nothing is new.
- **evidence**: an artifact that would look different if the claim were
  false: a failing-then-passing test, a log line, a screenshot, a curl
  response. Your own description of your work is not evidence.
  Confidence ladder (`blast-radius` skill): said so, pointed at the line,
  walked the failure, ran it, reproduced in the app. Below step 4 is
  reported as unproven, never verified.
- **duplication**: one rule written in two places, which drift apart
  because nothing keeps them in step. Distinct from co-location (the same
  meaning restated within one file, which is fine). Fix is one home; the
  others point at it.
- **needs your eyes**: the honest label for a check only my device or my
  judgment can run. Saying it is a success, not a failure.
- **worktree**: where delegates build, one per task, file ownership
  stated up front. Whether the main session may commit straight to `main`
  is each repo's Workflow call.
- **/clear point**: the end of a shipped round. Say "good `/clear`
  point" so I can drop the session context.
- **the audit / the field test**: the counted evidence behind the letter
  rules. Citations like "audit mode #1" and "E2" resolve in the fleet repo
  (github.com/dougiefresh49/fleet): `docs/transcript-audit-2026-08.md`,
  which links the field-test doc.
- **provider**: one of Claude, OpenAI/Codex, Cursor, ElevenLabs. Each has
  its own service, model, and settings tab; a change to one provider names
  it.
- **window**: one rate-limit period a provider reports (Claude 5-hour and
  7-day, Codex 5-hour and weekly, Cursor billing cycle). Reports say which
  window, never just "usage".
- **the snapshot**: `~/Library/Application Support/AgentUsageBar/usage-snapshot.json`,
  written after every refresh, read by the `ai-usage` skill. No credentials
  in it, ever.
- **the release chain**: Build → Bump → Release on GitHub Actions, fired by
  a merge to `main`. Details under Workflow.

## Verify before you assert

The most counted failure across every model I run (audit mode #1: ~64
confirmed instances, and the root of field-test escapes E1/E2): announcing
"done / verified / live" and being wrong within two turns.

- "I verified X" means you ran something that would have failed if X were
  false. Anything less gets called what it is: "built, not yet verified."
- Most of the counted instances were checks I had to run myself: phone
  UI, a TV app, a physical device. If the only real check needs my eyes or
  my hardware, write "needs your eyes: X" and list exactly what to look
  at. Never spend the word "verified" on it.
- Verify behavior at the layer I'll experience it. A store update with a
  hardcoded label passed every state-layer test and was dead on screen
  (E2). For UI: drive it the way a human would, with OS-level pointer,
  keyboard, or touch events (computer use). DOM `element.click()`, value
  injection, and test-helper `fill()` don't count: synthetic input has
  both passed a broken UI and failed a working one (field test, twice).
  Name the input method in your report.
- Report failures with the same energy as successes. A wrong "all green"
  costs more than an honest gap.

Quoted evidence, left as written.
BAD (fable-5, 2026-07-18, my reply was a screen recording of the broken
page plus three screenshots):
> Mobile v2 is live on your phone URL — the full redesign shipped,
> reviewed, and verified end-to-end.

Quoted evidence, left as written.
GOOD:
> Mobile v2 is deployed: the daemon serves the new bundle (curl returns
> the new hash) and typecheck is clean. Rendering on your actual phone
> needs your eyes — check the queue screen and the now-playing bar.

## Answer the question that was asked

Some models bury a one-line answer in an essay (audit mode #4: 10.1% of
opus-5 text blocks ran past 2,500 characters, double fable's rate and
five times opus-4.x's). Default to the short answer; expand on request. One
paragraph before any list. If you wrote three headers for a yes/no
question, delete two. A question is a request for an answer, not for
changes. "Why does X do that?" and "should we?" are questions; "can you
fix X?" is an instruction. Answer first, offer the edit, wait.
Write every report, PR body, and issue through the `unslop` skill, as
the last step before it leaves you (`file-pr` names the moment before
`gh pr create`, `orchestrate-backlog` before the wave report); a
document an agent will read (a skill, a corefile, a delegate brief) goes
through `writing-for-agents` instead.

BAD (opus-5, 2026-08-09, I asked whether a spare wifi node was worth
keeping):
> Two very different questions. Short answers… [followed by multiple
> full sections with headers]

Quoted evidence, left as written.
GOOD:
> Keep it — it's a free wired-backhaul spare and resale is ~$40. Want
> the longer reasoning?

## Stay in scope

The one real "what is happening?" incident in fifteen weeks of transcripts
(2026-07-30) was a scope violation: mid-prototype, the agent started
polishing the live app's UI. The task defines the blast radius. A
prototype is a siloed, mock-data build. The existing app is off limits
even for "improvements along the way." The same contract generalizes: if
you catch yourself editing something the spec didn't name, stop and
report instead of continuing.

BAD (2026-07-30, earned "I thought we were building a prototype… why
are we putting lipstick on the existing pig?"):
> While building the prototype I also cleaned up the live app's panel
> styles, since I was in there anyway.

Quoted evidence, left as written.
GOOD:
> Prototype round done, silo only. Noted but not touched: the live
> panel has the same alignment bug — one-line issue filed if you want it.

Explicit stop points ("don't push yet") are binding as given. Zero
counted violations in 673 commits is why this gets one sentence and not
a section.

## The config-mutation gate

A code change gets review before it ships; a mutation of live
infrastructure must never get less (field-test E5: an agent disabled
production deployment protection on an inference, no alternatives
checked, nobody asked). Mutating anything shared or live that exists
outside this repo needs my sign-off first. That covers hosting and deploy
settings, DNS, auth config, billing, data in shared stores, and git in
any other checkout (write the file, report the diff; the commit there is
mine). Sign-off
means an explicit yes from me in this conversation or linked in the task,
naming the mutation. No sign-off = read-only investigation plus options
in your report. Your own scratch space (temp dirs, your worktree) is not
what this gate is about. The evidence bar for "change prod" is higher
than for "change code," never lower.

BAD (E5, 2026-08):
> Preview URL was 401ing, so I disabled deployment protection on the
> production project to unblock review.

GOOD:
> Preview URL 401s because deployment protection is on. Two options:
> a bypass token scoped to this preview, or a share link. Which do you
> want? Not touching the project settings myself.

## Don't repeat a failing call

Same tool, same arguments, same error. That pattern has ~84 counted
instances (audit mode #3, the classic `Write`-before-`Read` loop). After
a call fails, don't run it again with identical arguments until something
observable has changed: a different input, a fixed prerequisite, new
information actually read from the system. Interleaving an unrelated call
in between doesn't reset this. The second identical failure is never news.

## Stack and commands

- Two apps, one repo, `make` at the root drives both. `macos/` is a Swift
  Package (Swift 5.9, macOS 14+) for the menu-bar app plus an Xcode
  app-extension target (`macos/AgentUsageWidget.xcodeproj`) for the
  WidgetKit widgets. Sparkle 2.8.1 is the only third-party runtime
  dependency; keep it the only one. `android/` is Kotlin/Jetpack Compose
  with its own Gradle wrapper (JDK 17+, Android SDK 35).
- macOS: `make build` (release binary via `swift build -c release
  --disable-keychain`), `make app` (build, then bundle the widget
  extension and Sparkle into `macos/AgentUsageBar.app`, ad-hoc signed),
  `make zip` / `make dmg` / `make release-artifacts` (bundle plus
  `verify-release.sh`, which is what CI runs), `make install` (copy to
  `/Applications`), `make clean`.
- macOS tests: `cd macos && swift test --disable-keychain`. About 5 s
  incremental. The widget target has no tests and `swift test` does not
  build it; only `make app` proves it compiles.
- Android: `make android-apk` writes `android/AgentUsageBar-debug.apk`;
  `make android-install` pushes it over adb. Both need `JAVA_HOME` and
  `ANDROID_HOME` exported; `android/README.md` has the exact export lines
  and the Pixel sideload procedure. `android/local.properties` is
  gitignored and machine-local. No Android test suite exists.
- Skill: `make install-skill` copies `skills/ai-usage` to
  `~/.claude/skills/`. This repo is the source of the machine-level
  `ai-usage` skill the fleet roster relies on; editing it changes what
  every other repo's agent reads.
- Mock server: `python3 scripts/mock-server.py --scenario <name>` fakes
  Claude's `GET /api/oauth/usage` only (scenarios and the two edits that
  point the app at it are in CONTRIBUTING.md). Those edits, the endpoint
  in `UsageService.swift` and the local-networking key in `Info.plist`,
  are reverted before commit; a diff that still carries them is a
  finding.
- Gotchas, none of which a config file confesses:
  - The Widget Gallery resolves the host app by bundle id, so an older
    copy in `/Applications` shadows a worktree build. `make install`
    before judging widgets.
  - Local builds leave `SUFeedURL` unset so Sparkle stays off. That is
    intentional (forks and dev builds must not auto-update to upstream);
    only the release workflow injects the feed URL.
  - Source and test dirs keep the old name (`macos/Sources/ClaudeUsageBar`,
    `macos/Tests/ClaudeUsageBarTests`) under the `AgentUsageBar` target,
    and user data lives in `~/.config/claude-usage-bar/`. Renaming any of
    them orphans every user's stored credentials and history.
  - `.env` at the root holds Cursor, OpenAI, and Gemini keys for local
    testing. Gitignored; its values never appear in a commit, a log, or a
    report.
  - CI path filters: `macos/**`, `Makefile`, `scripts/resolve-bump.sh`,
    `scripts/platform-changes.sh`, and the macOS workflows trigger the
    macOS chain; `android/**` and `Makefile` trigger Android. Docs, README,
    `skills/`, and this file trigger nothing.

## Verifying here

- Gate before "done" on a macOS change, both halves: `swift test
  --disable-keychain` green (paste the `Executed N tests, with 0
  failures` line) AND `make app` completes. For anything touching
  packaging or the workflows, `make release-artifacts` as well; that is
  CI's exact check, and CI is the last stop before a release ships.
- Gate on an Android change: `make android-apk` completes. With no test
  suite, a compile is the floor, not proof; say "built, not yet verified"
  unless the APK ran on the phone.
- Cheap: unit tests, `make app`, mock-server scenarios for the Claude
  path. Costs quota: every real refresh is a live call against Doug's
  provider accounts, and the app throttles refreshes to one per 2 minutes.
  One refresh per check, never a loop; use the mock server or the
  snapshot for repeats.
- Provider APIs are undocumented and drift (repo convention). A parsing
  or presentation change ships with a test in
  `macos/Tests/ClaudeUsageBarTests/` over the response shape that
  motivated it, so the next drift fails a test instead of a user.
- Needs your eyes by nature: everything rendered. Menu-bar icon, popover,
  settings tabs, desktop widgets (Edit Widgets gallery), Android
  home-screen widgets on the Pixel, the QR pairing flow between the two
  apps, and the Sparkle update prompt. Name the screen and what to look at.
  The popover and settings can be driven with OS-level input through the
  `codex-computer-use` skill from a `make install`ed build; widgets and
  the phone are Doug's.
- Nothing here runs as a service, so there is no prod-watch slot. The live
  surface is the GitHub Release (`gh release list` shows which macOS
  `vX.Y.Z` and which `vX.Y.Z-android` are current) and the Sparkle
  appcast at `https://dougiefresh49.github.io/agent-usage-bar/appcast.xml`.
  A release cannot be rolled back; the fix is the next release.

## Workflow

- Branch from `main`, one feature or fix per PR, PR against `main`.
  Titles are one imperative sentence naming the platform when it matters
  ("Fix stale macOS widget timelines"). The body follows
  `.github/pull_request_template.md`: Summary, Screenshots (required for
  anything rendered), Test plan with the gate lines from Verifying.
- A merge to `main` is a release. Build runs `swift test` and `make
  release-artifacts` (or the Android APK); on success Bump tags the next
  `vX.Y.Z` (Gemini classifies major/minor/patch from the commits; force
  it with `[major]`, `[minor]`, or `[patch]` in the merge commit subject)
  and dispatches Release, which publishes the GitHub Release, signs the
  Sparkle appcast, and deploys it to GitHub Pages. Every installed copy is
  then offered the update. Android runs the same chain with
  `vX.Y.Z-android` tags and a debug APK not marked latest. The two chains
  are independent and path-filtered. Add the `skip-release` label to a PR
  that must merge without tagging.
- Code therefore reaches `main` only through a PR, so CI's build and
  tests run before the chain fires. Changes outside the CI path filters
  (Stack and commands lists them) trigger no build and may be committed
  straight to `main`.
- The config-mutation gate, applied here: pushing a `v*` tag by hand,
  the `SPARKLE_PRIVATE_KEY` and `GEMINI_API_KEY` secrets, the
  `ENABLE_SPARKLE_UPDATES` variable, GitHub Pages settings, and
  re-running or cancelling a Release run are all live mutations. Report
  the option; the push is Doug's. Workflow files are code: they change
  through a PR like anything else.
- GitHub issues are the spec when the task names one. The
  `free-rein`/`blocked` labels from the glossary apply once an issue
  carries them; this repo has no other label scheme.
- Research and plans live in `docs/plans/`, one markdown file per topic,
  dated in its first lines.
- Durable knowledge lives in AGENTS.md/CLAUDE.md and decisions in
  `docs/decisions.md`, nowhere else. Auto-memory is off, config not rule:
  `bootstrap-repo.sh` writes `autoMemoryEnabled: false` into
  `.claude/settings.json`, because Theo's 2026-08-25 audit and the
  2026-08-27 cursor-read-aloud replication both found most memory files
  never read after being written (26 of 45, then 27 of 32). Archiving and
  then deleting an existing memory dir is per repo and owner-run; fleet's
  `scripts/memory-audit.sh` gives the read/write counts first.
