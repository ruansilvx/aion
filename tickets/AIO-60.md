---
ticketId: AIO-60
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-20T00:00:00.000
updatedAt: 2026-07-21T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Adapt the OpenSpec SDD workflow into Aion's own ticket system

## Key questions asked

1. Should each SDD stage map onto existing ticket types/status transitions, or does a distinct artifact set (proposal.md/design.md/etc.) live separately per ticket?
2. (User proposed a model unprompted, covering epic-level idea aggregation, a new raw-ideas ticket type, multi-level proposals, artifact placement, and ad-hoc changes as epic-child tasks) — does this hang together?
3. Where does `spec.md`'s delta fit, given it's structurally different from proposal/design (it's meant to be merged into permanent current-state specs, not just read for context)?
4. What else needs to be thought through on this topic?
5. Should stage-triggering automation reuse the same watcher `AutomationConfidence` setting, or a separate one?
6. Should the proposed three-tier model (auto/gated/manual) replace/extend the shared `AutomationConfidence` type everywhere, or stay scoped to just stage-triggering?
7. How do stage-triggering buttons relate to Aion's "chats tied to tickets" concept — a visible/watchable chat, or a silent background job?
8. For tracking "which SDD stage a ticket is in": is an explicit stored field more reliable than deriving it from child-ticket/chat state?
9. (Follow-up session, sequencing) Given nothing in `project.md` §5 has actually shipped yet, does the earlier 3-piece sequencing guess still hold, or does `AutomationConfidence` fold into whichever consumer is built first?
10. Should watcher-review be in scope for the execution-phase change, or deferred since it's a safety/quality layer, not required for the mechanism to function?
11. Given everything the watcher was meant to do is now covered by stage-specific mechanisms already designed this session, is there still a use for a standalone watcher concept at all?
12. Is the resulting gap — ad-hoc manual ticket edits outside an active SDD-cycle chat get no automatic quality check — acceptable, or is a lightweight check still wanted?

## Summary of answers

- **Artifact/ticket-type mapping:** ideas, known gaps, open questions, and other unexplored uncertainties aggregate into Epics via a new ticket type (exact shape not yet designed). Proposals happen at two levels — Epic-level (breaks into Stories) and Story-level (breaks into Tasks). `proposal.md`/`design.md` become a summary embedded in the ticket plus a linked Documentation page (direct reuse of the shipped linked-ticket model — no new mechanism). `spec.md`'s delta doesn't get its own artifact: `specs/*.md` becomes a set of living Page tickets, and "archive" becomes a direct edit to those pages. Ad-hoc changes (outside a full cycle) are plain epic-child Task tickets — already valid under the shipped type-compatibility matrix.
- **Execution model:** every SDD stage transition is a visible, watchable, interruptible chat. A ticket can have multiple chat children (already structurally valid), used to save tokens via fresh context per stage and keep stages cleanly separated — a Story's Exploration chat spawns Task children; once all Tasks reach Done, the Story advances to a fresh-context Verification chat, then an Archival chat. Mid-task issues branch the current chat with a handoff, folding back or spawning a separate ticket — the same mechanism as the existing Branch/Merge Semantics decision, applied at finer granularity. Making this branching feel subtle in the UI is flagged as real, unresolved design work.
- **Automation model:** stage-triggering uses the same underlying shared type as the rest of the app's automation points, extended from two states (`auto | ask-first`) to three (`auto | gated | manual`).
- **Stage-state tracking:** an explicit, Cubit-gated "current SDD stage" field on the ticket is more reliable than deriving it from child/chat state — derivation is ambiguous exactly at transition boundaries, and a stored field is what makes filtering/badging cheap. All writes go through a Cubit method that validates the actual precondition first (e.g. all child Tasks Done before advancing to verification).
- **Sequencing (follow-up session):** checking the archived-changes list confirmed nothing in `project.md` §5 has shipped yet — so "extending `AutomationConfidence`" is really "building it three-state for the first time," which has no standalone value without a consumer. That collapses the earlier 3-piece sequencing guess into 2 real changes.
- **Watcher, reconsidered:** mapping the watcher's originally-intended responsibilities (decompose Epic/Story into children, create tickets, merge chats, update documentation, assure quality/avoid hallucinations, handle repeated Tier-3 coding failures) against what this session already designed shows every one already has a concrete owner: the Propose-stage chat (decompose + create tickets), the existing Branch/Merge Semantics decision (merge chats), the Archive-stage chat (update documentation), the Verify-stage chat (quality/hallucination check), and mid-task branching (failure escalation, triggered by failure instead of a user click). A standalone watcher persona would duplicate this machinery under a different name. Dropped entirely as a distinct concept — this also simplifies sequencing further, since `AutomationConfidence`'s only real consumers are now the budget gate, the batch-flush gate, and SDD-stage-triggering (no watcher-override case).
- **Ad-hoc edit gap:** dropping the watcher leaves ad-hoc manual ticket edits (outside an active SDD-cycle chat) with no automatic quality/hallucination check. Accepted as consistent with the project's existing "sufficient at personal scale" reasoning (same logic already used for brute-force embeddings) — no lightweight check required for now. A soft, non-blocking possibility was floated — on a manual edit, optionally suggest the user run a quick review, or ask why it skipped the proper cycle so the reason gets documented — but explicitly not designed or committed to; captured only as a future, non-blocking idea.

## Conclusions reached

- New ticket type needed for raw ideas/gaps/open-questions, feeding Epic aggregation (schema not yet designed — open question).
- Two-tier proposal system: Epic-proposal → Stories, Story-proposal → Tasks.
- `proposal.md`/`design.md` → ticket summary + linked Documentation Page. `spec.md` → direct edits to living `specs/*.md` Page tickets at archive time, no separate delta artifact.
- Ad-hoc changes = plain epic-child Task tickets.
- Every SDD stage = its own visible/watchable/interruptible chat; multiple chat children per ticket, already valid under the shipped data model.
- Mid-task issue branching reuses the existing Branch/Merge Semantics decision at finer granularity — no new mechanism.
- `AutomationConfidence` is built three-state (`auto | gated | manual`) from its first real implementation — applied to the budget gate, the batch-flush gate, and SDD-stage-triggering. Stale-context prompt stays a documented exception.
- "Current SDD stage" is an explicit, Cubit-gated ticket field — not derived.
- **The standalone "watcher" concept from `project.md` §5 is dropped entirely** — every responsibility it was meant to cover already has a concrete owner among the mechanisms this idea designs (Propose/Verify/Archive-stage chats, Branch/Merge Semantics, mid-task branching). `project.md` §5's "Watcher system" subsection is now superseded and should be removed/revised — not as part of this brainstorm capture, but when this idea moves to `/propose` (or sooner, as a standalone doc correction).
- Ad-hoc manual edits outside an SDD cycle get no automatic review — accepted gap, no lightweight check needed. A soft "suggest a review / ask why it skipped the cycle" nudge was floated as a possible future, non-blocking enhancement only.
- **Sequencing resolves to two changes:**
  1. **Foundation** — new ideas/gaps ticket type + compatibility-matrix updates, `specs/*.md` becoming Page tickets, the Cubit-gated "current SDD stage" field (can exist inert, with no consuming UI yet).
  2. **Execution** — stage-triggering buttons, per-stage chat spawning/branching, and `AutomationConfidence` (three-state, its first-ever real consumer here).
  `provider-configuration` should be proposed/built before or alongside Execution, since stage-chats need a configured provider to actually call a model.

## Follow-up decisions (2026-07-21)

Resolved while re-scoping `sdd-ticket-foundation` (phase 1) against what had shipped since this idea was written — see that change's `proposal.md` for the full reasoning trail. Recorded here because these are phase-2 (Execution) design decisions, not phase-1 code:

- **Ticket type renamed `idea` → `signal`.** Working through how `/what-next`'s ticket-native equivalent would need to enumerate gaps and open questions (see next point) made clear the type's job is broader than "idea" suggests — it equally represents a known gap or an open question raised against an already-shipped feature, not just a fresh proposal. `signal` — something noticed but not yet resolved into work — covers all three without implying any one of them specifically. `sdd-ticket-foundation` ships `TicketType.signal` under this name.
- **Gap/open-question tracking resolved to the ticket-native design, not a ported file convention.** `detect-gaps.sh`'s Known-gaps/Open-questions priority tier works today by regex-parsing `## Known gaps`/`## Open questions` markdown sections out of `aion-arch/specs/*.md`. The alternative — keep that same prose-section convention inside a spec Page ticket's content and re-parse it in-app — was considered and rejected. Instead: a gap or open question becomes its own `signal` ticket, linked to the relevant spec page via the existing `TicketLinkType.relatesTo`, discoverable by an ordinary type/status query. This is the ticket-native version of "specs-as-pages," not Page-ticket storage itself (which `sdd-ticket-foundation`'s `proposal.md` confirmed already exists via `page-content-markdown-editor`/`storage-embedding-git-sync` — the missing piece was always this tracking mechanism, not the storage).
- **`project.md` also becomes a linked page, not just `specs/*.md`.** Originally this idea only discussed migrating `aion-arch/specs/*.md`. `project.md` (stack/architecture/foundational-decisions) needs the same treatment — it's the source `detect-gaps.sh`'s priority-2 tier scans for unbuilt foundational decisions, so it needs an in-app equivalent too, linked through the ticket system the same way spec pages are. Whether `project.md`/`CLAUDE.md`-style *agent-constitution* content (how to behave) should really be treated identically to *product* spec content (what exists), or kept file-based on purpose, is still open — see Open questions below.
- **New universal `Ticket.complexity` field** (small/medium/large, generalized from this idea's original idea-file-only `complexity` frontmatter) — applies to every ticket type, not just `signal`. Unlike `signal`/`release`'s enum-only addition, this is a real drift schema migration (new column, following the `deletedAt`/`syncStatus` precedent in `app_database.dart`). Deferred to phase 2 alongside the SDD-stage field — both are "built inert" with no consumer until phase 2's UI exists.
- **Confirmed still phase 2, not phase 1:** the mechanism that promotes/converts a `signal` ticket into an `epic` (attaching to an existing one or spinning up a new one) — depends on the chat/provider flow phase 1 deliberately doesn't touch.

## Open questions

- How an agent (chat or otherwise) locates "the right page" for a given spec domain or for `project.md` itself — today's CLI finds `aion-arch/specs/tickets.md` by filename; the ticket-native version has no equivalent lookup convention yet (a reserved root page? a naming convention? a discriminator field?). Applies equally to both the specs question below and the new `project.md`-as-page decision above.
- Whether `project.md`/`CLAUDE.md`-style agent-constitution content should become a page at all, or stay file-based on purpose the way a human dev's `CLAUDE.md` does regardless of what PM tool manages the product — not decided, flagged above.
- Exact schema for the new ideas/gaps/open-questions ticket type, and the migration path off today's file-based `aion-arch/ideas/*.md` (including, recursively, this very idea file and `provider-configuration.md`).
- The concrete chat-branching UX — explicitly flagged by the user as unresolved and "fundamental," not something settled in this session.
- The exact fold-vs-spawn decision logic when a branched mid-task issue-chat resolves is left as a user choice at merge time, not further specified.
- (Soft, non-blocking, floated but not designed) Whether a manual ad-hoc edit should ever prompt the user to run a quick review or explain why it skipped the SDD cycle, purely for documentation purposes.

## Architectural implications

- `AutomationConfidence` (`project.md` §5) is built three-state (`auto | gated | manual`) as its first real implementation — consumers are the budget gate, the batch-flush gate, and SDD-stage-triggering. The stale-context prompt stays a documented exception (a choice between two different behaviors, not a confidence spectrum).
- `project.md` §5's "Watcher system" subsection is superseded by this idea's conclusion and needs removal/revision — flagged for whenever this idea reaches `/propose`, not edited here.
- Applies `project.md` §2's Branch/Merge Semantics decision at a finer granularity (mid-task issue branching) — the decision itself doesn't change, just a new use of it.
- Extends the shipped type-compatibility matrix (`define-type-compatibility-matrix`) with the `signal` ticket type (renamed from "idea," see Follow-up decisions), covering ideas/gaps/open-questions in one type.
- Adds a new Cubit-gated ticket field ("current SDD stage") and a new universal `Ticket.complexity` field, both consistent with the existing validation-lives-in-Cubits convention — both deferred to phase 2, see Follow-up decisions.
- Depends on [[provider-configuration]] for phase→provider routing of each per-stage chat.
- Two-phase sequencing, re-scoped: Foundation is now `sdd-ticket-foundation` (just `signal`/`release` ticket types — proposed, see [[self-iteration-sequencing]]); Execution absorbs everything the original Foundation scope assumed was "just storage" but turned out not to be (stage-triggering, chat spawning/branching, AutomationConfidence, the SDD-stage field, the complexity field, gap/open-question tracking via linked `signal` tickets, and `project.md`-as-page) — see Conclusions reached and Follow-up decisions.
- Very likely the mechanism that constitutes Aion's self-iteration milestone — the ticket-native replacement for the CLI-driven workflow currently used to build Aion itself.