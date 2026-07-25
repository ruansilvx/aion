# what-next

Suggests the single most valuable next action when it isn't obvious
what to work on. A starting point for orientation, not a stage of the
SDD cycle itself.

Checks, roughly in priority order:

1. **Active cycles** — is there a change already in `propose`, `apply`,
   `verify`, or `archive`? If so, and it's not stale, continuing it is
   almost always higher-value than starting something new.
2. **Known gaps** — documented but unaddressed issues, half-finished
   features, or explicitly deferred follow-ups from past changes.
3. **Nothing concrete** — if neither of the above applies, falls back to
   suggesting a `brainstorm` session to generate a direction.

A cycle that's gone quiet for a while (no recent activity) is flagged as
possibly stale rather than silently resumed or silently ignored — that
judgment call (continue, abandon, or restructure) belongs to a person,
not an automatic decision.
