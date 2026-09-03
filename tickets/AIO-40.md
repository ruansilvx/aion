---
ticketId: AIO-40
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-10T00:00:00.000
updatedAt: 2026-08-10T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Multi-select filters for the ticket list (status, type, priority)

## Key questions asked

1. Where does single-select filtering actually get in your way day to
   day — status, type, priority, or a specific combination?
2. How does Jira (and similar platforms) handle multi-select filters —
   asked for inspiration before deciding Aion's shape.
3. Given Jira's full pattern is fairly heavy for a solo-dev tool: one
   combined popover (lighter), or the full per-field-dropdown-plus-chips
   treatment?
4. Chips or no chips, given the "lighter" direction chosen?
5. If chips: do they replace the single combined popover (back to
   per-field dropdrowns), or coexist with it (chips just for
   showing/removing selections made via the popover)?
6. Should filter selections persist across app restarts, or reset each
   time the ticket list opens?
7. If persisted, is it per-project or global?
8. Does Aion have existing per-project settings/preferences storage to
   hook into, or does this need something new? (Answered by codebase
   check, not the user.)
9. Given the known `AppDropdown` overlay-row gap (bare `GestureDetector`
   issue) flagged in `tickets.md`'s known gaps — should this new
   multi-select UI extend/fix `AppDropdown`, or be a separate widget?

## Summary of answers

- The single-select limitation affects all three fields (status, type,
  priority) — not just one.
- Jira's pattern: per-field dropdown with checkboxes, selected values as
  removable chips in a filter bar, OR-within-field/AND-across-field
  combination logic, plus a "Clear all" affordance. Judged too heavy for
  a solo-dev tool.
- Chosen shape: **one combined "Filters" popover** containing three
  checkbox groups (Status/Type/Priority) as the single entry point for
  making selections — not three separate per-field buttons/dropdowns.
- Chips are wanted, but only as a **removable summary of active
  selections** below/beside the Filters button — not as the selection
  mechanism itself. The popover stays the only way to add filters.
- Persistence: selections should **survive app restarts**, scoped
  **per project** (switching projects shouldn't carry over another
  project's filter state).
- Codebase check found **no existing per-project settings storage** —
  Aion's three current `SharedPreferences`-backed repos
  (`SharedPrefsAutomationSettingsRepository`,
  `SharedPrefsModelRoutingRepository`,
  `SharedPrefsExecutionContextCapRepository`) all use flat, global keys,
  not project-scoped ones. Each project's own Drift DB
  (`app_database.dart`) only has ticket-domain tables (`TicketsTable`,
  `TicketIdSequenceTable`, `TicketLinksTable`, `TicketCommentsTable`) —
  no settings table. Decision: extend the `SharedPreferences` pattern
  with project-id-prefixed keys rather than add a new Drift table —
  consistent with existing precedent, no migration needed.
- The new multi-select UI will be a **new dedicated widget**, kept
  separate from `AppDropdown` — the popover's checkbox-group + chip-row
  shape is different enough from `AppDropdown`'s single-select list that
  reuse isn't a clean fit, and it avoids entangling this change with
  `AppDropdown`'s separate known overlay-row bug.

## Conclusions reached

Build a single combined "Filters" popover (new dedicated widget, not an
`AppDropdown` extension) with three multi-select checkbox groups —
Status, Type, Priority — combined as OR-within-field/AND-across-field.
Active selections render as a removable chip row for visibility; the
popover remains the only entry point for changing selections. Selections
persist per-project across restarts via `SharedPreferences` keys prefixed
with the project id, following the existing settings-repository pattern.
Selection/combination/persistence orchestration logic lives in
`TicketsCubit`, per Aion's existing Cubit-owns-domain-logic convention —
not in a repository or the widget layer.

Ready for `/propose`.

## Open questions

- Exact `SharedPreferences` key naming scheme (e.g.
  `ticket_list_filters.<projectId>.status`) — implementation detail for
  `/propose`.
- Whether this change should also pick up the adjacent "no user-facing
  sort control" known gap in the same pass, or stay scoped strictly to
  filters — not decided in this session; `/propose` should scope
  narrowly to filters unless the user says otherwise.
- `AppDropdown`'s bare-`GestureDetector` overlay-row bug remains
  unresolved and out of scope for this change.

## Architectural implications

- Introduces a new Flutter widget (undetermined name, e.g.
  `TicketFilterPopover`) distinct from `AppDropdown`.
- Extends the `SharedPreferences`-backed settings-repository pattern to
  be project-scoped for the first time — future per-project preferences
  can follow the same project-id-prefix convention.
- Filter state (selected sets per field) and combination logic belong in
  `TicketsCubit`, consistent with [[feedback_cubit_domain_logic]] —
  reinforces that convention rather than introducing an exception.
- No changes needed to the per-project Drift DB schema.