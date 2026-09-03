---
ticketId: AIO-83
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
# 2.3. Edit `lib/core/database/app_database.dart` — bump

`schemaVersion` to `10`, add the `if (from < 10)` migration block
(add both columns, backfill both sources to `'manual'` for
already-sized rows) per design.md §3.4. Update the class-level
dartdoc comment block that documents each schema version's changes
(the one referenced near "Version 9 adds...") with a "Version 10
adds..." line.