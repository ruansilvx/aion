// presentation/widgets/resume_runs_prompt.dart — ResumeRunsPrompt banner (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:aion/features/tickets/presentation/widgets/banner_shell.dart';

/// A one-time-per-launch inline banner pinned to the top of the Board
/// view, listing coding-execution runs `TicketsCubit.restoreExecutionQueue`
/// found interrupted by an app restart under
/// `AutomationConfidence.gated`. Resume re-enqueues every surviving entry
/// (`TicketsCubit.resumePendingExecutions`); Dismiss falls back to
/// `AutomationConfidence.manual`'s behavior — clears the snapshot and
/// relies on the existing orphaned/stalled per-ticket retry banner
/// (`TicketsCubit.dismissPendingResumePrompt`). Rendered only while
/// `TicketsLoaded.pendingResumePrompt` is non-empty — vanishes on its own
/// once either action clears it. Added for
/// `aion-arch/changes/parallel-work`; see that change's design.md §3.
class ResumeRunsPrompt extends StatelessWidget {
  /// Creates a [ResumeRunsPrompt] listing [tickets] — the interrupted
  /// runs awaiting a Resume/Dismiss decision.
  const ResumeRunsPrompt({super.key, required this.tickets});

  /// The interrupted Task/Bug tickets to list.
  final List<Ticket> tickets;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isDark = t.isDark;
    final cubit = context.read<TicketsCubit>();

    return BannerShell(
      fill: c.pendingTint(isDark),
      border: c.pendingTint(isDark),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BannerIconChip(
            fill: c.pendingIconTint(isDark),
            icon: PhosphorIcons.arrowClockwiseLight,
            iconColor: c.primary,
          ),
          const SizedBox(width: AionSpacing.sp12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.resumeRunsPromptTitle(tickets.length),
                  style: AionText.h2.copyWith(fontSize: 15, color: c.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.resumeRunsPromptBody,
                  style: AionText.bodySm.copyWith(
                    color: c.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                for (final ticket in tickets)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${ticket.ticketId} · ${ticket.title}',
                      style: AionText.bodySm.copyWith(color: c.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: AionSpacing.sp12),
                Row(
                  children: [
                    AppButton(
                      label: context.l10n.resumeRunsPromptResumeAction,
                      onPressed: cubit.resumePendingExecutions,
                    ),
                    const SizedBox(width: AionSpacing.sp8),
                    AppButton(
                      label: context.l10n.resumeRunsPromptDismissAction,
                      variant: AppButtonVariant.ghost,
                      onPressed: cubit.dismissPendingResumePrompt,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
