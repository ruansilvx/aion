# design-sync

Validates and integrates a design export pasted into a story's linked
design ticket. Run after a design session (see `design-brief`) and
before `apply` — the gate between "a design exists" and "a design is
actually safe and complete enough to build against."

What it checks:

- **Constraint compliance** — the design doesn't quietly depend on
  something the project's UI conventions forbid (e.g. a framework's
  default styled components when the project mandates hand-built,
  token-driven ones).
- **Token cross-reference** — every color/spacing/type value in the
  design either matches an existing design-system token or is flagged as
  a new one that needs adding before implementation.
- **Task annotation** — each UI-creating task ticket gets a reference to
  the exact design-ticket section that specifies it, so implementation
  doesn't have to guess which part of the design applies to which file.

Sets the story's design gate to approved or still-pending accordingly.
`apply` should refuse to proceed on UI task tickets while the gate is
pending.
