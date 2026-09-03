---
ticketId: AIO-28
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
# Per-run dependency caching and ancestor-based sibling-conflict scheduling

## Key questions asked

1. Given these four gaps together are all real but non-breaking polish,
   should they ship as one bundled change or split into independently
   proposable ideas? (Shared session with
   [pr-metadata-and-notification-center](pr-metadata-and-notification-center.md).)
2. If split, does it follow the proposed pairing — dependency caching +
   sibling-conflict as one execution-mechanics idea?
3. For dependency caching: symlink shared build/dependency directories
   (`.dart_tool`/`build`/`node_modules`) straight from the main checkout
   into each worktree (the gap note's own suggested example), or use a
   separate, run-independent cache directory instead, to avoid
   reintroducing the original worktree-isolation risk?
4. For sibling-conflict beyond `parentId`: generalize to any shared
   ancestor at any depth (walk the full parent chain), or replace the
   hierarchy-proximity signal entirely with something like inferred
   file/path overlap from ticket content?

## Summary of answers

1. **Split**, not bundled — answered once, shared with the paired idea.
2. **Follow the proposed pairing.** This idea covers dependency caching
   + sibling-conflict; the sibling idea covers PR metadata + notification
   center.
3. **Separate, run-independent cache directory** — hardlinked or copied
   into each worktree, never the main checkout itself. Symlinking
   straight from the shared checkout was judged too risky: it's exactly
   the kind of run-to-shared-tree coupling
   `coding-execution-reliability-and-safety.md`'s worktree isolation was
   built to eliminate (a run's build tooling writing into `.dart_tool`/
   `build`/`node_modules` could still mutate state a human's shared
   checkout depends on, even if the top-level source files stay
   isolated).
4. **Generalize to any shared ancestor.** Walk the full parent chain
   instead of comparing `parentId` directly. Since Aion's ticket
   hierarchy is capped at Epic → Story → Task/Bug (three levels), "any
   shared ancestor" is already naturally bounded — the ceiling case is
   simply "same Epic," not an unbounded walk.

## Conclusions reached

- **Dependency caching:** each coding-execution worktree gets its
  build/dependency directories (`.dart_tool`/`build`/`node_modules`,
  language-dependent) populated from a separate cache location via
  hardlink or copy — never a live symlink back to the developer's main
  checkout. This keeps the caching win (avoiding a from-scratch
  dependency fetch every run) without reopening the shared-tree
  mutation risk worktree isolation was built to close.
- **Sibling-conflict signal:** `clusterSiblingsAdjacently` and
  `_tryStartNextQueuedExecutions`'s skip-ahead scan generalize from
  direct `parentId` equality to "shares any ancestor," resolving
  `parallel-work.md`'s own previously-unraised open question about
  whether the signal should broaden beyond direct siblings. No depth cap
  is needed as a separate mechanism — the existing three-level hierarchy
  bounds it implicitly.

## Open questions

- Exact cache location/lifecycle (per-project, shared across all
  worktrees of that project; invalidation policy when the main
  checkout's own dependency lockfile changes) — left for `/propose`'s
  design.md.
- Whether hardlink vs. plain copy is chosen per-platform (hardlinks
  aren't uniformly available/reliable across Windows/macOS/Linux
  filesystems) — left for `/propose`.
- Disk-bloat accounting once dependency caching and N-concurrent
  worktrees (from `parallel-work.md`) coexist — the cache itself is
  meant to reduce bloat versus fetching per-worktree, but total disk
  footprint across a cache directory plus N worktrees hasn't been sized.
- Whether the generalized ancestor-based sibling signal needs its own
  Board visual treatment beyond the existing `parentId`-based adjacent
  clustering from `parallel-work.md`, now that "sibling" can mean
  same-Epic cousins rather than only same-Story siblings — not raised
  this session.

## Architectural implications

- Extends (doesn't replace) `coding-execution-reliability-and-safety.md`'s
  worktree-isolation mechanism with a second, separate cache location —
  the worktree lifecycle gains a populate-from-cache step, distinct from
  worktree creation itself.
- `_tryStartNextQueuedExecutions`'s skip-ahead scan and
  `clusterSiblingsAdjacently`'s Board sort key both change their
  conflict-membership test from `a.parentId == b.parentId` to a
  shared-ancestor walk — a small algorithmic change, not a data-model
  change (still reuses `Ticket.parentId`, just chained instead of
  compared directly).
- No new persisted setting or `AutomationConfidence` consumer required
  for either half — both are mechanism-level fixes to existing,
  already-shipped behavior (worktree setup, Hybrid scheduling), not new
  user-facing decisions.