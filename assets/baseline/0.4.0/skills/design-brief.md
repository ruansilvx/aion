# design-brief

Bridges a story ticket and a visual design tool. Run after `propose`,
before doing any actual visual design work, for any story that touches
user-facing UI.

Reads the story ticket's own description (and its task tickets, if
already decomposed) and the project's existing design system — color
and type tokens, spacing, component conventions — and generates a
ready-to-use prompt for a design session: what's being built, what
already exists to reuse, what new components need specifying, and what
format the output should come back in so it can be integrated
mechanically afterward.

The design export itself lands on a linked design ticket (a
documentation-style ticket connected to the story), not back into the
story's own description — keeping "what's being built" and "the actual
design artifact" as separate, linkable records.

The goal is to hand a design tool (or a person doing the design work)
everything it needs without them having to go spelunking through the
story and the existing codebase themselves — and to get output back in
a shape the next stage (`design-sync`) can actually validate and wire
in.
