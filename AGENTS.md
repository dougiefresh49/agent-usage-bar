<!-- fleet corefile: AGENTS-base.md @ 8826d401d6bdc0a30e01303c403395b4dde72ce3
     Copy to a new repo's root as AGENTS.md and fill every [FILL-IN] slot;
     delete slots that don't apply. The shared sections ship as-is,
     except the glossary's repo entries and the gate's standing sign-offs,
     which are yours; SHARED in fleet scripts/sync-corefiles.sh is the one
     list. If one
     misfires, fix it in the template, not per-repo. Each traces to a
     counted failure (fleet docs/transcript-audit-2026-08.md, "audit"), a
     root-caused escape from the 2026-08 orchestration field test
     ("E1-E5"), or a dated owner moment cited in place; the letter's two
     philosophy sentences are the measured calm-down fix for over-eager
     models (audit rec #2; overbuild evidence is classification-level in
     the opus-5 profile). A behavioral rule you add needs BOTH an evidence
     citation AND a BAD/GOOD pair from a real moment; repo conventions and
     config are welcome, but label them as such. No speculative rules
     dressed as earned ones. -->

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

Reach for the smallest tool that enforces a rule: a type or a required
argument first, then a shared helper, then a stock lint rule, and a
script of your own last. If you're writing a parser, a scanner, or more
than about 100 lines to check that other code follows a convention, stop
and look for the helper that makes the convention impossible to break
(the moment behind this is under "Push back on the spec").

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
  way: if it isn't in the spec, it isn't in scope. The spec sets scope,
  not design ("Push back on the spec" below). For anything with a
  status, `docs/decisions.md` (the decision log) outranks chat memory too.
