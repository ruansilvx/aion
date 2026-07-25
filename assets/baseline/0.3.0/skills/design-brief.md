# design-brief

Bridges a written proposal and a visual design tool. Run after
`propose`, before doing any actual visual design work, for any change
that touches user-facing UI.

Reads the active change's `proposal.md` (and `design.md`/`tasks.md` if
already drafted) and the project's existing design system — color and
type tokens, spacing, component conventions — and generates a
ready-to-use prompt for a design session: what's being built, what
already exists to reuse, what new components need specifying, and what
format the output should come back in so it can be integrated
mechanically afterward.

The goal is to hand a design tool (or a person doing the design work)
everything it needs without them having to go spelunking through the
proposal and the existing codebase themselves — and to get output back
in a shape the next stage (`design-sync`) can actually validate and
wire in.
