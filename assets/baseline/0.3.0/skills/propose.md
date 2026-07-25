# propose

The planning stage of the SDD cycle (`explore → propose → apply →
verify → archive`). Architects a feature without writing any source
code — turns a rough idea or explored direction into a concrete,
reviewable plan.

Produces four artifacts for the change, typically under a
`changes/<change-name>/` folder:

- **`proposal.md`** — what's being built, why, and what's explicitly
  out of scope.
- **`design.md`** — the technical shape: new/changed types, functions,
  data flow, UI structure if applicable.
- **`spec.md`** — a delta specification: exactly which behaviors are
  ADDED, MODIFIED, or REMOVED relative to the project's current
  documented state.
- **`tasks.md`** — a strict, ordered checklist of files to create or
  edit, precise enough that implementation doesn't require re-deriving
  design decisions.

**Stops after generating these for human review.** Do not chain
straight into implementation — a proposal needs a person to read it and
either approve it, send it back for revision, or reject it before any
code gets written. If the plan touches user-facing UI, flag that a
design pass is needed before implementation starts.
