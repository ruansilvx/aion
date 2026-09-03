---
ticketId: AIO-85
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
# 2.5. Edit `lib/features/tickets/data/services/ticket_document_search_service.dart`

— remove the private `_cosineSimilarity` method, call the new
shared `cosineSimilarity` from `embedding_similarity.dart` instead;
update the file's imports.