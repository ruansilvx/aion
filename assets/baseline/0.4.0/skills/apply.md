# apply

The implementation stage of the SDD cycle (`explore → propose → apply →
verify → archive`). Executes a story's task tickets exactly — makes
only the changes each task ticket describes, in dependency order,
marking each task ticket done as it's completed.

Ground rules:

- No scope creep. If something outside the current set of task tickets
  looks worth doing, note it rather than doing it — a new ticket, not a
  silent addition to this one.
- No skipping ahead. Work through tasks in order; a later task may
  depend on an earlier one's output.
- Documentation is part of the task, not a follow-up. Every new public
  symbol and every touched file should be understandable on its own by
  the time the task ticket is marked done.
- If a task ticket turns out to be impossible or wrong as written (a
  false assumption in the plan, something that doesn't exist), stop and
  flag it rather than improvising a different implementation silently —
  the story's own plan may need a revision, not a workaround.

Before starting, check whether the story needed a design pass (visual
UI work) and whether that pass has actually happened — implementing
against a plan whose visual design isn't settled yet produces work that
has to be redone.

When every task ticket is done, the story is ready for `verify`.
