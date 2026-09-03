---
ticketId: AIO-87
type: task
status: done
priority: none
parentId: 730b86dd-9df8-495f-a8a8-4e9172a250a9
estimate: null
timeSpent: null
createdAt: 2026-09-02T21:17:20.135559
updatedAt: 2026-09-02T21:17:20.135559
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# 2.7. Grep the rest of the app repo for any other place that

constructs a `Ticket(...)` naming every field explicitly (test
fixtures/mocks aside — see §5) and add the same two pass-through
lines wherever a real (non-test) production code path does this.