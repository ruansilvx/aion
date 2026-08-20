// presentation/cubit/pending_tool_proposal.dart — PendingToolProposal value type (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// A `branch_ticket`/`close_branch`/`create_ticket`/`add_link` tool call
/// awaiting user confirmation, held on
/// `TicketDetailLoaded.pendingToolProposal` while
/// `TicketsCubit._awaitProposalConfirmation` keeps the underlying model
/// run paused (`AutomationConfidence.gated`). Rendered by
/// `_ToolProposalBanner`. Added for
/// `aion-arch/changes/mid-task-chat-branching`; see that change's
/// design.md §8. `CreateTicketProposal`/`AddLinkProposal` added for
/// `aion-arch/changes/ticket-crud-tool-calls`; see that change's design.md
/// §5.
sealed class PendingToolProposal extends Equatable {
  /// Creates a [PendingToolProposal].
  const PendingToolProposal();

  /// A pending `branch_ticket` call — see [BranchProposal].
  const factory PendingToolProposal.branch({
    required String title,
    String? description,
  }) = BranchProposal;

  /// A pending `close_branch` call — see [CloseBranchProposal].
  const factory PendingToolProposal.close({required String summary}) =
      CloseBranchProposal;

  /// A pending `create_ticket` call — see [CreateTicketProposal].
  const factory PendingToolProposal.createTicket({
    required String title,
    required TicketType type,
    String? description,
  }) = CreateTicketProposal;

  /// A pending `add_link` call — see [AddLinkProposal].
  const factory PendingToolProposal.addLink({
    required String targetTicketId,
    required String targetTicketTitle,
    required TicketLinkType linkType,
  }) = AddLinkProposal;
}

/// A pending `branch_ticket` call, proposing a new child chat titled
/// [title] (with an optional [description] of the AI's rationale).
class BranchProposal extends PendingToolProposal {
  /// Creates a [BranchProposal] for [title]/[description].
  const BranchProposal({required this.title, this.description});

  /// The proposed child chat ticket's title.
  final String title;

  /// The AI's optional 1–3 sentence rationale for why this sub-issue
  /// deserves its own thread.
  final String? description;

  @override
  List<Object?> get props => [title, description];
}

/// A pending `close_branch` call, proposing to fold [summary] — the AI's
/// account of how the branch was resolved — back into the parent chat.
class CloseBranchProposal extends PendingToolProposal {
  /// Creates a [CloseBranchProposal] for [summary].
  const CloseBranchProposal({required this.summary});

  /// The AI's account of how the branch's sub-issue was resolved.
  final String summary;

  @override
  List<Object?> get props => [summary];
}

/// A pending `create_ticket` call, proposing a new top-level ticket of
/// [type] titled [title] (with an optional [description]). Added for
/// `aion-arch/changes/ticket-crud-tool-calls`.
class CreateTicketProposal extends PendingToolProposal {
  /// Creates a [CreateTicketProposal] for [title]/[type]/[description].
  const CreateTicketProposal({
    required this.title,
    required this.type,
    this.description,
  });

  /// The proposed new ticket's title.
  final String title;

  /// The proposed new ticket's type — always `story`, `task`, or `bug`
  /// (`create_ticket` never proposes any other type).
  final TicketType type;

  /// The AI's optional 1–3 sentence rationale/body for the ticket.
  final String? description;

  @override
  List<Object?> get props => [title, type, description];
}

/// A pending `add_link` call, proposing to relate the current ticket to
/// the ticket identified by [targetTicketId] (titled [targetTicketTitle],
/// resolved once by the handler before this proposal is constructed) via
/// [linkType]. Added for `aion-arch/changes/ticket-crud-tool-calls`.
class AddLinkProposal extends PendingToolProposal {
  /// Creates an [AddLinkProposal] for [targetTicketId]/[targetTicketTitle]/
  /// [linkType].
  const AddLinkProposal({
    required this.targetTicketId,
    required this.targetTicketTitle,
    required this.linkType,
  });

  /// The target ticket's human-readable id (e.g. `"TASK-42"`).
  final String targetTicketId;

  /// The target ticket's title, resolved once when the call was validated
  /// so the banner never needs its own follow-up fetch.
  final String targetTicketTitle;

  /// How the current ticket would relate to the target.
  final TicketLinkType linkType;

  @override
  List<Object?> get props => [targetTicketId, targetTicketTitle, linkType];
}
