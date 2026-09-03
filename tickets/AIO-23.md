---
ticketId: AIO-23
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-26T00:00:00.000
updatedAt: 2026-09-02T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Decommission aion-arch's CLI-driven workflow

decommission-aion-arch-cli-workflow: A full retirement plan for
aion-arch's CLI-driven SDD workflow (`.claude/skills/` — /explore,
/propose, /apply, /verify, /archive, /design-brief, /design-sync —
plus CLAUDE.md and workflow/scripts+shared reference docs), once
Aion's ticket-native SDD workflow (sdd-ticket-foundation/
sdd-ticket-execution, plus the spec-ticket-type idea) covers
everything it does. Raised while brainstorming spec-ticket-type,
after concluding aion-arch is transitional scaffolding (deprecated
once Aion can self-iterate) and that project.md should fold into the
same spec-ticket mechanism as one architecture spec ticket — this
idea is the "everything else in aion-arch" follow-up that was
explicitly descoped from that session to keep it landable as one
proposal. This 2026-08-26 session reached a full resolution — see
Conclusions reached below.

## Key questions asked

1. Once ticket-native `idea`/`knownGap`/`openQuestion` types can
   represent everything a raw idea file captures, does the existing
   ~50-file `aion-arch/ideas/*.md` backlog actually need migrating
   into tickets one-for-one, or could it stay a frozen historical
   record with only new ideas going forward using ticket-native
   types?
2. Does full migration mean every idea file regardless of status,
   including already-`archived` ones whose content is already
   superseded by shipped specs — or only still-in-flight ones
   (`raw`/`resolved`/`explored`/`specced`)?
3. Given specs are per-Epic (not per-domain) and the current
   `specs/*.md` files are already many changes merged together with
   no clean per-Epic boundary left, should each spec ticket be seeded
   from its originating archived change's own delta `spec.md` (already
   scoped to exactly one change) rather than trying to carve up the
   merged current-state file?
4. Given a change's own delta only reflects the world as of that
   change — missing any later drift-fix folded into current
   `specs/*.md` by a subsequent, unrelated change — should the delta
   be treated only as a starting draft, reconciled against the
   current merged text before finalizing, rather than trusted as
   complete on its own?
5. What happens to the `aion-arch/changes/archive/<name>/` folder
   itself once its content becomes a spec ticket — kept as a frozen
   dump, or deleted?
6. (User clarified the real scope: `aion-arch` won't be used at all
   going forward, everything must migrate) What's the recommended
   full plan?
7. Two specific calls in that plan — retiring `.claude/skills/`
   strictly last (since it's the tool executing the rest of the
   migration), and archiving rather than deleting the `aion-arch`
   repo itself — right, or would you rather delete the repo outright
   once migration is confirmed complete?
8. Should the migration also audit Aion's own bundled baseline skills
   (`aion/assets/baseline/*/skills/*.md`) for any remnant reference to
   `aion-arch` specifically, as a safety check?
9. Should the migration also cover repointing references to
   `aion-arch` tasks/designs/files scattered in Aion's own source-code
   comments, toward the new tickets instead?
10. Will other AI providers (not just Claude Code) be able to
    properly detect and use Aion's own skill mechanism, once
    `aion-arch` — which shares the same underlying discovery
    convention — is gone? (Investigated via code, see Summary of
    answers — resolved as a separate, blocking issue, not part of this
    idea's own scope.)

## Summary of answers

- Full migration, not a frozen-and-abandoned backlog: every
  `aion-arch/ideas/*.md` file becomes a ticket, with no cutoff by
  status — including already-`archived` idea files, since "aion-arch
  won't be used anymore" means all information needs a ticket-native
  home, not just the still-open threads.
- Splitting `specs/*.md` into per-Epic spec tickets can't be done by
  carving up the merged current-state files directly — they've
  already absorbed many changes with no clean per-Epic seam left.
  Instead: one spec ticket per archived change, seeded from that
  change's own delta `spec.md`.
- That delta seed is a draft only — each spec ticket's content gets
  reconciled against the *current* merged `specs/*.md` text for its
  area before being finalized, so later corrections/drift-fixes that
  landed via unrelated subsequent changes aren't silently lost.
- Every archived change is reconstructed as a full Epic + Story +
  Task ticket set (already "done"): the change's `proposal.md`
  content folds directly into the reconstructed ticket's own
  description field (no separate artifact needed for it), `design.md`
  becomes a linked Documentation page, and the reconciled delta
  becomes the spec ticket. `project.md` becomes the one
  hand-bootstrapped architecture spec ticket, since no single Epic
  produces it.
- Confirmed scope is total: `aion-arch` is retired outright, not kept
  running in any partial or coexisting form. Six-step plan proposed
  and agreed (see Conclusions reached).
- Agreed: `.claude/skills/` retires strictly last, since it's the
  very tool used to execute the migration steps that precede it —
  can't delete the tool mid-use. Agreed: the `aion-arch` repo is
  archived (frozen/read-only), never deleted, so its git history
  stays recoverable for anything the ticket migration didn't capture
  faithfully.
- Agreed: audit Aion's own bundled baseline skills
  (`aion/assets/baseline/*/skills/*.md` — templates handed to *other*
  managed projects, kept in sync with `aion-arch`'s own skills per the
  existing staleness-tracking mechanism) for any literal `aion-arch`
  reference. Those files are meant to be fully generic/portable; any
  such reference would be a real bug regardless of this decommission,
  so it's folded in as an explicit step-1 audit rather than left
  implicit.
- Agreed: also repoint references to `aion-arch` tasks/designs/other
  files scattered across Aion's own Dart source comments (not just
  idea/change paths) toward the corresponding new ticket, since ticket
  and code will live in the same system going forward and can carry a
  real, stable link instead of a citation into an external repo.
