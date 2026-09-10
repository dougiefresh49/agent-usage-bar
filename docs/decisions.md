# Decisions

One line per decision, newest first. The format and the status vocabulary
are the `decision-record` skill's; AGENTS.md Workflow says decisions live
here and nowhere else. This log starts 2026-09-09 with the owner
decisions in tracking issue #58; calls that predate it live in AGENTS.md
as prose or were dropped, not backfilled.

| # | date | decision | status |
|---|------|----------|--------|
| 17 | 2026-09-10 | #54 popover pace: overview capsules keep the compact used-percent text and only the per-window headline and detail rows switch to "left", reading owner decision 3's "headline only" narrowly (#68) | assumed (reopens when: Doug says the overview cards should read "left" too) |
| 16 | 2026-09-10 | #54 popover pace, the question at fix dispatch 3: the design holds; the open finding (Codex additional rate-limit rows still plain used-percent) is an implementation miss against "each window metric gains geometry", so dispatch 3 goes out for that row only (#68) | accepted |
| 15 | 2026-09-10 | Overnight #58 run: one Sol round per PR is the gate from wave 2 on (the lane's own, with a coverage table over every spec bullet); the orchestrator re-reviews only a PR whose lane gate could not run, and grok via cursor-agent is the overflow reviewer while codex is capped, because seven lane gates plus four re-reviews took codex from 32% to 48% weekly and capped its 5-hour window | accepted |
| 14 | 2026-09-10 | Overnight #58 run: the Sol review gate runs `codex -m gpt-5.6-sol` at high reasoning, not the local codex config's pinned default `gpt-6-astra`, because the run brief names Sol and the roster has no row for astra | assumed (reopens when: Doug names the codex review model, or adds astra to the roster) |
| 13 | 2026-09-10 | Overnight #58 run: no lane, reviewer, or verifier calls the Codex reset-credit consume endpoint against a real account; the RFC UUIDv5 vector and stubbed sessions are the whole check, and the #56 computer-use round opens the confirm dialog and presses Cancel only | accepted |
| 12 | 2026-09-10 | Overnight #58 run: a red main after a merge gets a fix lane at once on a `fix-<what>` branch through the same review gate, nothing else merges until green, and two fix PRs for one failure without a green result stops the run as a design problem | accepted |
| 11 | 2026-09-10 | Overnight #58 run: Android PRs merge without skip-release so the Android chain publishes the debug APK the owner sideloads; desktop widgets, Android screens, and Mac-to-phone pairing are reported as needs your eyes, never verified | accepted |
| 10 | 2026-09-10 | Overnight #58 run: macOS PRs with a rendered change (#52 #53 #54 #56 #57) get one codex-computer-use round each against a `make install`ed build of the PR branch before merge, OS-level input only, screenshots posted on the PR, then merge without skip-release; wave-1 macOS PRs add unrendered files and merge with skip-release | accepted |
| 9 | 2026-09-10 | Overnight #58 run: Sol (codex-review) gates every PR; #54 and #56 change user-facing text so each also gets one fable reviewer pass before Sol's rounds, budget permitting; fix dispatches count per delegate-issue and the question at three is answered here | accepted |
| 8 | 2026-09-10 | Overnight #58 run: every lane is transcription from a written spec; grok via cursor-agent takes the multi-file lanes (#46 #50 #52 #53 #54 #57), composer the single-file ones (#44 #45 #47 #48 #49 #51 #55), Sol at high reasoning replaces any lane grok fails twice, #56 starts on a fresh-context fable subagent, and any other fable escalation needs Sol to have missed first | accepted |
| 7 | 2026-09-10 | Overnight #58 run: Fable weekly usage may rise from 6% to 20% and no further; at 15% no further fable subagents (reviewer passes and escalations go to Sol at high reasoning); at 20% finish in-flight merges, report, stop | accepted |
| 6 | 2026-09-10 | Overnight #58 run: nothing waits on the owner; an item needing the owner's answer becomes an assumption row in the trail and a needs-your-eyes line in the report, and the lane continues on it unless the item is under the config-mutation gate, where it stops | accepted |
| 5 | 2026-09-09 | No billing-cycle date is shown for Claude or Codex, since neither exposes one; Cursor shows renewal from `billingCycleEnd` (#58 owner decision 5) | accepted |
| 4 | 2026-09-09 | No `codex app-server` refresh fallback until a real expired-token report; the plan doc keeps the recipe (#58 owner decision 4) | accepted |
| 3 | 2026-09-09 | "Left" replaces "used" in the popover headline only; the menu bar icon and widgets keep used-percent semantics (#58 owner decision 3) | accepted |
| 2 | 2026-09-09 | Keep the phone-fetches-itself sync model; Tailscale is only the transport, no relay, no Mac-as-server (#58 owner decision 2) | accepted |
| 1 | 2026-09-09 | Credential precedence on the Mac: pasted token, then CLI login, then env var; on the phone the CLI token wins because the Mac keeps it fresh (#58 owner decision 1) | accepted |
