<!-- fleet corefile: CLAUDE-base.md @ 4d6434180db4a996ec74c0d6604b1917b914de83
     Copy to a new repo's root as CLAUDE.md next to the instantiated
     AGENTS.md. This layer is main-session/orchestrator concerns only.
     Everything shared lives in AGENTS.md so delegated prompts can shrink
     to "read AGENTS.md, then do issue #N." The model roster is not here: fleet
     rules/model-roster.md loads in every session through ~/.claude/rules,
     and this file holds only this repo's overrides. Run the sync-corefiles
     skill to re-apply the shared sections. -->

@AGENTS.md

# Claude main-session guidance

Everything above (AGENTS.md) is the shared rulebook. It applies to every
agent, including subagents. What follows is for the orchestrating Claude
session only.

## Model roster overrides

These win over the default roster in `~/.claude/rules/fleet-model-roster.md`,
which loads in every session.

None.

## Session token hygiene

Long main-session context is the Fable cost driver, not delegated agents.
Per-task cost ≈ context size × wakeup count, because every background-task
notification re-reads the whole conversation. This section is spend
policy (config); the measurement behind it is fleet `docs/decisions.md`
row 9.

- During big multi-stage rounds, the main session stops authoring code:
  chunks beyond small surgical edits go to a delegate against a written
  spec (the builder lanes in the default roster; a fresh-context fable
  subagent when the chunk is taste work or a long open-ended run). The
  main session does
  specs, targeted diff review, merges. Ordinary small tasks: author freely.
- Codebase recon goes to composer-2.5 or an Explore subagent (Claude
  Code's read-only search agent type); a wide read across many files,
  docs, or projects that returns facts, not verdicts, fans out to
  haiku-5.5 subagents (the haiku-5.5 roster notes); when finding the
  answer takes judgment, a sonnet-5.5 subagent (the sonnet-5.5 roster
  notes); when the job is finding what's wrong (a bug's root cause, an
  audit), gpt-6.2 Sol through `codex exec` (the gpt-6.2 Sol roster
  notes). Don't pull 2,000-line files into the main context when a
  delegate can return the 20 lines that matter.
- Batch verification into ONE delegated round with the complete
  checklist; every extra round-trip is a full-context wakeup.
- In a multi-turn main session that passes about 250k tokens, name a good
  compact point once; subagents and delegates never comment on context
  hygiene. Follow-up work discovered mid-task goes to the backlog, not the
  current session: file a GitHub issue (or a backlog line for an idea)
  with enough context to start cold, so the owner can run it in another
  worktree in parallel. Never "compact, then I'll start on B" (fleet
  `docs/decisions.md` row 8).

## Delegation mechanics

- Delegate prompt shape (the field-test exemplar `delegate-spec-task-67.md`,
  zero merge conflicts across 36 PRs): read AGENTS.md → issue #N is the spec → existing
  machinery to reuse → decisions already made → **Files you own / Do NOT
  touch** → gates → commit-but-don't-push. Ownership is decided at spec
  time, not merge time.
- Check CLI availability before delegating (`command -v agent`,
  `command -v codex`); fall back to a Claude subagent if missing, with
  the same worktree isolation when it writes code.
- opus-5.5: the Agent tool with `model: 'opus'` and
  `isolation: 'worktree'`.
- composer/grok: `agent --worktree -p --force "prompt"`; non-`-fast`
  variants only. codex: `codex exec` / `codex review`. The local codex
  config pins the default model (tier slugs drift; check it), pass
  `-c model_reasoning_effort="high"` for deep work; background long runs.
- **Two-deadline rule on any external wait** (field-test E3): arm an ack
  timeout and a completion timeout the moment the wait starts; silence is
  not success. Numbers, fallback, and BAD/GOOD live in the `babysit-pr`
  skill.
- **Every "done" from a delegate is a claim requiring one artifact
  produced by someone other than the builder.** The verifier runs the
  check itself, and the artifact must be one that would look different
  if the claim were false. Accepting the builder's own screenshot or
  log doesn't count (field-test E1/E4: the builder self-attested a
  design match nobody independently checked). Builders over-deliver
  against tight specs; verifiers under-verify unless forced to produce
  artifacts. Keep the verifier separate from the builder for anything
  user-visible.
- Recon goes to the `scout` agent, one independent review goes to the `reviewer` agent (both fleet `agents/`, installed machine-level), and a multi-model panel goes to the `interrogate` skill.

## Repo-specific orchestration

- A change under `skills/ai-usage/` is a meaning change for every repo
  on this machine (AGENTS.md, Stack and commands): fable reviews it once
  as the `reviewer` agent, and it is verified by running the skill's
  `scripts/get-usage.sh` against the running app and pasting the
  snapshot's `generatedAt`, then `make install-skill` so the machine copy
  matches `main`.
- Verification lanes: unit tests and `make app` run in the builder's
  worktree. Popover and settings UI go to the `codex-computer-use` skill
  against a `make install`ed build (the Widget Gallery shadowing gotcha in
  AGENTS.md means a worktree build alone is not enough). Desktop widgets,
  the Android app, and macOS-to-Android pairing are "needs your eyes" and
  are reported that way, never delegated as verified.
- Spend gate for delegates: no delegate hits a real provider API. Repeats
  go through the mock server or the snapshot; one live refresh per round
  is the ceiling, and the builder says which it used.
- Android builds need the JDK and SDK exports from `android/README.md`.
  A delegate without them (any cloud or cursor-agent lane) builds and
  tests macOS only and says so; Android compile checks stay on this
  machine.
- Boundary with sibling projects: a fix to a shared letter section
  belongs in the fleet template, so write it in `../fleet` and report the
  diff under the config-mutation gate; the commit there is Doug's. Other
  repos that consume the `ai-usage` skill are never edited from this
  session.
