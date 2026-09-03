---
ticketId: AIO-17
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-23T00:00:00.000
updatedAt: 2026-07-23T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Coding-execution reliability, safety, and observability

## Context: how this was found

Dogfooded via `self-iteration-sequencing.md`'s step 3 (`sdd-ticket-execution`)
against the real `aion` checkout on 2026-07-23: created a Task ticket for a
real known gap (`tickets.md`'s overflow-menu-shadow-in-Obsidian entry),
triggered coding execution through Aion's own UI, and watched what actually
happened end to end (a real Claude Agent SDK subprocess, real git branch,
real push, real PR against `ruansilvx/aion`). Along the way, also hit and
fixed two unrelated environment/SDK bugs (stale `@anthropic-ai/
claude-agent-sdk` pin causing duplicate-`tool_use`-id API errors; missing
`permissionMode: 'bypassPermissions'` meaning tool-enabled runs previously
could Read but never actually Write) — those are fixed in
`agent_bridge/index.mjs`, not part of this idea. The four findings below are
what remained once the mechanism could actually run to completion.

## Finding 1 — PR-opening isn't gated behind verification the way it is everywhere else in this project

The run diagnosed a real, reasonable fix (route `AionShadows.card()`'s
dark-theme case through a glow instead of an empty list, mirroring
`AionShadows.overlay()`'s pattern) but wrote it using `BoxShadow(inset:
true)` — not a real parameter on this Flutter SDK's `BoxShadow`. It
committed, pushed, and opened a real PR anyway. `flutter analyze` would
have caught this in about a second.

The root cause isn't just "nothing runs analyze" — it's structural.
`_assembleExecutionContext` instructs the model to "open a pull request
as the run's last step," folding implementation and PR-opening into one
undifferentiated turn with no gate between them. Every *other* path to a
PR in this project goes through `/verify` first: the OpenSpec cycle this
very repo runs on is `/propose → /apply → /verify → /archive`, and
`/archive` — the only stage that opens a PR — explicitly will not run
until `/verify` has passed and `tasks.md` is fully checked off (see
`aion-arch/CLAUDE.md`'s shared rules: "no archiving before every
`tasks.md` item is checked off"). Coding-execution invented its own,
weaker path to a PR that skips the equivalent of `/verify` entirely.
`tickets.md`'s existing Known gaps note ("nothing verifies the PR
genuinely exists") undersold this — the real fix isn't just adding a
check, it's giving coding-execution its own verify-then-archive
structure instead of collapsing both into "implement, then PR."

## Finding 2 — the agent's own git operations can destroy uncommitted human work

Mid-run, the agent committed once directly to `main`, caught itself,
`git reset`, created a proper feature branch, and recommitted there — good
instincts once it had real tool access. But somewhere in that sequence
(reset + branch checkout), two *uncommitted* local files unrelated to its
own task — a `.gitignore` edit and an `agent_bridge/index.mjs` edit sitting
in the same working tree — were silently wiped, with `git stash list`
confirming they weren't stashed, just gone. Aion's project `rootPath` for
coding execution *is* the developer's real checkout (there's no separate
worktree or sandbox), so any Task moved to "In Progress" while the
developer has unrelated uncommitted changes sitting in that same tree can
lose them, with zero warning, as a side effect of the agent's own routine
git hygiene. This is exactly the class of action `project.md`'s own safety
posture would refuse if a human asked for it directly (`git reset --hard`,
discarding uncommitted work) — but nothing stops the *agent* from doing it
to itself.

## Finding 3 — no Task-level signal when a run fails, stalls, or finishes ambiguously

Three different terminal states were observed across the dogfood run's
several attempts, and all three look identical from the Task ticket and
the ticket list: a hard API-error failure (visible only as an "Execution
failed: ..." comment buried in the spawned chat), a run that completed
without ever emitting the required `EXECUTION: PR_OPENED`/`NO_PR` line (no
error, no success — just silence), and the eventual real success. In every
non-success case, the Task ticket simply stays "In Progress" forever
alongside a genuinely-running Task, with no banner, no error surfaced at
the Task level, and no way to tell "still working" from "silently dead"
without opening the spawned chat and reading its transcript. Recovering
requires knowing the undocumented workaround of toggling status away and
back to re-trigger — `tickets.md`'s Known gaps already notes this for the
app-restart case; it turns out to be the *only* recovery path for a failed
run in general, restart or not.

## Finding 4 — no progress visibility during the tool-use phase

A run that's actively reading files, fighting permissions, or making edits
produces zero UI signal beyond the initial system-context comment until
its final text reply lands — one observed run sat silent for ~4.5 minutes
while the model worked (and, in that case, struggled) via tool calls with
no interstitial text. `ChatCubit.sendMessage`'s streaming already surfaces
`AgentTextEvent` chunks live; there's no equivalent signal for tool-call
events (`AgentToolUseEvent` or similar), so a run's actual activity —
which file it's touching, which command it's running — is invisible until
it either produces prose or ends.

## Brainstorm session (2026-07-23) — resolving the four findings

### Key questions asked

1. Should Finding 2 (working-tree data loss) jump ahead of the other
   three and ship alone, given it's the one with real destructive
   consequences, or should all four be covered together in one change?
2. For Finding 2, which mechanism: git worktree isolation, blocking on a
   dirty tree at trigger time, or auto-stashing around the run?
3. For Finding 1, should the run split into two turns (implement, then
   an Aion-run `flutter analyze`/`test` gate, then Aion itself pushes and
   opens the PR only on a clean pass), and should a failed check
   auto-retry with a corrective turn or just flag for human review?
4. For Finding 3, does the suggested Task-detail status banner become a
   single unified surface for every non-success state (verify failure,
   hard error, silent completion, stall), or stay split by failure type?
5. For Finding 4, does progress visibility need a real `AgentToolUseEvent`
   variant threaded through `AgentModelClient`/`ChatCubit`, or is a
   coarser "agent is working..." indicator enough?

### Summary of answers

1. Cover everything together, as one change — not splitting Finding 2
   off to ship alone.
2. Git worktree isolation, driven entirely from Aion's own Dart code
   (`Process.run('git', ['worktree', 'add', ...])` around
   `_runCodingExecution`, `workingDirectory` pointed at the created
   worktree, removed after). This was newly surfaced during this idea's
   preceding `/explore` session: `ClaudeAgentSdkClient.run` currently
   does a bare `Process.start` with no git isolation of any kind, and the
   vendored SDK's own `worktree.bgIsolation` setting turned out to be
   scoped to its background-session/agent-view feature, not the plain
   `query()` call `agent_bridge/index.mjs` makes — so it isn't a usable
   shortcut here; the worktree has to be Aion's own responsibility.
   Chosen over blocking-on-dirty-tree (only protects at trigger time) and
   auto-stash (idea file's own prior open question already flagged the
   stash/mid-run-git-ops collision risk) because it removes the risk
   structurally rather than mitigating it.
3. Checked how the actual `/verify`→`/archive` split works before
   answering (`aion-arch-workflow.md`: `/verify` "reports, doesn't fix";
   `/archive` only proceeds once verification has no outstanding CRITICAL
   findings) and confirmed this idea's own Finding 1 open question already
   flags that auto-retry duplicates `sdd-ticket-execution`'s deliberately
   deferred "mid-task escalation" mechanism. Resolution: two-turn split,
   mirroring `/verify`→`/archive` — implement, then Aion itself runs
   `flutter analyze` (+ a scoped `flutter test`) inside the worktree, then
   Aion itself (plain git/gh, no model call) pushes and opens the PR only
   on a clean pass. Retry-on-failure isn't hardcoded either way — it's
   governed by `AutomationConfidence` (a new consumer of the existing
   `auto | gated | manual` pattern): `auto` feeds errors back for a
   corrective turn automatically (capped retries), `gated` asks the user
   before retrying, `manual` never retries automatically and just
   surfaces the failure for the human to trigger manually. This
   knowingly reopens a narrow slice of the deferred mid-task-escalation
   concept, but scopes and gates it rather than building it unconditionally.
4. One unified banner. A single Task-detail component surfaces every
   non-success/stuck state — verify failure (with the analyze/test
   errors), hard API error, silent no-`EXECUTION:`-line completion, and a
   stalled run — each with a state-specific message and a one-click
   manual retry, replacing the undocumented toggle-status-away-and-back
   workaround entirely. This is also the surface Finding 1's `gated`/
   `manual` retry paths write to.
5. A real `AgentToolUseEvent` variant (tool name/summary), added
   alongside the existing `AgentTextEvent` on `AgentModelClient` and
   threaded through `ChatCubit`'s existing streaming — chosen over a
   coarse busy indicator because the Claude Agent SDK's own event stream
   already distinguishes tool-use events; this surfaces something the
   bridge already receives rather than computing something new.

### Conclusions reached

Ship all four fixes together as one change:

1. **Git worktree isolation** (Finding 2) — every coding-execution run
   gets its own worktree, created and torn down by Aion's own Dart code;
   the shared developer checkout is never touched.
2. **Two-turn implement → verify → (Aion-driven) PR** (Finding 1) — runs
   inside the worktree; retry-on-failure policy is a new
   `AutomationConfidence` consumer (`auto`/`gated`/`manual`).
3. **Unified Task-detail failure/retry banner** (Finding 3) — one surface
   for every non-success/stuck state, including Finding 1's gated/manual
   retry flagging.
4. **`AgentToolUseEvent`** (Finding 4) — live per-tool-call visibility
   threaded through `AgentModelClient` → `ChatCubit`.

### Open questions

- Exact retry cap and backoff for `AutomationConfidence: auto` on
  Finding 1's verify gate — left for `/propose`'s design.md.
- Whether `AgentToolUseEvent` needs its own opt-out/verbosity setting, or
  always shows once built — not raised this session, worth a sanity check
  during `/propose`.
- Symlinked/sparse worktree config (`symlinkDirectories`/`sparsePaths`,
  seen in the vendored SDK's own worktree typedefs) wasn't discussed —
  Aion's worktree creation is plain `git worktree add`, not the SDK's
  own worktree feature, so this may not even apply; confirm during
  `/propose` whether large ignored directories (build artifacts, etc.)
  need any special handling to avoid disk bloat per worktree.

### Architectural implications

- Extends `AutomationConfidence` with a second real consumer (coding-
  execution retry policy) alongside SDD-stage-triggering — reinforces
  `project.md` §5's "shared automation-confidence pattern" as designed:
  new automated decision points plug into the existing three-state type
  rather than growing their own ad hoc flag.
- Finding 1 and Finding 2's mechanisms are coupled, not independent: the
  analyze/test check and the eventual push/PR both need to run from
  *inside* the worktree Finding 2 creates, not the shared tree — so these
  can't ship as fully separate tasks in `/propose`'s `tasks.md`; the
  worktree lifecycle has to exist before the two-turn split can run
  anywhere.
- `AgentModelClient`'s interface shape changes (new `AgentEvent` variant)
  — every current and future implementation (today: just
  `ClaudeAgentSdkClient`) needs to handle `AgentToolUseEvent`, not just
  `AgentTextEvent`.
- Knowingly reopens a narrowly-scoped slice of `sdd-ticket-execution`'s
  deliberately-deferred "mid-task escalation" concept (auto-retry on
  verify failure) rather than leaving it fully out of scope — gated by
  `AutomationConfidence` so it doesn't become an unconditional retry loop.
- Directly extends `sdd-ticket-execution`'s explicitly-deferred "mid-task
  escalation" gap (see its proposal's Out of scope) from a theoretical
  concern into one with concrete, reproduced evidence — Findings 1 and 3
  are two faces of the same underlying missing mechanism.
- Finding 2 is a new category of risk not discussed in any prior idea:
  the coding-execution provider (`ClaudeAgentSdkClient`, `toolsEnabled:
  true`) now has unrestricted git/bash access to the *same* working tree
  a human developer uses, once `permissionMode: 'bypassPermissions'` is
  set (a prerequisite for coding execution to do anything real at all —
  see the SDK-bug fixes noted in Context above). Worktree isolation is
  the structural fix for this, not a mitigation.
- Reinforces `self-iteration-sequencing.md`'s own conclusion that
  dogfooding the mechanism before building more product surface on top of
  it (e.g. `new-project-onboarding`) was the right call — every finding
  here came from actually running it once, not from reading the spec.