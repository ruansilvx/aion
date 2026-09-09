<!-- Keep a Changelog format (https://keepachangelog.com). Sections are
     filled in by the `/prepare-release` skill (aion-arch/.claude/skills/
     prepare-release/), never hand-edited except to seed notes ahead of
     the next release. -->

# Changelog

## [Unreleased]

## [0.1.0] - 2026-09-09

First release. Everything below was built pre-release, so this entry
covers the project's entire history rather than a delta since a prior
tag.

### Added

- **Foundation & ticket model** — the first vertical ticket slice
  (list/create/detail); ticket editing, deletion (later soft-delete),
  and status editing in place; parent (`parentId`) made editable with
  cycle-prevention; a strict type-compatibility hierarchy for
  reparenting; epics rejected as reparent targets.
- **Board & list** — a Kanban Board view; sort control with Board as
  the new default view; multi-select Status/Type/Priority filters;
  persisted List/Board choice and configurable Board column
  visibility; database-backed ticket search with pagination; ticket
  parent selection UX (set-at-creation, ancestor breadcrumbs); bulk
  status/priority edit and delete entry points on list/board rows;
  visual blocks/blockedBy ordering plus a hard gate preventing a
  blocked ticket from starting; a link-count fix excluding trashed
  tickets; a link-management UI (type indicator, remove, in-place
  retype); a page-nesting depth clamp; a consistent max-width content
  layout across wide screens.
- **Trash** — soft-delete/Trash replacing hard delete, with subtree
  cascade and bulk delete; per-row age indicator and manual purge;
  automatic purge on launch; multi-select restore/permanent-delete
  inside the Trash screen; restore wired into git projection.
- **Documentation** — a dedicated Documentation section for
  page/resource tickets (nesting, linking, full-text search,
  backlinks); a full Markdown content editor in its own feature
  module; inline `[[wikilink]]` backlinks.
- **SDD workflow, ticket-native** — Signal/Release ticket types (Signal
  later split into Idea/Known Gap/Open Question); stage-triggering,
  live stage chats, and `AutomationConfidence`; a ticket-native design
  gate (designBrief/designSync); a quality gate before
  verifying→archived; project-configurable transition preconditions;
  a Spec ticket type auto-written from an Epic's outcome, with
  auto-linking of related gaps/bugs; project-configurable
  `TicketStatus`/`SddStage` data instead of fixed enums; any named
  skill (or an Aion-native prompt template) attachable to a status or
  stage, confidence-gated; ticket-graph and embedding-based context
  enrichment for spawned chats; generalized live-refresh for open
  ticket detail screens; estimate/timeSpent rollup across a ticket's
  descendants; a live-ticking "Updated x ago" timestamp.
- **Agentic coding execution** — the first working `AgentModelClient`
  (Claude Agent SDK via a bundled Node bridge) with a Settings
  connection/model picker; moving a Task to In Progress triggers a
  real, tool-enabled coding-execution run; per-phase (frontier/capable/
  execution) model routing; a pluggable `AgentProvider` abstraction
  plus a second, Anthropic-Messages-API-backed provider; a capability
  flag gating skill-discovery-dependent runs to providers that
  actually support it; per-run dependency caching and ancestor-aware
  sibling-conflict scheduling; concurrent, cancellable, restart-safe
  execution with Strict FIFO/Parallel/Hybrid modes; an isolated git
  worktree per run with a pre-PR verify gate and failure/stall
  visibility; a Bug ticket type with full execution parity to Task;
  reliable PR metadata parsing and a persistent notification center;
  Board execution/SDD-stage-advancement indicators; pre-flight and
  running token-cost estimates; project-editable decision graphs
  (deterministic rule builder, plus a model-judgment condition backed
  by guaranteed session resumption); `create_ticket`/`add_link`/
  `log_time` mid-chat tool calls; mid-task chat branching with
  fold-back; one reused execution chat per Task instead of a new one
  per retry; automatic, system-measured time tracking on every AI
  turn.
- **Chats & Inbox** — a redesigned chat transcript (collapsing header,
  turn-taking layout, Markdown rendering, auto-expanding compose
  field); an Inbox for capturing raw ideas/gaps/questions; AI-assisted
  complexity/estimate suggestions on tickets.
- **Projects & onboarding** — multi-project Hub (per-project database
  and git repo, versioned baseline); attach-to-existing-project
  onboarding with gitignore confirmation and optional codebase
  summarization; per-project baseline upgrade flow; a detector for a
  bundled baseline skill falling behind its source; the project's own
  effective verify-skill content used as coding-execution's verify
  step, replacing a hardcoded/shell-command check.
- **Persistence & sync** — bundled on-device ticket embeddings,
  ticket-to-Markdown git projection, and matching lint/repair tooling;
  reconciler support for hand-edited `parentId`/`deletedAt` changes;
  ticketId preserved (not re-minted) on DB reconstruction; two fixed
  git-projection gaps (several structural writes bypassing projection
  entirely; trash/restore cascades not projecting every affected
  ticket, plus a related reconstruction crash on trashed tickets);
  visible trash/restore commits.
- **Navigation & design system** — a persistent sidebar/tab-bar
  navigation shell; the design system moved into its own
  `lib/design_system/` module (tokens/atoms/molecules); keyboard focus
  and activation support across overlay menu rows; barrel files for
  the design system, core, and tickets feature; private build-method
  widgets retrofitted into real widget classes, with an enforcing
  check; full `intl`/ARB localization retrofit.
- **Aion's own development process** — a built-in, per-project
  "Prepare Release" capability, independent of Claude Code; a one-time
  bootstrap migration of `aion-arch`'s idea/change history into Aion's
  own ticket store; exploring-stage chats scoped explicitly to
  read-only investigation; `project.md` reworded to name agentic tiers
  by role rather than vendor.
- **Release readiness** — a real app icon; the Linux build decoupled
  from the release gate so it can't block a Windows-only release;
  live workflow-status UI wiring across every screen that reads
  ticket status; a validated `AutomationConfidence.auto` pass; and
  end-to-end native Windows verification (ticket creation, git
  projection, Board drag-and-drop, Trash restore, provider connection,
  and a full coding-execution → PR cycle).

### Fixes & chores

- Restored `TicketParentTrashService`'s not-found guard on trash/restore.
- Added missing focus-ring visuals to `WorkflowStatusSettingsScreen`.
- Fixed system-divider spacing being heavier than the inter-message gap.
- Anchored `.gitignore`'s `tickets/` rule to the repo root.
- Granted `agent_bridge` write access for headless coding-execution runs.
- Addressed `/verify` findings for `ticket-link-management-ui` and
  `overlay-menu-keyboard-focus`.
- Extracted `TicketOverflowMenu`'s root menu/chooser and `SelectionMenu`'s
  itemBuilder/trigger content into real widget classes.
- Tracked ticket bookkeeping (`tickets/*.md`, `.aion/manifest.json`) in
  Aion's own source repo instead of gitignoring it.
- Backfilled tickets for two archived changes
  (`fix-ticket-git-projection-gap`, `scope-exploring-stage-instructions`,
  `fix-ticket-trash-cascade-projection-gap`) that landed after the
  bootstrap migration's snapshot.
- Undid a blanket `dart format` pass on `tickets_cubit_test.dart`.
- Regenerated plugin registrants and the pub lockfile.
- Initial Flutter project setup and repo housekeeping (`.gitignore`,
  removing `.env` from tracking, untracked local Claude Code/MCP
  config).
