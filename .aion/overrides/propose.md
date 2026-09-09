# propose (Aion project override)

Aion's own development still has a second, file-based mechanism
alongside its native ticket-driven one: `aion-arch` (a separate,
private companion repository, `aion-workspace/aion-arch/`) — frozen
from further routine use, but still exercised for real ad hoc
investigation/fix work found via `/explore`. This override preserves
that actual mechanics, distinct from the generic ticket-native
`propose` guidance every other project gets.

The planning stage of the OpenSpec cycle (`explore → propose → apply →
verify → archive`). Architects a feature without writing any source
code. Concretely:

- Checks whether the request matches an existing idea file under
  `aion-arch/ideas/`; if so, grounds the proposal in its conclusions
  and updates its `status`/`last_touched`.
- Creates a branch named after the change, and a new
  `aion-arch/changes/<name>/` directory.
- Generates four artifacts inside it: `proposal.md` (what's being built
  and why), `design.md` (technical architecture — BLoC states, widget
  tree), `specs/spec.md` (a delta spec: exactly what's ADDED/MODIFIED/
  REMOVED), and `tasks.md` (an ordered, file-level implementation
  checklist — every task touching a Dart file includes its
  documentation as part of that same task).
- Appends a `## Design gate` block to `proposal.md` — `PENDING` if the
  change touches any widget/screen/component, `NOT REQUIRED` otherwise.
- Commits the four artifacts in `aion-arch/` and pushes to `origin` on
  the change's branch.

**Stops after generating these for human review.** Do not chain
straight into `/apply` unless explicitly asked.
