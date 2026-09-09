# propose

The planning stage of the SDD cycle (`explore → propose → apply →
verify → archive`). Architects a feature without writing any source
code — turns a raw idea, known gap, or open question ticket into a
concrete, reviewable plan.

What it does:

- Reads the source ticket (an idea, known gap, or open question) that
  this epic is resolving, and any spec tickets it relates to, so the
  plan is grounded in what the project actually does today, not just
  the raw idea's own wording.
- Decomposes the epic into child story tickets — each a coherent slice
  of the work, not yet broken down to individual files or functions.
- Writes the plan directly into the epic ticket's own description: what's
  being built, why, and what's explicitly out of scope. If the change
  touches user-facing UI, flags that a design pass is needed before
  implementation starts.
- Notes the technical shape where it matters — new or changed concepts,
  data flow, structural decisions — as part of that same description or
  a linked documentation page, not a separate artifact disconnected from
  the ticket it belongs to.

**Stops after decomposing and writing the plan, for human review.** Do
not chain straight into implementation — a proposal needs a person to
read it and either approve it, send it back for revision, or reject it
before any story ticket moves into active work.