- Investigated directly (code read, not just discussion): confirmed
  `SkillAttachmentKind.delegatedSkill` depends on the underlying agent
  discovering `.claude/skills/<skillName>` on disk — the same
  Claude-Code-native convention `aion-arch` itself uses — and that
  today's shipped safeguard (`ModelPhaseToolAccess`/
  `ModelRoutingCubit` filtering by `supportedToolAccessTiers`) only
  checks tool-access capability, not `.claude/skills/`-discovery
  capability specifically, so a future non-Claude-Code-CLI full-tool
  provider could still silently fail on a `delegatedSkill` attachment.
  Judged a real, pre-existing issue independent of `aion-arch`'s
  fate — split off as its own idea,
  [[delegated-skill-provider-portability]], and marked as a hard
  prerequisite: fix it *before* this migration proceeds, since the
  migration likely leans on `delegatedSkill`-style mechanisms itself.

## Conclusions reached

Full retirement of `aion-arch`'s CLI-driven workflow, in six ordered
steps:

1. **Bootstrap migration** (one-time backfill, no exceptions): every
   `aion-arch/ideas/*.md` file (all ~50, every status including
   already-`archived`) becomes an `idea`/`knownGap`/`openQuestion`
   ticket. Every archived change under
   `aion-arch/changes/archive/<name>/` is retroactively reconstructed
   as its own Epic + Story + Task tickets (already "done"):
   `proposal.md`'s content folds directly into the ticket's own
   description field, `design.md` becomes a linked Documentation
   page, and `spec.md`'s delta seeds a `spec` ticket reconciled
   against the current merged `aion-arch/specs/*.md` text before
   being finalized. `project.md` becomes the one architecture spec
   ticket, bootstrapped by hand. Also includes two audits: (a) Aion's
   own bundled baseline skills
   (`aion/assets/baseline/*/skills/*.md`) checked for any literal
   `aion-arch` reference, since those are meant to be fully generic
   for any managed project; (b) Aion's own Dart source-code comments
   checked for citations to `aion-arch` tasks/designs/files, repointed
   to the corresponding new ticket.
2. **Prove forward parity** — confirm the live ticket-native SDD
   mechanism can carry at least one real *new* change end-to-end, not
   just receive backfilled history.
3. **Cutover** — once (1) and (2) hold, stop routing new Aion work
   through `aion-arch`'s CLI.
4. **Delete outright, no migration**: `CLAUDE.md`,
   `workflow/scripts/*.sh`, `workflow/shared/*.md` — pure
   process/configuration documentation for a workflow that no longer
   runs, with no ticket-native equivalent to migrate into.
5. **Retire `aion-arch/.claude/skills/*` last** — necessarily last,
   since these are the very skills executing steps 1–4 (this
   brainstorm session included).
6. **Archive the `aion-arch` repo** (never delete) once all of the
   above lands; remove the `aion-workspace/.claude` symlink at that
   point.

## Open questions

- The concrete bulk-migration mechanism/tooling — a bespoke one-shot
  script/admin action against `TicketRepository`, versus something
  incremental — is unresolved; left for `/explore`.
- What concretely counts as "proven forward parity" (step 2) before
  cutover is greenlit — not defined this session.
- How the architecture spec ticket (`project.md`'s replacement) gets
  bootstrapped by hand, and how it's kept updated afterward, is
  already an open question inherited from
  [[spec-ticket-type]] — not resolved here either.
- Sequencing between archiving the `aion-arch` GitHub repo and
  removing the local `aion-workspace/.claude` symlink (step 6) wasn't
  pinned down beyond "both happen at that point."
- The exact fix for [[delegated-skill-provider-portability]] (a new
  `AgentProvider` capability flag, restricting `delegatedSkill` to
  known CLI-bridge providers, or Aion's own code taking over skill-
  content injection directly) is unresolved — that idea's own Open
  questions, not re-litigated here. This idea just depends on it
  landing first.

## Architectural implications

- Directly extends [[spec-ticket-type]]'s per-Epic spec-ticket
  mechanism — this idea is what applies that mechanism retroactively
  to `aion-arch`'s existing history, rather than only to Epics created
  going forward.
- Directly extends [[sdd-workflow-in-ticket-system]]'s Epic/Story/Task
  shapes and `idea`/`knownGap`/`openQuestion` ticket types (the
  `signal` split) — the bootstrap migration's target schema is exactly
  what that idea shipped, not something new.
- This idea's resolution is a migration/retirement plan, not a code
  change itself — nothing here alters shipped behavior until the
  migration is actually executed, gated on step 2's forward-parity
  proof.
- Retiring `aion-arch/.claude/skills/` is the terminal step of Aion's
  self-iteration milestone: once complete, Claude Code driven against
  `aion-arch` stops being the mechanism for developing Aion at all,
  and Aion's own in-app ticket/chat system takes over entirely.
- Hard-blocked on [[delegated-skill-provider-portability]] landing
  first — that idea fixes a real gap in
  `SkillAttachmentKind.delegatedSkill`'s provider-portability that
  this migration's own execution would otherwise inherit.