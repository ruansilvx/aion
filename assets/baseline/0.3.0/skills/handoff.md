# handoff

Writes a summary of the current session so a fresh session — with no
memory of what just happened — can pick up the work without losing
context. Not tied to any single SDD stage; useful whenever a session is
ending mid-task.

Use it when:

- Context is getting long and a fresh session will reason more
  reliably than a heavily-compacted one.
- You're ending a session for the day (or indefinitely) with work still
  in flight.
- Someone else — a person or another session — needs to continue what
  you started.

A good handoff states: what change or task is active and where its
artifacts live, what's been done so far, what's left, any decisions
made along the way that aren't obvious from the code/artifacts alone,
and any blockers or open questions the next session should know about
before continuing. The goal is that the next session can start working
immediately, not spend its first several turns reconstructing state.
