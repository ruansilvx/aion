# what-next

Suggests the single most valuable next action when it isn't obvious
what to work on. A starting point for orientation, not a stage of the
SDD cycle itself.

Checks, roughly in priority order:

1. **Active epics and stories** — is a ticket already mid-cycle
   (`exploring`, `proposed`, `verifying`, or partway through a design
   gate)? If so, and it's had recent activity, continuing it is almost
   always higher-value than starting something new.
2. **Known gaps and open questions** — `knownGap`/`openQuestion` tickets
   raised against already-shipped work, still unresolved. A known gap
   points at `explore` next; an open question points at a decision to
   make first, since it's unresolved direction, not unbuilt code.
3. **Raw ideas** — captured but not yet explored or promoted into an
   epic.
4. **Nothing concrete** — if none of the above applies, falls back to
   suggesting a fresh exploration session to generate a direction.

A ticket that's gone quiet for a while (no recent activity, no recent
chat turns) is flagged as possibly stale rather than silently resumed
or silently ignored — that judgment call (continue, abandon, or
restructure) belongs to a person, not an automatic decision.
