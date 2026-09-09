# what-next (Aion project override)

Aion's own development still has a second, file-based mechanism
alongside its native ticket-driven one: `aion-arch` (a separate,
private companion repository, `aion-workspace/aion-arch/`) — frozen
from further routine use, but still exercised for real ad hoc
investigation/fix work found via `/explore`. This override preserves
that actual mechanics, distinct from the generic ticket-native
`what-next` guidance every other project gets.

Suggests the single most valuable next action, checking in order:

1. **An active `aion-arch` cycle** — a folder directly under
   `aion-arch/changes/` (not `archive/`) means a change is already
   mid-cycle. If it's on the current branch and not stale, continue its
   current stage. If stale, flag it and ask whether to continue/abandon/
   restructure.
2. **Known gaps and open questions, ticket-native** — `knownGap`/
   `openQuestion` tickets in Aion's own project, raised against
   already-shipped behavior.
3. **Priority-0 gaps recorded in `aion-arch/specs/*.md`** — a `## Known
   gaps` or `## Open questions` section the spec's own author left
   behind. Same weight as ticket-native gaps above; source of truth is
   whichever is more current for the area in question.
4. **Raw ideas** — either an `aion-arch/ideas/*.md` file with
   `status: raw`/`resolved`, or a raw `idea` ticket, not yet explored or
   promoted.
5. **Nothing concrete** — fall back to a fresh brainstorm/exploration
   session.

A quiet cycle or ticket is flagged as possibly stale rather than
silently resumed or ignored — that judgment call belongs to a person.
