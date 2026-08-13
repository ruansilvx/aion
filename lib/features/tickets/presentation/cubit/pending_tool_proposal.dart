// presentation/cubit/pending_tool_proposal.dart — PendingToolProposal value type (presentation layer).

import 'package:equatable/equatable.dart';

/// A `branch_ticket`/`close_branch` tool call awaiting user confirmation,
/// held on `TicketDetailLoaded.pendingToolProposal` while
/// `TicketsCubit._awaitProposalConfirmation` keeps the underlying model
/// run paused (`AutomationConfidence.gated`). Rendered by
/// `_ToolProposalBanner`. Added for
/// `aion-arch/changes/mid-task-chat-branching`; see that change's
/// design.md §8.
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
