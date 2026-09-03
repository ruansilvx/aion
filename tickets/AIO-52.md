---
ticketId: AIO-52
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-21T00:00:00.000
updatedAt: 2026-08-21T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# PR metadata parsing and persistent notification center

## Key questions asked

1. Given these four gaps together (PR metadata parsing, notification
   center, per-run dependency caching, sibling-conflict beyond
   `parentId`) are all real but non-breaking polish, should they ship as
   one bundled change (as the two prior coding-execution sessions both
   did) or split into independently-proposable ideas?
2. If split, does it follow the proposed pairing — PR metadata +
   notification center as one UI/observability-facing idea, dependency
   caching + sibling-conflict as a second execution-mechanics idea — or
   should each of the four stand fully alone?
3. For the notification center specifically: full persisted
   `Notification` entity (read/unread, survives restart) from the start,
   or a simpler in-memory session-only history list first?
4. Should the center's events cover both coding-execution status changes
   and Epic/Story SDD-stage-chat states (as the shipped Board indicator
   already does), or stay scoped to coding-execution only, matching how
   the gap note in `tickets.md` names it?
5. Should the parsed PR metadata (number, file count) feed a
   notification-center "PR opened" entry's text, not just the existing
   banner sub-line — one parse, two consumers?

## Summary of answers

1. **Split**, not bundled — these four don't share the tight mechanical
   coupling the prior two sessions' findings did (e.g. worktree
   isolation being a hard prerequisite for the verify-gate split).
2. **Follow the proposed pairing.** This idea covers PR metadata +
   notification center; a sibling idea
   ([dependency-caching-and-ancestor-sibling-conflict](dependency-caching-and-ancestor-sibling-conflict.md))
   covers the other two.
3. **Full persisted entity**, not a session-only list. Notifications
   should survive an app restart from the start, not get built cheap now
   and re-architected later.
4. **Both.** Coding-execution status changes and Epic/Story SDD-stage
   chats populate the same notification stream — reusing
   `board-execution-indicators-and-notifications.md`'s existing computed
   states as the event source rather than inventing a narrower one.
5. **Yes.** One parse of the `gh pr create` response feeds both the
   banner sub-line and the notification entry's text — avoiding two
   independent, potentially-diverging renderings of the same fact.

## Conclusions reached

- **PR metadata parsing:** parse `gh pr create`'s response for PR number
  and file count at the point Aion already calls it (per
  `coding-execution-reliability-and-safety.md`'s Aion-driven PR-opening
  step). This single parse feeds two consumers: the existing
  `_ExecutionActionBanner(tone: .success)` sub-line (currently always
  omitted) and a new notification-center entry's text.
- **Notification center:** a new, fully persisted `Notification` entity
  (Drift table) — read/unread state, survives app restart — not a
  transient/session-only list. Explicitly the surface
  `board-execution-indicators-and-notifications.md` deferred "until
  Aion invests in parallel execution," a precondition `parallel-work.md`
  has since met.
- **Event coverage:** both Task coding-execution states (`isExecuting`,
  `executionAwaitingReview`, `executionFailureReason`, PR-opened) and
  Epic/Story SDD-stage-chat states (`isAdvancingStage`-equivalent) feed
  the same notification stream — matching the Board indicator's existing
  scope rather than the narrower "coding-execution status changes"
  wording in the current gap note.
- **One parse, two consumers:** PR metadata parsing and the notification
  center are coupled specifically because the parsed data is what makes
  a "PR opened" notification entry meaningfully different from a bare
  status ping.

## Open questions

- Exact `Notification` entity shape (fields beyond read/unread, per-event
  payload shape, retention/pruning policy if any) — left for
  `/propose`'s design.md.
- Where the notification center surfaces in the UI (bell icon +
  dropdown, dedicated screen, both) — a `design-brief`/`design-sync`
  question, not architectural.
- Whether marking a notification read has any side effect on the
  underlying ticket/execution state, or is purely local to the
  notification itself — not raised this session.
- Whether `gh pr create`'s response format needs defensive parsing
  (fallback when number/file-count fields are absent or the CLI version
  differs) — left for `/propose`.

## Architectural implications

- First real persisted entity for notifications — a new category of
  storage, following existing Drift table conventions rather than
  reusing an existing table.
- Directly builds on `board-execution-indicators-and-notifications.md`'s
  computed-state work (`isExecuting`/`executionAwaitingReview`/
  `executionFailureReason`/`isAdvancingStage`) as its event source, and
  fulfills that idea's explicitly-deferred notification-center follow-up
  now that `parallel-work.md` has shipped the stated precondition.
- The `gh pr create` call site (Aion-driven PR-opening, per
  `coding-execution-reliability-and-safety.md`) gains a response-parsing
  step it didn't previously need, since today it only checks for a
  returned URL.