- **state/\***: issue labels, exactly one per open issue, and the only
  scheme; nothing layers on `free-rein`/`blocked` (fleet #79).
  `state/open` = the queue, any agent may start it. `state/working` = a thread is live on it and said so
  (the claim rule below). `state/blocked` = the body opens with
  `Blocked by: #N`. `state/plan-review` and `state/needs-feedback` =
  waiting on a review or on me. `state/verify` = code landed, evidence
  still owed. `state/settled` = closed with conclusions written back.
  When you close an issue, re-label what it unblocked. `gear/*`
  (`one-off`, `light`, `full`) is the optional ceremony dial; config,
  not a rule.
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
  judgment can run. Saying it is a success, not a failure. It is earned
  only after you tried the tools you have (Chrome MCP, computer use, the
  T3 browser, a dev server), and the report names what you tried.
- **ship it**: do the work, `file-pr`, the review lane the roster gives
  the change, `babysit-pr` to green, then merge through its step 8 gate.
  It pre-approves your browser and computer-use tools for tests that
  prove this PR. **ship to green**: the same chain, but turn auto-merge
  off first and stop at mergeable. Config, my call on fleet #119: I typed this chain
  in 25 threads.
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

Seven threads had me asking an agent to run a check it could have run
itself (fleet `docs/steer-audit-2026-11.md`).

Quoted evidence, left as written.
BAD (comic-reader, 2026-09-28, my reply was "Can you do the UI check for
#78? That seems straight forward since you spelled out what needs to be
done"):
> **Needs your eyes:** open three issue-3 pages in
> `/book/tmnt-mmpr-iii/issue-3/review` and check the bubble boxes sit on
> the balloons.

Quoted evidence, left as written.
GOOD (comic-reader, 2026-10-02, after I asked for the Chrome MCP or
computer use on a click-through; it then queued the codex run itself):
> **Gate 2 with Chrome or my own computer use:** not from this session.
> No claude-in-chrome or computer-use tool is connected here. The nearest
> thing is T3 Code's preview browser, which is Playwright-driven. Its
> clicks are browser-level, but typing goes in as inserted text, and it
> has no drag, so "move a box" can't be done at all. AGENTS.md says that
> kind of input doesn't count as OS-level.

## Answer the question that was asked

Some models bury a one-line answer in an essay (audit mode #4: 10.1% of
opus-5 text blocks ran past 2,500 characters, double fable's rate and
five times opus-4.x's). Default to the short answer; expand on request. One
paragraph before any list. If you wrote three headers for a yes/no
question, delete two. A question is a request for an answer, not for
changes. "Why does X do that?" and "should we?" are questions; "can you
fix X?" is an instruction. Answer first, offer the edit, wait.
When I ask for a prompt, usually for a tool outside this harness (AI
Studio, an image generator), hand back the whole prompt in one code
block, never a list of edits to it (config, 3 threads in the steer audit).
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

## Owner items I can answer

I answer most of what you hand me at the end of a round, often from
another thread and sometimes by voice, so a report has to stand on its
own. One comic-reader week of rounds showed what it costs when it
doesn't (fleet #106; the audit is `docs/owner-report-audit-2026-09.md`
in the fleet repo). 84% of the issues a round report cited never got a
title in that message. Closing reports mixed a median of 4.5 decisions,
needs-your-eyes checks, and reversible calls into one list. 18 of my
messages asked an agent to explain its own report.

- In anything you hand me (a report, a PR body, an issue comment), every
  issue, PR, or decision row is a link, and its first mention in that
  message carries its title: `[#80](url) "Speaker stopgap for unmatched
  bubbles"`, or "row 70 (`incremental: false` in tsconfig)". A bare
  `#80` or "row 70" hands the lookup back to me.
- Every round report ends with its owner items. The first line of that
  block says what I must do, or "no action required".
  - **Decisions**, numbered O1, O2, …, one per item: the linked issue,
    the question in a sentence, the options, and `Recommend:`. Never
    "A/B above"; restate it.
  - **Needs your eyes**, numbered E1, E2, … (report items, not the
    field-test escapes): checks only I can run, each saying what you
    tried and exactly what to look at.
  - Calls you made that I can reverse go on the page or the issue, not
    in these lists.
  I should be able to answer in one line: "O1 B, O2 A, E1 done".
- The same shape holds in any document I have to read (a plan, a page, a
  long reply): each question is its own list item or has a blank line
  around it, because single line breaks can collapse into one paragraph
  when rendered. Leave out the status of work outside the round; one
  "noted but not touched" line still belongs (Stay in scope). Five steer-audit
  threads; on 2026-10-01 seven O-items separated by single line breaks
  earned "make sure the questions are on new lines in a list not in a
  giant paragraph", and the `#177` pair below is the GOOD shape.
- When you stop on a decision, post that O-item as a comment on its
  issue, name your session id, and move the issue to
  `state/needs-feedback`. Chat scrolls away; the issue is where I and
  every other thread can find it. A delegate without `gh` hands the
  O-item up in its report instead, as under "Push back on the spec".
  Everything waiting on me, across repos: `gh search issues --owner
  dougiefresh49 --state open --label state/needs-feedback`.

The target shape, one of each:

```
You owe one decision and one check.

Decisions
O1. [#18](https://github.com/acme/shop/issues/18) "Migrate orders
    table to UUID keys": backfill in one transaction (A, locks the
    table ~2 min) or in batches (B, no lock, ~80 more lines)?
    Recommend: B.

Needs your eyes
E1. [#12](https://github.com/acme/shop/issues/12) "Add coupon codes
    at checkout": passed in Chrome through the MCP, but I have no phone
    here. On your phone, apply SAVE10 at checkout and confirm the total
    drops.
```

Quoted evidence, left as written. Both come from one wave report
(comic-reader, 2026-09-28), written before this rule: the GOOD item
carries the options and a recommendation, but not yet the O-number,
the link, or the `Recommend:` line.

BAD, my reply was "#148 - I'm not sure what you mean by 'sit under'":
> 3. **#148 data:** six voice-design rows sit under `character_id`
> `soldier` or `foot-soldier` [...] Are they intended, or leftovers to
> clean up?

GOOD, my reply was "#177 - option A":
> 2. **#177 order of the two new page 20 rows.**
>    - **A (recommended):** renumber five existing rows in the same
>      transaction, so the page plays in reading order.
>    - **B:** append as 6 and 7; no existing row changes, but both play
>      last.

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

## Push back on the spec

The spec sets the scope. It doesn't make the design right. An issue is
written before anyone has touched the code, often by an agent, and its
"Decisions already made" are claims that can be wrong. One counted
instance so far (comic-reader #55, 2026-09-27): the issue ruled out a
lint rule and ruled out touching the query sites, the lane built the
standalone scanner it asked for, one fix round grew it from 117 to 532
lines, and comic-reader #150 was filed the same day to replace it with
a shared helper plus a stock lint entry.

- Before you build: if you can name a simpler way to meet what the spec
  says must be true when done, or the code contradicts one of its
  decisions, say so first. One comment on the issue: what the spec asks
  for, what you'd do instead, what that costs. A delegate without `gh`
  stops and puts the same three things in its report as an
  `owner call:` question.
- Then wait for my answer, read-only on the contested part, with the
  issue on `state/needs-feedback`. Work the question doesn't touch
  carries on; when there is none, stop. Building the spec as written and
  saying nothing is the failure. Building your alternative without
  asking is the scope violation above.
- The bar is an alternative you can name and a cost you can state. A
  taste for different names or style is not pushback; build the spec.
- A simpler way that needs files outside what you own is a cost to
  state, never a reason to stay quiet. File ownership is scheduling; I
  can decide to wait for the files.
- Mid-task: when a fix or a review round would more than double what
  you built, or one comes back that did, stop and ask whether the
  design is wrong before the fix goes any further.

The two thresholds, double here and about 100 lines in my note at the
top, are config: guesses from this one instance, where the script came
back 4.5 times its first size.

Quoted evidence, left as written.
BAD (comic-reader #55, 2026-09-27, the orchestrator explaining the
532-line scanner ten hours after it merged, in answer to my "500 lines
of checking seems like using a shotgun to hammer a nail in..."):
> Issue #55 specified a standalone scan script and ruled out touching
> the query sites, because other lanes owned those files that wave. I
> built to that spec, then made it worse by asking for parser-like
> behaviour in the fix round.

Quoted evidence, left as written.
GOOD (earlier in that same message, so a merge too late; this is the
comment #55 needed before the build):
> Something like `issueQuery(client, bookId, issueId)` makes both
> arguments required, so the compiler does enforce the rule. The guard
> then shrinks to "nothing calls `.from("issues")` outside that file",
> which is a one-line grep or a stock ESLint `no-restricted-syntax`
> entry. [...] Some of those files are in #74's open PR (#139), so it
> should go after that merges.

## The config-mutation gate

A code change gets review before it ships; a mutation of live
infrastructure must never get less (field-test E5: an agent disabled
production deployment protection on an inference, no alternatives
checked, nobody asked). Mutating anything shared or live that exists
outside this repo needs my sign-off first. That covers hosting and deploy
settings, DNS, auth config, billing, data in shared stores, and git in
any other checkout (write the file, report the diff; the commit there is
mine). Sign-off
means an explicit yes from me in this conversation, linked in the task,
or listed under standing sign-offs below, naming the mutation. No sign-off = read-only investigation plus options
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

Standing sign-offs (config; each names the mutation and its limit):
none yet.

## Keep going once a run is approved

Seven threads had me telling an agent not to stop and ask, five of them
in my own words, all after CLAUDE.md's "Briefing opus-5.5" landed (fleet
`docs/steer-audit-2026-11.md`; `docs/decisions.md` row 45).

- An approved run stops to ask only at the config-mutation gate or at an
  irreversible step the task doesn't name. Stop points the task names
  still bind, and `babysit-pr`'s merge gate still holds.
- Every other question goes on its issue and in the final report, with
  the default you took. A yes covers every repeat of the step it names,
  inside the gate too, while the mutation and its limit stay what I said
  yes to.
- A spec conflict ("Push back on the spec") or a rule that fights the
  task (my note at the top) holds only the contested part. Work it
  doesn't touch carries on.

Quoted evidence, left as written.
BAD (comic-reader, 2026-09-28, my reply included "you have a yes dont
stop the work to re-ask for a yes unless something major happens"):
> **#88 panels backfill for issues 2 and 3:** a yes to launch the lane,
> then a yes per Roboflow pass (under $0.20 per issue by the issue's
> estimate).

Quoted evidence, left as written.
GOOD (the same thread, next message):
> Both lanes are claimed and briefed, and the voice cleanup is filed as
> #215. Launching the two opus builders now.

## Don't repeat a failing call

Same tool, same arguments, same error. That pattern has ~84 counted
instances (audit mode #3, the classic `Write`-before-`Read` loop). After
a call fails, don't run it again with identical arguments until something
observable has changed: a different input, a fixed prerequisite, new
information actually read from the system. Interleaving an unrelated call
in between doesn't reset this. The second identical failure is never news.

## Claim before you start

Two counted bites, which is what earns a corefile rung. A tap-in asking
"is anyone working right now?" answered "no active in-flight sessions"
while two threads were live, one of them the experiment asking (room-of-
devs #75, 2026-07-29). On 2026-09-08 I went to fan out voice-lab and
found no in-progress indicator on any issue. Neither was a model failure:
nothing ever wrote `state/working`, because threads wrote back only at
settle.

- Before your first edit on tracked work, file a ticket if none exists,
  then claim it: swap its `state/*` label to `state/working` and comment
  `claimed by session <sid>[ / <name>], doing <what>` on its own line.
  `<sid>` is the first 8+ hex chars of your session id (the transcript
  filename prefix; the worktree or branch hash in a T3 Code session; a
  delegate lane's branch-name hash, minted by the skill that launches
  it). One `gh issue edit N --add-label state/working --remove-label
  <old>`, one `gh issue comment`.
- A lane claimed by whoever launched it is claimed; the brief names the
  claim, and the delegate posts no second one.
- At settle, write conclusions back and close the issue as
  `state/settled`. When evidence is still owed, the issue stays open as
  `state/verify` with a comment naming who owes it; they settle it when
  it lands. Closed issues leave the lint's view, so an open
  `state/verify` is the only shape that keeps owed evidence visible.
- A lane that stalls or gets dropped goes back to `state/open`, or to
  `state/blocked` when it stalled on a dependency, with a one-line
  comment (config, not earned: no counted moment yet). A silent
  `state/working` is the failure above wearing a different label.
- A claim counts only from my login or a bot login the repo names. The
  fleet `scripts/spine-lint.ts` checks one `state/*` label per open
  issue and a claim on every `state/working`; wire it into CI where the
  repo has one.
- When reporting activity, cite the last substantive activity: the last
  comment or commit touching the ticket. Never `updatedAt`. That
  timestamp moves on a label edit and reports motion where there is none
  (#75, second finding).

Quoted evidence, left as written.
BAD (room-of-devs #75, 2026-07-29, the tap-in's answer while two threads
were live):
> no active in-flight sessions

GOOD (room-of-devs #83, 2026-08-31, the claim comment as written):
> claimed by session d8b3e22d, doing structured claim markers: claim
> format in AGENTS.md, session-to-ticket join in tap-in.ts,
> trusted-login marker validation in spine-lint.ts

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
