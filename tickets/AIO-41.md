---
ticketId: AIO-41
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-20T00:00:00.000
updatedAt: 2026-07-30T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# New-project onboarding — attach flow, project Inbox, and Release ticket type

## Key questions asked

1. Does "attach Aion to an existing project" mean the lightweight version — point Aion's already-shipped per-project git/storage config at a pre-existing codebase, tickets still created manually/via chat afterward — or something bigger, like Aion actively scanning the codebase and git history to auto-generate an initial backlog?
2. Given chat is always a leaf parented by epic/story/task today (no project-level, parentless chat exists), does the Inbox's use cases (dumping knowledge before any epic exists, cross-epic release planning, general Q&A) need a new structural exception, or is there an existing anchor to reuse?
3. Does the Inbox need to actually *be* a ticket/chat entity (showing up in ticket lists, search, linking), or is it better modeled as a standing, non-ticket app-level feature whose conversations spawn ordinary parentless tickets?
4. Given the established "fresh context per purpose" pattern from `sdd-workflow-in-ticket-system`, should the Inbox be one continuous chat thread, or a launcher spawning fresh, purpose-specific chats each time?
5. Does "release planning" need a first-class, persisted "release" concept tickets can be filtered/assigned to, or just ad hoc query power over existing ticket data with no new stored field?
6. (Factual) How do Jira-like platforms model releases/versions?
7. Given Aion's "everything is a ticket" philosophy, should Release become another ticket type (like Epic), reusing all existing ticket machinery for free, or a lighter non-ticket entity closer to Jira's actual Version object?
8. What should Release's relationship to Epic/Story/Task be — strict tree-parentage (Release sits above Epic), or the existing cross-cutting linked-ticket model (same as pages/resources)?
9. Is "feature" (from "define features" in the original ask) synonymous with Epic, or a genuinely distinct entity between raw idea and Epic?

## Summary of answers

