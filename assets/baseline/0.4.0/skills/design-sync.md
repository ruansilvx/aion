# design-sync

Validates and integrates a design export pasted back into a change's
`design.md`. Run after a design session (see `design-brief`) and before
`apply` — the gate between "a design exists" and "a design is actually
safe and complete enough to build against."

What it checks:

- **Constraint compliance** — the design doesn't quietly depend on
  something the project's UI conventions forbid (e.g. a framework's
  default styled components when the project mandates hand-built,
  token-driven ones).
- **Token cross-reference** — every color/spacing/type value in the
  design either matches an existing design-system token or is flagged as
  a new one that needs adding before implementation.
- **Task annotation** — updates the change's `tasks.md` so each
  UI-creating task cites the exact design section that specifies it,
  so implementation doesn't have to guess which part of the design
  applies to which file.

Sets the change's design gate to approved or still-pending accordingly.
`apply` should refuse to proceed on UI tasks while the gate is pending.
