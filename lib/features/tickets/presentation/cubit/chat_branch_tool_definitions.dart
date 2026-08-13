// presentation/cubit/chat_branch_tool_definitions.dart — branch_ticket/close_branch AgentToolDefinitions (presentation layer).

import 'package:aion/core/contracts/agent_tool_definition.dart';

/// The `branch_ticket` app-defined tool: callable by the model on any
/// `chat` whose own parent isn't itself a `chat` (see
/// `ChatCubit._toolsFor`/`TicketsCubit._canBranch`), to split a blocking
/// sub-issue off into its own child `chat` ticket. Handled by
/// `TicketsCubit._handleBranchToolCall`. Added for
/// `aion-arch/changes/mid-task-chat-branching`; see that change's
/// design.md §6.
const branchTicketToolDefinition = AgentToolDefinition(
  name: 'branch_ticket',
  description:
      'Split a blocking sub-issue discovered mid-conversation into its own '
      'child chat ticket, so this conversation can keep moving on its own '
      'thread while the sub-issue is worked separately. Only call this for '
      'a genuinely blocking sub-issue that deserves its own thread — not '
      'for routine clarifying questions.',
  inputSchema: {
    'type': 'object',
    'properties': {
      'title': {
        'type': 'string',
        'description': 'A short title for the new child chat ticket.',
      },
      'description': {
        'type': 'string',
        'description':
            'One to three sentences explaining why this sub-issue needs '
            'its own thread.',
      },
    },
    'required': ['title'],
  },
);

/// The `close_branch` app-defined tool: the symmetric counterpart to
/// [branchTicketToolDefinition], callable by the model on a branch chat
/// (one whose parent *is* a `chat`) once it judges the sub-issue resolved,
/// to fold a summary of the resolution back into the parent chat's
/// transcript and close the branch. Handled by
/// `TicketsCubit._handleCloseBranchToolCall`. Added for
/// `aion-arch/changes/mid-task-chat-branching`; see that change's
/// design.md §6.
const closeBranchToolDefinition = AgentToolDefinition(
  name: 'close_branch',
  description:
      'Fold this branch chat\'s resolved sub-issue back into its parent '
      'chat, posting a summary of how it was resolved onto the parent\'s '
      'transcript and closing this branch. Only call this once the '
      'sub-issue this branch was created for is actually resolved.',
  inputSchema: {
    'type': 'object',
    'properties': {
      'summary': {
        'type': 'string',
        'description':
            'A short account of how the branch\'s sub-issue was resolved, '
            'for the parent chat to read.',
      },
    },
    'required': ['summary'],
  },
);
