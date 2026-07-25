# apply

The implementation stage of the SDD cycle (`explore → propose → apply →
verify → archive`). Executes a change's `tasks.md` checklist exactly —
writes and modifies only the files it specifies, in the order it lists
them, marking each task off as it's completed.

Ground rules:

- No scope creep. If something outside `tasks.md` looks worth doing,
  note it rather than doing it — a separate change, not a silent
  addition to this one.
- No skipping ahead. Work through tasks in order; a later task may
  depend on an earlier one's output.
- Documentation is part of the task, not a follow-up. Every new public
  symbol and every touched file should be understandable on its own by
  the time the task is checked off.
- If a task turns out to be impossible or wrong as written (a false
  assumption in the design, a file that doesn't exist), stop and flag it
  rather than improvising a different implementation silently — the
  proposal/design may need a revision, not a workaround.

Before starting, check whether the change needed a design pass (visual
UI work) and whether that pass has actually happened — implementing
against a plan whose visual design isn't settled yet produces work that
has to be redone.

When every task is checked off, the change is ready for `verify`.