- **Attach flow:** lightweight — reuse the already-shipped `multi-project-hub` per-project git/storage config, pointed at a pre-existing codebase. No automatic reverse-engineering of tickets from code. Aion *can* scan/summarize an existing codebase, but only on explicit user request, given the token cost of doing so automatically.
- **Inbox structural home:** resolved cleanly without a new compatibility-matrix exception — since the Inbox's output is ordinary Epics (which are already parentless by rule), the Inbox itself doesn't need to be a ticket at all. It's a standing, non-ticket, project-level app feature — structurally like Documentation or Trash from `persistent-navigation-shell` — with its own nav slot.
- **Inbox UI shape:** a launcher, not a single thread — the nav destination shows a history of past Inbox chats (like Documentation's page list), and each use case (brain-dump-to-tickets, what-next guidance, release planning, Q&A) starts a fresh, purpose-specific chat, consistent with the fresh-context-per-purpose pattern already established for SDD-stage chats.
- **Release, factual grounding:** Jira's closest concept is "Fix Version" — a project-scoped, named, non-issue entity (name, optional start/release dates, status of unreleased/released/archived), assignable to issues (multi-select), filterable on boards, with its own timeline/burndown view. Sprints are a separate, orthogonal concept Aion doesn't have. GitHub's Milestone is the lighter version (title + due date + issue set + progress bar).
- **Release structure:** given Aion's "everything is a ticket" philosophy, Release becomes a new first-class ticket type, structurally like Epic (parentless, top-level) — this gives it chat children (a natural fit for the release-planning Inbox chat), linked Documentation pages, search/embeddings, and Trash, all for free, rather than inventing a separate lightweight entity from scratch.
- **Release relationship to Epic/Story/Task:** cross-cutting, via the existing linked-ticket model (the same bidirectional, non-parent-child mechanism already used for Pages/Resources ↔ work tickets) — not tree-parentage. This matches how releases actually work in practice (a Story can ship early while sibling Stories in the same Epic slip to the next release; a release can bundle loose ad-hoc Tasks not tied to any Epic) and requires no new relationship type, just a new participant in one that already ships.
- **"Feature" = Epic:** confirmed synonymous — "define features" describes what the brain-dump Inbox chat purpose *does* (shape raw dumped ideas into well-formed Epics), not a separate entity. No new ticket type needed for "feature."

## Conclusions reached

- Attaching Aion to an existing project reuses `multi-project-hub`'s per-project git/storage config as-is, pointed at a pre-existing codebase; ticket backlog is seeded manually or via the Inbox's brain-dump chat, not auto-extracted. Codebase summarization is an explicit, opt-in, on-request action only (token-cost aware).
- A new standing "Inbox" app-level feature — not a ticket, its own nav slot — acts as a launcher for four purpose-specific chats: brain-dump-to-tickets, what-next guidance, release planning, and general Q&A. Each launch starts fresh context; the Inbox screen shows chat history like Documentation's page list.
- "Release" is a new first-class ticket type, parentless like Epic, linked (not parented) to whichever Epics/Stories/Tasks belong to it via the existing linked-ticket mechanism — giving release planning real, persisted, board-filterable data and free reuse of ticket machinery (chat, Documentation links, search, Trash).
- "Feature" is Epic by another name — no new ticket type required for it.

## Open questions

- **Sequencing against `sdd-workflow-in-ticket-system`:** that idea's Foundation phase already adds a new ideas/gaps ticket type and extends the type-compatibility matrix. This idea adds another new ticket type (Release) and touches the same matrix, plus the Inbox app-level feature and attach-flow work. Should these be proposed together as one combined foundational change (all pure ticket-model/infrastructure work, no execution UI yet), or kept as separate `/propose` cycles? Not decided.
- The Inbox's "brain-dump-to-tickets" chat purpose is presumably the same mechanism that operates on `sdd-workflow-in-ticket-system`'s new ideas/gaps ticket type to shape it into Epics — this connection is implied but not explicitly designed as a single mechanism yet.
- The in-app "what-next guidance" Inbox purpose is presumably a ported equivalent of the CLI's `/what-next` skill (check active SDD-stage tickets first, then gaps surfaced from the specs-as-pages "Known gaps" sections, then open ideas) — not explicitly walked through, left as an implementation detail for `/propose`.
- "Other useful project-management skills" from the original ask remains an open-ended catch-all, not resolved to anything specific beyond the four named Inbox purposes.
- Exact UI for the Inbox's nav slot placement (top-level vs. overflow, per the `persistent-navigation-shell` precedent of Board/Documentation getting top-level slots while Trash/Switch-Project stay secondary) not decided.
- **New, empirical (2026-07-23):** dogfooding self-iteration required registering the real `aion` checkout as an Aion project ahead of this idea's attach-flow shipping — and confirmed the concern this idea's own summary already anticipated. `CreateProjectCubit._initializeDesktopProject` unconditionally writes `.aion/manifest.json` and a `tickets/` directory directly into whatever `rootPath` is chosen and always runs `git init` there, with no option to keep an existing codebase's working tree untouched. Pointed at a real, already-git-tracked repo, this means Aion's own bookkeeping data and commits become indistinguishable from the project's actual source history unless the developer manually gitignores `.aion/`/`tickets/` first — which nothing in the app prompts for or does automatically. Whatever the attach flow ends up being, it should not leave this as a manual step; either the attach path (or even today's plain "New Project" path, pointed at a non-empty directory) should auto-gitignore its own bookkeeping paths, or bookkeeping should live outside the target repo's working tree entirely.

## Architectural implications

- Extends the shipped type-compatibility matrix (`define-type-compatibility-matrix`) with a new Release ticket type (parentless, like Epic) — on top of the ideas/gaps ticket type already planned in `sdd-workflow-in-ticket-system`.
- Extends the shipped linked-ticket mechanism (`notion-obsidian-like-documentation-section`) to a new participant type (Release ↔ Epic/Story/Task), beyond its current Page/Resource ↔ work-ticket use.
- Extends `persistent-navigation-shell` with a new standing, non-ticket app-level feature (Inbox), following the same precedent as Documentation/Trash.
- Reuses `multi-project-hub`'s per-project git/storage config unchanged for the "attach to existing project" flow — no new storage mechanism needed.
- Depends on [[sdd-workflow-in-ticket-system]] for the fresh-context-per-purpose chat pattern the Inbox reuses, and for the ideas/gaps ticket type the brain-dump purpose likely feeds into.
- Depends on [[provider-configuration]] for phase→provider routing of Inbox chats (same routing question as SDD-stage chats).

## Brainstorm session (2026-07-24) — resolving attach-flow bookkeeping isolation and Inbox wiring

Picked up via `/explore self-iteration-sequencing`, which found this idea's
own newest open question (the bookkeeping-in-target-repo risk, surfaced
2026-07-23 while dogfooding [[self-iteration-sequencing]]) was the only
concrete blocker left before `/propose`-ing pieces 1–2.

### Key questions asked

