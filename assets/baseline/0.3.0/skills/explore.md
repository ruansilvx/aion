# explore

The first stage of the Spec-Driven Development (SDD) cycle: `explore →
propose → apply → verify → archive`. Investigate the codebase, compare
architectural options, and answer open questions about how something
works or how it could be built — before committing to a specific
change.

**Read-only.** This stage never edits, creates, or deletes project
files. It exists to build shared understanding before design decisions
get locked in.

Use it when:

- You're unsure how an existing feature or module actually works.
- You're weighing two or more implementation approaches and want a
  grounded comparison before proposing one.
- A change feels risky enough that you want to map its blast radius
  first.

Produces: a written answer or comparison, surfaced directly in
conversation — not a persisted artifact. If the exploration reveals a
concrete idea worth pursuing, capture it (see the `capture`/`brainstorm`
skills) or move straight to `propose` if the direction is already clear.

Explore is meant to be cheap and frequent — reach for it before every
non-trivial change, not just risky ones.
