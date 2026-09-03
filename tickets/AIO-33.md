---
ticketId: AIO-33
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-17T00:00:00.000
updatedAt: 2026-07-18T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Hub and infrastructure to support multiple projects

we need a hub and infrastructure to support multiple projects

## Resolution (via /brainstorm storage model, 2026-07-17)

This idea was resolved together with the "Storage Model" foundational
decision in `project.md` — see
[[storage-model-per-project-scoping]] for the full session record
(questions asked, answers, open questions, architectural implications).

Conclusion: each project has its own fully isolated environment (drift
DB, git repo, skills, architecture conventions, model config). Aion
supplies a common baseline that projects start from and can tune away
from, distributed as **pinned + override** (each project pins a
baseline version; local overrides shadow/extend baseline pieces by
name; upgrades are explicit, never silent). The hub itself is a
**single running Aion instance** with a project switcher that swaps
active project context — not a separate instance per project.