1. Should Aion auto-gitignore its own bookkeeping (`.aion/`, `tickets/`)
   into the target repo silently, ask first, or move bookkeeping entirely
   out of the target repo's working tree?
2. Should the resulting gate apply only to the new attach-flow entry
   point, or also retroactively to today's existing "New Project" flow
   when pointed at an already-git-tracked directory?
3. If the user declines the gitignore edit, should project creation
   proceed with a warning, or block until resolved?
4. Should the Inbox's brain-dump-to-tickets purpose create `signal`
   tickets (reusing `sdd-ticket-execution`'s existing signal→epic
   promotion mechanism), or write Epics directly?
5. Should attach-flow and Inbox be one combined `/propose`, or should
   attach-flow (cheaper, no Inbox/chat dependency) ship first as its own
   smaller change?

### Summary of answers

1. **Ask before gitignoring** — a one-time confirmation before
   `CreateProjectCubit._initializeDesktopProject` appends `.aion/` and
   `tickets/` to the target repo's `.gitignore` (creating one if absent).
   Bookkeeping still lives inside the repo's working tree, same layout as
   today, just excluded from the repo's own commits going forward.
2. **Both flows** — the check ("is rootPath already a git repo?") and the
   confirmation gate apply regardless of entry point, since today's plain
   New Project screen has the identical unguarded risk right now if
   pointed at an existing repo.
3. **Proceed with a warning** — declining doesn't block creation; Aion
   just warns that `.aion/`/`tickets/` will be tracked in the target
   repo's own history unless excluded manually later. Matches Aion's
   general inform-don't-block posture.
4. **Reuse signal→epic promotion** — brain-dump output becomes `signal`
   tickets, which then go through the same promotion path already shipped
   in `sdd-ticket-execution`, rather than growing a second raw-idea→Epic
   code path.
5. **One combined change** — attach-flow and Inbox propose together; they
   share the "starting/joining a project" theme, and the gitignore gate
   touches `CreateProjectCubit` either way, so splitting would mean two
   review cycles for closely-related work.

### Conclusions reached

Pieces 1–2 are ready for `/propose` as a single combined change:

- **Attach-to-existing-project flow** — reuses `multi-project-hub`'s
  per-project git/storage config pointed at a pre-existing codebase (no
  auto-generated backlog; optional, explicitly-triggered codebase
  summarization only).
- **Gitignore-confirmation gate** — new step in
  `CreateProjectCubit._initializeDesktopProject`, triggered whenever
  `rootPath` is already a git repo, for both the attach flow and today's
  existing New Project flow. Confirm → auto-append `.aion/`/`tickets/` to
  `.gitignore`. Decline → proceed, with a one-time warning.
- **Inbox app-level feature** — standing nav-slot launcher (not a ticket)
  spawning fresh, purpose-specific chats: brain-dump-to-tickets (writes
  `signal` tickets into the existing promotion pipeline), what-next
  guidance, release planning, general Q&A.

### Architectural implications

