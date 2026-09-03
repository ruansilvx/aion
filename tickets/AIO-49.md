---
ticketId: AIO-49
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-19T00:00:00.000
updatedAt: 2026-07-19T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Persistent navigation shell for Board/Documentation/future sections

we need to improve ux. I'm thinking of creating a hub where you can
access both board and documentation (and other sections in the future)
instead of having just an icon in the tickets page. Today, if I go to
the documentation there is no way to go back to the tickets (using
other platforms besides web).

## Key questions asked

1. Right now Board and Documentation are separate top-level routes
   reached via a header icon button, with no shared chrome between
   them. What should the "hub" actually be?
2. Today's header icon row on TicketsListScreen has 4 items:
   Documentation-entry, Trash-entry, Switch-Project, and Select-mode
   toggle. Which of these should be promoted into the new persistent
   nav shell alongside Board/Documentation, versus staying as a
   secondary/overflow action?

## Summary of answers

1. Persistent nav shell (not a landing/launcher page) — a sidebar on
   wide layouts, a bottom tab bar on narrow ones, always visible
   across Board, Documentation, and future sections. Switching
   sections is a single tap/click from anywhere; no dead-end screens.
2. Only Board + Documentation get top-level slots. Trash and
   Switch-Project stay as secondary/overflow actions (they're not
   content sections — Trash is a utility view, Switch-Project is
   project-level, not section-level).

## Conclusions reached

Build a persistent navigation shell wrapping `/workspace/*`:

- **Structure**: adaptive shell — sidebar (rail or full sidebar,
  TBD at /propose) on wide/desktop/web layouts, bottom tab bar on
  narrow/mobile layouts. Replaces the current pattern of duplicating
  icon buttons per-screen (`_SwitchProjectButton`,
  `_TrashEntryButton`, Documentation-entry button all currently live
  inside `tickets_list_screen.dart`).
- **Top-level slots**: Board, Documentation, and room for future
  sections (e.g. a future Chat section per `project.md`'s open
  "Agentic Engine" question). This is the extensibility the user
  explicitly wants ("other sections in the future").
- **Secondary/overflow**: Trash-entry and Switch-Project move out of
  the top-level nav into a secondary surface (exact placement —
  overflow menu, profile-style corner menu, etc. — is an
  implementation detail for `/propose`).
- **Root problem fixed structurally**: today `DocumentationScreen` has
  no way back to Board on non-web platforms because there's no shared
  chrome at all — each screen currently owns its own local header
  buttons. A persistent shell fixes this for every current and future
  section at once, rather than adding a one-off back button to
  `DocumentationScreen`.

## Open questions

- Exact shell widget shape (`NavigationRail` vs. a custom sidebar;
  bottom `NavigationBar` vs. custom tab bar) — implementation detail
  for `/propose`.
- Where exactly Trash and Switch-Project land once demoted from
  top-level (overflow menu on the shell itself vs. staying
  screen-local) — implementation detail for `/propose`.
- Whether existing routes (`/workspace/tickets`,
  `/workspace/documentation`) stay as-is under the new shell, or get
  restructured (e.g. nested under a shared shell route) — routing
  detail for `/propose`/`/design-sync`.
- Not addressed this session: three related bugs the user flagged
  (chevron shown on documentation pages with no children, markdown
  checkbox syntax not rendering, info bubbles like "synced" clipping
  near the viewport edge on Windows) — user explicitly deferred these
  out of this brainstorm to be handled as direct fixes, not design
  exploration.

## Architectural implications

- Touches `core/routing/app_router.dart` and likely introduces a new
  shared shell widget (outside any single feature module, similar in
  spirit to how `core/contracts/` mediates cross-feature access today).
- Interacts with [[hub-and-infrastructure-to-support-multiple-projects]]
  — that idea shipped the *project*-level switcher (`/hub` →
  `/workspace`); this idea is the *section*-level nav living inside an
  already-active project's workspace. The two are different altitudes
  and should stay conceptually separate (project switch is not a
  "section").
- Directly resolves the "no way back" complaint from
  [[notion-obsidian-like-documentation-section]]'s shipped
  Documentation section, which only ever added a one-way entry icon,
  not shared chrome.
- Paired with [[consistent-max-width-content-layout]] from the same
  session — both are cross-cutting UX-consistency changes, but
  architecturally separate (shell/routing vs. layout-widget
  convention). Could be proposed as one combined change or two
  sequential ones; left for `/propose` to decide based on scope.