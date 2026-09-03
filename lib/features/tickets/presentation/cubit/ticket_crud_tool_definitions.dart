// presentation/cubit/ticket_crud_tool_definitions.dart — create_ticket/add_link AgentToolDefinitions (presentation layer).

import 'package:aion/core/contracts/agent_tool_definition.dart';

/// The `create_ticket` app-defined tool: callable by the model on any chat
/// turn that already offers app-defined tools (coding execution, SDD-stage
/// chats, design-sync — see `TicketsCubit._toolsFor`), to spin off a new
/// top-level `story`/`task`/`bug` ticket for follow-up work discovered
/// mid-conversation. Never accepts a model-supplied parent — every ticket this
/// tool creates is top-level; relating it to the ticket under discussion is a
/// separate [addLinkToolDefinition] call. Handled by
/// `TicketsCubit._handleCreateTicketToolCall`. Added for `AIO-2108`; see that
/// change's design.md §2.
const createTicketToolDefinition = AgentToolDefinition(
  name: 'create_ticket',
  description:
      'Create a new top-level ticket for follow-up work discovered '
      'mid-conversation — e.g. an unrelated bug spotted while working on '
      'something else, or a new task worth tracking separately. The new '
      'ticket has no parent; call add_link afterward to relate it to the '
      'ticket you\'re currently working on, if relevant. The result '
      'always has an "accepted" field: true means the ticket was really '
      'created (its id is included) — false means it was declined '
      '(e.g. the user\'s automation setting requires manual approval) '
      'and nothing was created. Never tell the user a ticket was '
      'created unless accepted is true; on false, relay the "reason" '
      'to them honestly instead.',
  inputSchema: {
    'type': 'object',
    'properties': {
      'title': {'type': 'string', 'description': 'A short, clear title.'},
      'type': {
        'type': 'string',
        'enum': ['story', 'task', 'bug'],
        'description': 'The kind of ticket to create.',
      },
      'description': {
        'type': 'string',
        'description': 'Optional 1-3 sentence description.',
      },
    },
    'required': ['title', 'type'],
  },
);

/// The `add_link` app-defined tool: callable the same places as
/// [createTicketToolDefinition], to relate the ticket the current chat is
/// attached to (`chat.parentId`) to another ticket resolved by its
/// human-readable `ticketId` (e.g. `"TASK-42"`, never the internal uuid).
/// Doubles as duplicate-flagging — `linkType: 'duplicates'` is an ordinary
/// call, not a separate tool. Handled by
/// `TicketsCubit._handleAddLinkToolCall`. Added for `AIO-2108`; see that
/// change's design.md §2.
const addLinkToolDefinition = AgentToolDefinition(
  name: 'add_link',
  description:
      'Relate the ticket you\'re currently working on to another ticket by '
      'its ticket id (e.g. "TASK-42") — mark it as blocking, blocked by, '
      'related to, or a duplicate of the target. The result always has '
      'an "accepted" field: true means the link was really created — '
      'false means it was declined (e.g. the user\'s automation setting '
      'requires manual approval) and nothing changed. Never tell the '
      'user the link was created unless accepted is true; on false, '
      'relay the "reason" to them honestly instead.',
  inputSchema: {
    'type': 'object',
    'properties': {
      'targetTicketId': {
        'type': 'string',
        'description': 'The other ticket\'s human-readable id, e.g. "TASK-42".',
      },
      'linkType': {
        'type': 'string',
        'enum': ['blocks', 'blockedBy', 'relatesTo', 'duplicates'],
        'description': 'How the current ticket relates to the target.',
      },
    },
    'required': ['targetTicketId', 'linkType'],
  },
);
