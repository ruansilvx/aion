// domain/entities/default_workflow_statuses.dart — seeded default WorkflowStatus list (domain layer).

import 'package:aion/features/tickets/domain/entities/workflow_status.dart';
import 'package:aion/features/tickets/domain/enums/workflow_status_role.dart';

/// The shared-base [WorkflowStatus] set seeded into a brand-new project's
/// `workflow_statuses` table (and backfilled once for every pre-existing
/// project on schema-15 upgrade — see
/// `WorkflowStatusDao.seedDefaultsIfEmpty`). Reproduces today's exact
/// hardcoded pre-configuration behavior: a project that never opens the
/// Workflow settings screen behaves exactly as Aion did before this change.
/// Fixed ids (rather than freshly-generated UUIDs) so every fresh install and
/// every upgraded pre-existing database seeds byte-identical rows. See
/// `AIO-549` §1.3.
const List<WorkflowStatus> defaultWorkflowStatuses = [
  WorkflowStatus(
    id: '9c3f9b0a-8e0e-4a7c-9d1e-000000000001',
    name: 'backlog',
    displayName: 'Backlog',
    sortOrder: 0,
  ),
  WorkflowStatus(
    id: '9c3f9b0a-8e0e-4a7c-9d1e-000000000002',
    name: 'todo',
    displayName: 'Todo',
    sortOrder: 1,
  ),
  WorkflowStatus(
    id: '9c3f9b0a-8e0e-4a7c-9d1e-000000000003',
    name: 'inProgress',
    displayName: 'In Progress',
    sortOrder: 2,
    role: WorkflowStatusRole.executionTrigger,
  ),
  WorkflowStatus(
    id: '9c3f9b0a-8e0e-4a7c-9d1e-000000000004',
    name: 'inReview',
    displayName: 'In Review',
    sortOrder: 3,
    role: WorkflowStatusRole.reviewReady,
  ),
  WorkflowStatus(
    id: '9c3f9b0a-8e0e-4a7c-9d1e-000000000005',
    name: 'done',
    displayName: 'Done',
    sortOrder: 4,
    role: WorkflowStatusRole.done,
  ),
  WorkflowStatus(
    id: '9c3f9b0a-8e0e-4a7c-9d1e-000000000006',
    name: 'cancelled',
    displayName: 'Cancelled',
    sortOrder: 5,
  ),
];