- Extends `CreateProjectCubit` (today's plain New Project path) with new
  gitignore-detection/confirmation behavior, not just the new attach-flow
  screen — a wider blast radius on that Cubit than originally scoped.
- Confirms the Inbox's brain-dump purpose is a second entry point into
  `sdd-ticket-execution`'s existing signal→epic promotion mechanism, not a
  parallel implementation — no new promotion logic needed.
- Closes out the last blocker `self-iteration-sequencing.md` flagged
  before this idea's remaining pieces could be proposed.

## Brainstorm session continued (2026-07-24) — remaining facets

User feedback mid-session: prior brainstorm sessions were stopping too
early, at the first resolved architectural fork rather than covering every
facet of a multi-piece idea (see `[[feedback_brainstorm_question_depth]]`
memory note). Continued this same session to resolve the facets
previously deferred to `/propose` rather than leaving them unprobed.

### Key questions asked

1. What should codebase summarization (attach flow's opt-in feature)
   concretely produce?
2. What should it actually read, given the token-cost concern that made
   it opt-in — full agentic pass, structural-only pass, or reuse of
   existing embedding search?
3. Follow-up, given the user's answer (let the user choose depth; a
   shallow pass should know it's shallow and dive deeper on demand): how
   does "dive deeper on demand" actually get triggered in a later chat?
4. What should the Inbox's "release planning" chat purpose concretely do?
5. What scope should the Inbox's general Q&A chat purpose have — what can
   it read?
6. Anything specific for the "other useful project-management skills"
   catch-all, or stay explicitly deferred?
7. Should the Inbox's "what-next guidance" purpose be a literal port of
   the CLI's `/what-next` logic, or adapted?
8. Where should Inbox sit in `persistent-navigation-shell` — top-level
   slot (like Board/Documentation) or secondary/overflow (like Trash)?

### Summary of answers

1. **Signal tickets** — codebase summarization writes `signal` tickets
   describing what it found, feeding the same signal→epic promotion
   pipeline as brain-dump — not a standalone summary page, not both.
2. **User's own framing, more precise than any of the three options
   offered:** Aion is a general-purpose tool for *any* software project,
   not just itself — so this isn't a single fixed choice. The user picks
   depth (shallow structural pass vs. full agentic read) per attach, and
   a shallow pass must carry forward the fact that its own knowledge is
   incomplete rather than presenting it as complete.
3. **Model-initiated** — the shallow summary's context includes an
   explicit "this knowledge is shallow" flag; a later chat's own model
   decides mid-conversation to read further files when it recognizes the
   gap, using the same tool-enabled mechanism as coding execution rather
   than requiring a separate manual "get deeper context" action or a
   fully automatic pre-flight escalation.
4. **Conversational release assembly** — the chat queries existing
   Epics/Stories/Tasks (read-only) and proposes which to link to a new or
   existing Release, creating the Release ticket and the links as it
   goes — not read-only reporting alone.
5. **Tickets + docs + source code (read-only)** — same read-only tool
   tier as the `design-gate-for-ticket-driven-sdd-workflow`'s
   `designSync` stage, so Q&A can answer "how does X work in the code"
   questions, not just project-management ones.
6. **Redirected, not deferred as a vague catch-all** — the user's actual
   concern was concrete: today's skills/conventions (`flutter_verifier.dart`,
   the baseline manifest's `conventions/flutter-conventions` asset — see
   Architectural implications) are hardcoded to Flutter/Dart, inherited
   from being built to develop Aion itself, but Aion is meant to work on
   *any* software project. This is out of scope for this idea — see
   Follow-up decisions below; it's split into its own idea file.
7. **Literal port** — same three-check priority order (active SDD-stage
   tickets, known-gaps-from-specs-as-Pages, raw signal tickets), reading
   from ticket/page data instead of parsing `aion-arch` markdown — no new
   logic, just a new data source for the existing algorithm.
8. **Top-level slot** — Inbox is a primary, frequently-used entry point
   (start a new project, brain-dump, ask what's next), not an occasional
   utility like Trash/Switch-Project.

### Conclusions reached

All remaining facets of pieces 1–2 are now resolved, alongside the
earlier session's conclusions:

- **Codebase summarization** — opt-in, user-selectable depth (shallow
  structural vs. full agentic), writes `signal` tickets either way. A
  shallow-depth project carries a persistent "knowledge is shallow" flag
  that later chats' own models use to decide when to read further files
  on demand.
- **Release planning chat** — conversational; creates/links Release
  tickets directly rather than just reporting on existing ones.
- **General Q&A chat** — read-only access to tickets, docs, *and* source
  code (reusing the `designSync`-stage tool tier), not project-data only.
- **What-next guidance chat** — literal port of the CLI `/what-next`
  algorithm onto ticket/page data sources.
- **Inbox nav placement** — top-level slot in `persistent-navigation-shell`.

### Follow-up decisions

- **Split out a new idea:** "make the SDD/coding-execution mechanism
  project-type-aware" (working title) — covers generalizing
  `FlutterVerifier` into a per-language/toolchain verifier abstraction,
  making the baseline manifest's architecture-convention asset vary by
  attached project type instead of always shipping
  `conventions/flutter-conventions`, and auditing skill/prompt content
  for Dart/Flutter assumptions. This absorbs what was previously an
  open-ended "other useful PM skills" catch-all — the user's actual
  concern was Aion's own Flutter-centric bootstrapping leaking into every
  future attached project, not an unnamed fifth Inbox purpose. Confirmed
  as its own idea file rather than a fourth piece of this one, given the
  surface area (verifier abstraction, baseline/asset system, skill
  content) is large enough to warrant its own dedicated brainstorm.
  The attach flow's project-type detection step becomes that new idea's
  entry point, not this one's.

### Architectural implications

- Codebase summarization's "shallow knowledge, deepen on demand" pattern
  reuses the exact tool-enabled mechanism coding-execution already has
  (model decides to read files mid-turn) — no new capability class, just
  a new context flag driving existing model behavior.
- Release-planning's read-then-link behavior needs the same read access
  to Epic/Story/Task data the what-next chat needs — likely shares
  context-assembly plumbing with it rather than being built independently.
- Q&A's read-only source-code tool tier is the same one
  `design-gate-for-ticket-driven-sdd-workflow` already defined for
  `designSync` — a second consumer of that tier, not a new one.
- Confirms `FlutterVerifier` (`aion/lib/core/build/flutter_verifier.dart`)
  and the baseline manifest's `conventions/flutter-conventions` asset
  (`aion/assets/baseline/0.2.0/manifest.json`) are both hardcoded to
  Flutter/Dart today — real, code-confirmed blockers for attaching Aion
  to a non-Flutter project, now scoped into a new, separate idea rather
  than this one.

## Brainstorm session (2026-07-24) — Inbox chat history

Resolved a structural wrinkle the earlier sessions left implicit: every
`chat` ticket today always has a parent (`TicketTypeHierarchy.isAlwaysRoot`
is `true` only for `epic`/`signal`/`release`), but the Inbox itself isn't
a ticket, so an Inbox-launched chat has nothing to be parented under.

### Key questions asked

1. Should Inbox-launched chats become parentless `chat` tickets
   (extending `isAlwaysRoot`), or anchor to something else structurally?
2. How should the Inbox history list organize its four chat purposes —
   a single chronological list, or grouped/tabbed by purpose?
3. Should the history list get the same embedding-based search
   Documentation has, or is a plain list enough for v1?

### Summary of answers

1. **Parentless chat, extend `isAlwaysRoot`** — but only for
   Inbox-spawned chats specifically; every other chat-creation path
   (SDD-stage, coding-execution, signal/release chat) keeps requiring a
   parent exactly as today. Reuses every existing chat mechanism
   (comments, streaming, agent wiring) unchanged — only the
   parent-requirement rule gets a narrow exception.
2. **Single chronological list, purpose badge per row** — simplest,
   matches Documentation's own flat-list-plus-search precedent, and a
   mixed-recency view naturally surfaces what's actually been used
   lately. No tabbed/grouped navigation pattern (Aion has no existing
   precedent for that).
3. **Depends on whether agents consider Inbox history when making
   decisions** — resolved by checking that question first (see below):
   since the answer is no, a plain list is fine for v1. Search stays a
   pure human-browsing convenience, not load-bearing for any agent
   decision, deferrable until there's evidence a long-enough history
   actually needs it.
   - **Follow-up resolved:** should any Inbox purpose (what-next guidance
     especially) automatically recall past Inbox chats as context?
     **No — strictly fresh, no auto-recall.** Consistent with this
     idea's own already-established "fresh context per purpose"
     principle (the same one SDD-stage chats already follow). If the
     user wants to reference something from before, they bring it up
     themselves.

### Conclusions reached

- `chat` gains a narrow `isAlwaysRoot` exception for Inbox-spawned chats
  only — every other chat-creation path is unaffected.
- Inbox's history screen: one reverse-chronological list of past Inbox
  chats, each row tagged with a small badge/icon for which of the four
  purposes it was.
- No embedding search for v1 — confirmed unnecessary since no Inbox
  purpose auto-recalls history as agent context; add later only if a
  real need shows up.

### Architectural implications

- `TicketTypeHierarchy.isAlwaysRoot` gains its fourth `true` case
  (`chat`, Inbox-scoped) — the matrix now needs a way to distinguish
  "this chat is allowed to be parentless because the Inbox spawned it"
  from "chat generally requires a parent," since the type alone
  (`chat`) can't carry that distinction — left for `/propose`'s
  design.md to resolve (e.g. a spawn-origin flag, or a dedicated Inbox
  chat marker) rather than loosening the rule for every chat
  unconditionally.
- Reinforces this idea's own "fresh context per purpose" principle as a
  hard boundary that also governs whether Inbox history search is worth
  building at all — a UI decision (search) ended up resolved by an
  agent-behavior decision (no auto-recall) rather than a UX judgment
  call alone.

## Brainstorm session (2026-07-24) — revisiting the first-part decisions

Re-explored under the "ask as much as necessary" fix (see
`[[feedback_brainstorm_question_depth]]` memory note): the earliest part
of this idea's very first session (bookkeeping-isolation gate, gate
scope, decline behavior, brain-dump target, propose scoping) was
resolved before that fix, with less probing than later sessions got.
Revisited each in light of everything built/decided since.

### Key questions asked

1. Given `chat-transcript-ux-redesign` didn't exist when "propose
   scoping" was first decided, and Inbox specifically depends on it
   shipping first while attach-flow doesn't — does the combined-change
   decision still hold?
2. Given `bug-ticket-type` didn't exist when "brain-dump target" was
   first decided, should brain-dump's promotion step now also be able
   to target Bug, not just Epic?
3. Follow-up: how should the feature-vs-defect classification actually
   happen when promoting a signal?
4. Follow-up: how should the brain-dump chat's classification
   suggestion actually be carried on the signal ticket?
5. Does the gitignore-confirmation gate apply on mobile/web, or is it
   desktop-only?
6. Given `board-execution-indicators-and-notifications` has since
   relocated toasts to a shell-level, app-wide mechanism, should the
   decline-warning reuse it, and should it persist beyond a one-shot
   toast?
7. When should the gitignore-confirmation prompt actually appear — a
   blocking modal at submit, or an inline banner as soon as an
   already-git-tracked directory is detected?

### Summary of answers

1. **Split** — attach-flow proposes and ships on its own now (no
   dependency on the chat redesign); Inbox becomes its own follow-up
   `/propose`, deliberately sequenced after `chat-transcript-ux-redesign`
   so its chat surface is built against the new design from day one.
2. **Extend promotion to support Bug too** — reopens `bug-ticket-type`'s
   scope slightly (it explicitly didn't touch the promotion mechanism),
   but a defect-describing signal shouldn't be forced through an
   Epic-shaped promotion.
3. **Model suggests during brain-dump** — the chat itself classifies each
   raw idea as it writes signal tickets, tagging a suggested promotion
   type; the human can still override at promotion time.
4. **New dedicated field** — `Ticket.suggestedType: TicketType?`
   (meaningful only for `signal` tickets), set by the brain-dump chat.
   The promotion UI reads it to pre-select/default the epic-vs-bug
   choice — consistent with Aion's existing preference for structured
   fields (`SddStage`, `complexity`) over embedded prose parsing.
5. **Desktop-only** — `CreateProjectCubit._initializeDesktopProject`
   (where this gate lives) is already desktop-only; mobile/web projects
   have no `rootPath`/git repo to pollute.
6. **Reuse the shell-level toast, stay one-shot** — consistent with
   every other in-app notification now that one exists; no persistent
   indicator, since the user can always fix it later via the Overrides/
   Settings surface `project-type-aware-conventions-and-verification`
   adds, and a permanent nag overstates a low-stakes, easily-reversible
   state.
7. **Inline banner, pre-submit** — appears the moment `ProjectStackDetector`
   detects an already-git-tracked directory (the same detection moment
   `project-type-aware-conventions-and-verification` already introduced
   for verify-command suggestions), with a checkbox the user sets before
   ever hitting submit — no separate modal interruption.

### Conclusions reached

- **Propose split, revised:** attach-flow (gitignore gate + codebase
  summarization) proposes independently, now. Inbox is a separate,
  later `/propose`, gated on `chat-transcript-ux-redesign`.
- **Brain-dump promotion widened:** signals can now promote to either
  Epic or Bug, classified by the brain-dump chat itself via a new
  `Ticket.suggestedType` field, human-overridable at promotion time.
- **Gitignore gate mechanics fully specified:** desktop-only, inline
  banner at the same moment stack-detection already runs, decline
  proceeds via the shell-level toast mechanism, one-shot, no persistent
  indicator.

### Architectural implications

- `bug-ticket-type`'s "no new promotion logic needed" conclusion is
  superseded — `promoteSignalToEpic` needs to generalize into a
  type-aware promotion step (Epic or Bug) as part of whichever change
  implements the Inbox's brain-dump purpose, not as originally scoped.
- Adds `Ticket.suggestedType` as a new universal-but-mostly-null field,
  following the same pattern `complexity`/`sddStage` already established
  — meaningful only for one `TicketType` (here, `signal`), `null`
  elsewhere.
- Ties the gitignore-gate's UI timing directly to
  `project-type-aware-conventions-and-verification`'s `ProjectStackDetector`
  — both fire off the same "directory just chosen" moment in
  `NewProjectScreen`, worth implementing as one coordinated banner
  rather than two independent ones stacking awkwardly, when attach-flow
  is eventually proposed.
- Confirms the decline-warning and any future attach-flow notifications
  should route through `board-execution-indicators-and-notifications`'s
  shell-level toast mechanism as the one, consistent in-app notification
  surface — no ad hoc per-feature toast handling going forward.