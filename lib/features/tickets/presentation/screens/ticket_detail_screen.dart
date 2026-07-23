// presentation/screens/ticket_detail_screen.dart — Ticket detail screen and comment widgets (presentation layer).

import 'dart:async';

import 'package:flutter/material.dart'
    show Material, MaterialType, TextField, InputDecoration;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:intl/intl.dart' show DateFormat;

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/data/services/active_ticket_view_registry.dart';
import 'package:aion/features/tickets/data/services/ticket_repair_service.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';
import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/ticket_complexity.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sync_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_link_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/chat_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/chat_state.dart';
import 'package:aion/features/tickets/presentation/cubit/comments_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/comments_state.dart';
import 'package:aion/features/tickets/presentation/cubit/ticket_repair_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_state.dart';
import 'package:aion/features/tickets/presentation/screens/tickets_board_view.dart';
import 'package:aion/features/tickets/presentation/screens/tickets_list_screen.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_link_picker.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_needs_repair_banner.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_overflow_menu.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_parent_picker.dart';

/// The `/tickets/:id` route: ticket meta (priority, complexity, title,
/// type, status, description, timestamps), a comment thread, and a
/// pinned comment composer. [TicketsCubit] is read from the root-level
/// provider; [CommentsCubit]/[ChatCubit] are provided per-route by
/// [appRouter](../../../../core/routing/app_router.dart) since they're
/// screen-scoped — `chat`-type tickets render their thread through
/// [ChatCubit] (a live conversation, see `chat_cubit.dart`) instead of
/// [CommentsCubit]. `epic`/`story` tickets also render an SDD-stage
/// section (see `_SddStageSection`) below the meta row. For `resource`
/// tickets, also renders two Documentation-section sections — Linked
/// Tickets and Backlinks — populated via
/// [TicketsCubit.loadDocumentRelations]. `page` tickets no longer render
/// here at all: since `page-content-markdown-editor`, a loaded `page`
/// ticket immediately redirects to `PageDetailScreen` via
/// `/workspace/pages/:id` (see the `TicketDetailLoaded` branch below) —
/// this screen now only ever renders `resource`/work-item/`chat` tickets.
class TicketDetailScreen extends StatefulWidget {
  /// Creates a [TicketDetailScreen] for the ticket with internal id [ticketId].
  const TicketDetailScreen({super.key, required this.ticketId});

  /// Internal UUID of the ticket to display.
  final String ticketId;

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  final _commentController = TextEditingController();

  /// The human-readable `ticketId` this screen registered as "active"
  /// with [ActiveTicketViewRegistry], once its [TicketDetailLoaded]
  /// state arrives (unknown before then). `null` on mobile/web, where
  /// [ActiveTicketViewRegistry] isn't provided at all (see
  /// `WorkspaceShell`) — reads are guarded with [_tryReadRegistry]
  /// rather than assuming desktop.
  String? _registeredTicketId;

  /// The internal ticket id [loadDocumentRelations] was last triggered
  /// for — guards against re-triggering on every re-emitted
  /// [TicketDetailLoaded] (that method itself re-emits
  /// [TicketDetailLoaded] once it resolves, which would otherwise loop).
  String? _relationsLoadedForId;

  /// The most recently loaded ticket, updated by the top-level
  /// [BlocListener]'s [TicketDetailLoaded] branch — used by
  /// [_sendComment] to decide whether to post through [ChatCubit] or
  /// [CommentsCubit], since the composer row sits outside the ticket
  /// [BlocBuilder]'s subtree.
  Ticket? _currentTicket;

  /// The persisted SDD-stage-triggering [AutomationConfidence], loaded
  /// once per screen instance (no polling) — see
  /// `aion-arch/changes/sdd-ticket-execution/design.md`'s
  /// "Precondition check on ticket-detail load" section.
  AutomationConfidence? _automationConfidence;

  /// `'<ticketId>:<sddStage>'` key of the last ticket+stage this screen
  /// already auto-advanced, so a rebuild doesn't re-trigger
  /// [TicketsCubit.advanceSddStage] repeatedly while
  /// [_automationConfidence] is [AutomationConfidence.auto] and the
  /// precondition remains (momentarily) satisfied.
  String? _autoAdvancedKey;

  /// Whether a [TicketsCubit.retryDesignSync] call is currently in
  /// flight — drives `_RetryValidationButton`'s disabled/spinning state
  /// (design.md §4.3) so a second tap can't fire a concurrent retry
  /// while the first is still running. Added for
  /// `aion-arch/changes/sdd-design-gate`.
  bool _retryingDesignSync = false;

  /// Calls [TicketsCubit.retryDesignSync], toggling [_retryingDesignSync]
  /// around the call so `_RetryValidationButton` can show its in-flight
  /// state and ignore further taps until this one resolves.
  Future<void> _retryDesignSync(Ticket designSyncChat) async {
    if (_retryingDesignSync) return;
    setState(() => _retryingDesignSync = true);
    try {
      await context.read<TicketsCubit>().retryDesignSync(designSyncChat);
    } finally {
      if (mounted) setState(() => _retryingDesignSync = false);
    }
  }

  @override
  void initState() {
    super.initState();
    context.read<TicketsCubit>().getTicketById(widget.ticketId);
    context.read<CommentsCubit>().loadComments(widget.ticketId);
    context.read<ChatCubit>().loadMessages(widget.ticketId);
    unawaited(
      context
          .read<AutomationSettingsRepository>()
          .getConfidence(AutomationContext.sddStage)
          .then((confidence) {
            if (mounted) setState(() => _automationConfidence = confidence);
          }),
    );
  }

  /// Calls [TicketsCubit.advanceSddStage] once for [ticket]'s current
  /// stage when [_automationConfidence] is [AutomationConfidence.auto]
  /// and [canAdvance] is `true`, guarded by [_autoAdvancedKey] so a
  /// rebuild before the resulting state change lands doesn't fire it
  /// again for the same ticket+stage.
  void _maybeAutoAdvanceSddStage(Ticket ticket, bool canAdvance) {
    if (_automationConfidence != AutomationConfidence.auto || !canAdvance) {
      return;
    }
    final key = '${ticket.id}:${ticket.sddStage?.name}';
    if (_autoAdvancedKey == key) return;
    _autoAdvancedKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<TicketsCubit>().advanceSddStage(ticket));
    });
  }

  /// Calls [TicketsCubit.advanceSddStage] for an explicit gated/manual
  /// "Advance" tap, then navigates to the spawned chat ticket once it and
  /// its first AI reply are ready — an intentional user action, unlike
  /// [_maybeAutoAdvanceSddStage]'s passive auto-advance, which never
  /// yanks the user off the screen they're already viewing.
  Future<void> _advanceSddStage(Ticket ticket) async {
    final chatId = await context.read<TicketsCubit>().advanceSddStage(ticket);
    if (chatId != null && mounted) {
      context.go('/workspace/tickets/$chatId');
    }
  }

  @override
  void dispose() {
    final registeredId = _registeredTicketId;
    if (registeredId != null) {
      final registry = _tryReadRegistry(context);
      if (registry?.activeTicketId.value == registeredId) {
        registry!.activeTicketId.value = null;
      }
    }
    _commentController.dispose();
    super.dispose();
  }

  /// [ActiveTicketViewRegistry] is only provided on desktop with a
  /// resolved project directory (see `WorkspaceShell`) — `null` on
  /// mobile/web rather than a thrown `ProviderNotFoundException`.
  ActiveTicketViewRegistry? _tryReadRegistry(BuildContext context) {
    try {
      return context.read<ActiveTicketViewRegistry>();
    } catch (_) {
      return null;
    }
  }

  void _registerActiveTicket(String ticketId) {
    if (_registeredTicketId == ticketId) return;
    final registry = _tryReadRegistry(context);
    if (registry == null) return;
    registry.activeTicketId.value = ticketId;
    _registeredTicketId = ticketId;
  }

  /// Whether [ticket] should show the sync badge/repair banner: a
  /// `resource` type (the only type still rendered by this screen — see
  /// the class doc comment), **and** sync tracking is actually active
  /// (desktop with a resolved project directory — [ActiveTicketViewRegistry]
  /// presence is used as that signal, rather than assuming desktop).
  /// Without the second check, a `resource` ticket on mobile/web would
  /// show a "SYNCED" badge implying a sync mechanism that doesn't exist
  /// there at all.
  bool _isSyncable(Ticket ticket) {
    if (ticket.type != TicketType.resource) {
      return false;
    }
    return _tryReadRegistry(context) != null;
  }

  /// Posts [_commentController]'s text via [ChatCubit.sendMessage] when
  /// [_currentTicket] is a `chat` ticket, or [CommentsCubit.addComment]
  /// otherwise. The model is resolved per-phase by
  /// `ChatCubit.sendMessage` itself; see `providers.md`.
  void _sendComment() {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;
    if (_currentTicket?.type == TicketType.chat) {
      context.read<ChatCubit>().sendMessage(
        chatTicketId: widget.ticketId,
        content: content,
      );
    } else {
      context.read<CommentsCubit>().addComment(
        ticketId: widget.ticketId,
        content: content,
      );
    }
    _commentController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return BlocListener<TicketsCubit, TicketsState>(
      listener: (context, state) {
        if (state is TicketTrashed) {
          context.go('/workspace/tickets');
        } else if (state is TicketsError &&
            state.reason == TicketsErrorReason.invalidParent) {
          AppToast.show(context, context.l10n.ticketInvalidParentError);
        } else if (state is TicketsError &&
            state.reason == TicketsErrorReason.codingExecutionBlocked) {
          AppToast.show(
            context,
            context.l10n.ticketCodingExecutionBlockedError,
          );
        } else if (state is TicketsError &&
            state.reason ==
                TicketsErrorReason.executionBudgetOverageDetected) {
          AppToast.show(
            context,
            context.l10n.executionBudgetOverageDetectedToast,
          );
        } else if (state is TicketDetailLoaded) {
          final ticket = state.ticket;
          if (ticket.type == TicketType.page) {
            // `page` tickets moved to their own module in
            // page-content-markdown-editor — bounce a stale
            // `/workspace/tickets/:id` link to the new route instead of
            // rendering the (no-longer-applicable) page UI here.
            context.go(ticketDetailRoute(ticket));
            return;
          }
          _currentTicket = ticket;
          _registerActiveTicket(ticket.ticketId);
          if (ticket.type == TicketType.resource &&
              _relationsLoadedForId != ticket.id) {
            _relationsLoadedForId = ticket.id;
            context.read<TicketsCubit>().loadDocumentRelations(ticket.id);
          }
        }
      },
      child: ColoredBox(
        color: c.background,
        child: Column(
          children: [
            BlocBuilder<TicketsCubit, TicketsState>(
              builder: (context, state) {
                final title = state is TicketDetailLoaded
                    ? state.ticket.ticketId
                    : '…';
                return AppHeader(
                  title: title,
                  showBack: true,
                  onBack: () => context.go('/workspace/tickets'),
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                  trailing: state is TicketDetailLoaded
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isSyncable(state.ticket)) ...[
                              SyncStatusBadge(status: state.ticket.syncStatus),
                              const SizedBox(width: 12),
                            ],
                            TicketOverflowMenu(ticket: state.ticket),
                          ],
                        )
                      : PhosphorIcon(
                          PhosphorIcons.dotsThreeLight,
                          size: 20,
                          color: c.textSecondary,
                        ),
                );
              },
            ),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: ContentMaxWidth(
                        variant: ContentWidthVariant.reading,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                16,
                                20,
                                16,
                              ),
                              child: BlocBuilder<TicketsCubit, TicketsState>(
                                builder: (context, state) {
                                  return switch (state) {
                                    TicketsLoading() => const Center(
                                      child: AppSpinner(),
                                    ),
                                    TicketsError(
                                      :final message,
                                      :final reason,
                                    ) =>
                                      Text(
                                        reason != null
                                            ? ticketsErrorMessage(
                                                context,
                                                reason,
                                              )
                                            : message,
                                        style: AionText.body.copyWith(
                                          color: c.danger,
                                        ),
                                      ),
                                    TicketDetailLoaded(
                                      :final ticket,
                                      :final canAdvanceSddStage,
                                      :final sddStageBlockReason,
                                      :final needsDesignReview,
                                      :final linkedDesignPage,
                                      :final isExecuting,
                                      :final executionQueuePosition,
                                      :final executionAwaitingReview,
                                    ) =>
                                      Semantics(
                                        header: true,
                                        child: Builder(
                                          builder: (context) {
                                            if (ticket.type ==
                                                    TicketType.epic ||
                                                ticket.type ==
                                                    TicketType.story) {
                                              _maybeAutoAdvanceSddStage(
                                                ticket,
                                                canAdvanceSddStage,
                                              );
                                            }
                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (_isSyncable(ticket) &&
                                                    ticket.syncStatus ==
                                                        TicketSyncStatus
                                                            .needsRepair)
                                                  _RepairBanner(
                                                    ticket: ticket,
                                                    onRepaired: () => context
                                                        .read<TicketsCubit>()
                                                        .getTicketById(
                                                          widget.ticketId,
                                                        ),
                                                  ),
                                                SelectionMenu<TicketPriority>(
                                                  // PriorityBadge renders SizedBox.shrink() for
                                                  // TicketPriority.none, which would make the trigger
                                                  // untappable (zero hit-test area) — fall back to a
                                                  // visible placeholder so priority can still be set
                                                  // for the first time from this screen.
                                                  trigger:
                                                      ticket.priority ==
                                                          TicketPriority.none
                                                      ? Text(
                                                          context
                                                              .l10n
                                                              .ticketDetailAddPriority,
                                                          style: AionText.label
                                                              .copyWith(
                                                                color:
                                                                    c.textMuted,
                                                              ),
                                                        )
                                                      : PriorityBadge(
                                                          priority:
                                                              ticket.priority,
                                                          isRow: false,
                                                        ),
                                                  items: TicketPriority.values,
                                                  itemLabel: (p) =>
                                                      ticketPriorityLabel(
                                                        context,
                                                        p,
                                                      ),
                                                  currentValue: ticket.priority,
                                                  onSelected: (p) => context
                                                      .read<TicketsCubit>()
                                                      .updateTicket(
                                                        ticket.copyWith(
                                                          priority: p,
                                                        ),
                                                      ),
                                                  semanticsLabel: context
                                                      .l10n
                                                      .ticketDetailChangePriority,
                                                ),
                                                const SizedBox(
                                                  height: AionSpacing.sp8,
                                                ),
                                                SelectionMenu<
                                                  TicketComplexity?
                                                >(
                                                  trigger:
                                                      ticket.complexity == null
                                                      ? Text(
                                                          context
                                                              .l10n
                                                              .ticketDetailAddComplexity,
                                                          style: AionText.label
                                                              .copyWith(
                                                                color:
                                                                    c.textMuted,
                                                              ),
                                                        )
                                                      : Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            ComplexityMeter(
                                                              complexity: ticket
                                                                  .complexity,
                                                            ),
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
                                                            Text(
                                                              ticketComplexityLabel(
                                                                context,
                                                                ticket
                                                                    .complexity!,
                                                              ),
                                                              style: AionText
                                                                  .label
                                                                  .copyWith(
                                                                    color: c
                                                                        .textSecondary,
                                                                  ),
                                                            ),
                                                          ],
                                                        ),
                                                  items: const [
                                                    null,
                                                    ...TicketComplexity.values,
                                                  ],
                                                  itemLabel: (v) => v == null
                                                      ? context
                                                            .l10n
                                                            .commonNotSet
                                                      : ticketComplexityLabel(
                                                          context,
                                                          v,
                                                        ),
                                                  currentValue:
                                                      ticket.complexity,
                                                  onSelected: (v) => context
                                                      .read<TicketsCubit>()
                                                      .updateTicket(
                                                        ticket.copyWith(
                                                          complexity: () => v,
                                                        ),
                                                      ),
                                                  itemBuilder:
                                                      (context, c, item) =>
                                                          ComplexityMenuRow(
                                                            item: item,
                                                          ),
                                                  semanticsLabel: context
                                                      .l10n
                                                      .ticketDetailChangeComplexity,
                                                ),
                                                const SizedBox(
                                                  height: AionSpacing.sp8,
                                                ),
                                                InlineEditableField<String>(
                                                  displayText: ticket.title,
                                                  editText: ticket.title,
                                                  maxLines: 1,
                                                  textStyle: AionText.h2
                                                      .copyWith(
                                                        color: c.textPrimary,
                                                      ),
                                                  semanticsLabel: context
                                                      .l10n
                                                      .ticketDetailEditTitle,
                                                  parser: (raw) {
                                                    final trimmed = raw.trim();
                                                    if (trimmed.isEmpty) {
                                                      throw FormatException(
                                                        context
                                                            .l10n
                                                            .ticketDetailTitleEmptyError,
                                                      );
                                                    }
                                                    return trimmed;
                                                  },
                                                  onCommit: (v) => context
                                                      .read<TicketsCubit>()
                                                      .updateTicket(
                                                        ticket.copyWith(
                                                          title: v,
                                                        ),
                                                      ),
                                                ),
                                                const SizedBox(
                                                  height: AionSpacing.sp12,
                                                ),
                                                Row(
                                                  children: [
                                                    SelectionMenu<TicketType>(
                                                      trigger: TypeChip(
                                                        type: ticket.type,
                                                        isRow: false,
                                                      ),
                                                      items: TicketType.values,
                                                      itemLabel: (ty) =>
                                                          ticketTypeLabel(
                                                            context,
                                                            ty,
                                                          ),
                                                      currentValue: ticket.type,
                                                      onSelected: (ty) =>
                                                          context
                                                              .read<
                                                                TicketsCubit
                                                              >()
                                                              .updateTicket(
                                                                ticket.copyWith(
                                                                  type: ty,
                                                                ),
                                                              ),
                                                      semanticsLabel: context
                                                          .l10n
                                                          .ticketDetailChangeType,
                                                    ),
                                                    const SizedBox(
                                                      width: AionSpacing.sp8,
                                                    ),
                                                    SelectionMenu<TicketStatus>(
                                                      trigger: StatusIndicator(
                                                        status: ticket.status,
                                                      ),
                                                      items:
                                                          TicketStatus.values,
                                                      itemLabel: (s) =>
                                                          ticketStatusLabel(
                                                            context,
                                                            s,
                                                          ),
                                                      currentValue:
                                                          ticket.status,
                                                      onSelected: (s) => context
                                                          .read<TicketsCubit>()
                                                          .changeTicketStatus(
                                                            ticket,
                                                            s,
                                                          ),
                                                      semanticsLabel: context
                                                          .l10n
                                                          .ticketDetailChangeStatus,
                                                    ),
                                                  ],
                                                ),
                                                if (ticket.type !=
                                                    TicketType.epic) ...[
                                                  const SizedBox(
                                                    height: AionSpacing.sp8,
                                                  ),
                                                  TicketParentPicker(
                                                    ticketType: ticket.type,
                                                    currentParentId:
                                                        ticket.parentId,
                                                    candidatesLoader: () => context
                                                        .read<TicketsCubit>()
                                                        .getValidParentCandidates(
                                                          ticket,
                                                        ),
                                                    onParentSelected:
                                                        (parentId) => context
                                                            .read<
                                                              TicketsCubit
                                                            >()
                                                            .updateTicketParent(
                                                              ticket,
                                                              parentId,
                                                            ),
                                                  ),
                                                ],
                                                const SizedBox(
                                                  height: AionSpacing.sp12,
                                                ),
                                                Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          context
                                                              .l10n
                                                              .ticketDetailEstimateCaption,
                                                          style: AionText
                                                              .caption
                                                              .copyWith(
                                                                color:
                                                                    c.textMuted,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height:
                                                              AionSpacing.sp4,
                                                        ),
                                                        InlineEditableField<
                                                          int?
                                                        >(
                                                          displayText:
                                                              formatDurationMinutes(
                                                                ticket.estimate,
                                                                placeholder: '',
                                                              ),
                                                          editText:
                                                              formatDurationMinutes(
                                                                ticket.estimate,
                                                                placeholder: '',
                                                              ),
                                                          placeholder: context
                                                              .l10n
                                                              .ticketDetailEstimatePlaceholder,
                                                          textStyle: AionText
                                                              .bodySm
                                                              .copyWith(
                                                                color: c
                                                                    .textPrimary,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                          semanticsLabel: context
                                                              .l10n
                                                              .ticketDetailEditEstimate,
                                                          parser: (raw) {
                                                            try {
                                                              return parseDurationMinutes(
                                                                raw,
                                                              );
                                                            } on FormatException {
                                                              throw FormatException(
                                                                context.l10n
                                                                    .durationInvalidFormat(
                                                                      raw,
                                                                    ),
                                                              );
                                                            }
                                                          },
                                                          onCommit: (v) => context
                                                              .read<
                                                                TicketsCubit
                                                              >()
                                                              .updateTicket(
                                                                ticket.copyWith(
                                                                  estimate:
                                                                      () => v,
                                                                ),
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(
                                                      width: AionSpacing.sp24,
                                                    ),
                                                    Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          context
                                                              .l10n
                                                              .ticketDetailTimeSpentCaption,
                                                          style: AionText
                                                              .caption
                                                              .copyWith(
                                                                color:
                                                                    c.textMuted,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height:
                                                              AionSpacing.sp4,
                                                        ),
                                                        InlineEditableField<
                                                          int?
                                                        >(
                                                          displayText:
                                                              formatDurationMinutes(
                                                                ticket
                                                                    .timeSpent,
                                                                placeholder: '',
                                                              ),
                                                          editText:
                                                              formatDurationMinutes(
                                                                ticket
                                                                    .timeSpent,
                                                                placeholder: '',
                                                              ),
                                                          placeholder: context
                                                              .l10n
                                                              .ticketDetailTimeSpentPlaceholder,
                                                          textStyle: AionText
                                                              .bodySm
                                                              .copyWith(
                                                                color: c
                                                                    .textPrimary,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                          semanticsLabel: context
                                                              .l10n
                                                              .ticketDetailEditTimeSpent,
                                                          parser: (raw) {
                                                            try {
                                                              return parseDurationMinutes(
                                                                raw,
                                                              );
                                                            } on FormatException {
                                                              throw FormatException(
                                                                context.l10n
                                                                    .durationInvalidFormat(
                                                                      raw,
                                                                    ),
                                                              );
                                                            }
                                                          },
                                                          onCommit: (v) => context
                                                              .read<
                                                                TicketsCubit
                                                              >()
                                                              .updateTicket(
                                                                ticket.copyWith(
                                                                  timeSpent:
                                                                      () => v,
                                                                ),
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                                if (needsDesignReview ==
                                                        true &&
                                                    linkedDesignPage !=
                                                        null) ...[
                                                  const SizedBox(height: 11),
                                                  _LinkedDesignPageChip(
                                                    page: linkedDesignPage,
                                                    onTap: () => context.go(
                                                      ticketDetailRoute(
                                                        linkedDesignPage,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                                const SizedBox(
                                                  height: AionSpacing.sp16,
                                                ),
                                                Container(
                                                  color: c.border,
                                                  height: 1,
                                                ),
                                                if (ticket.type ==
                                                        TicketType.epic ||
                                                    ticket.type ==
                                                        TicketType.story) ...[
                                                  const SizedBox(
                                                    height: AionSpacing.sp16,
                                                  ),
                                                  _SddStageSection(
                                                    ticket: ticket,
                                                    canAdvance:
                                                        canAdvanceSddStage,
                                                    blockReason:
                                                        sddStageBlockReason,
                                                    automationConfidence:
                                                        _automationConfidence,
                                                    needsDesignReview:
                                                        needsDesignReview,
                                                    onAdvance: () =>
                                                        _advanceSddStage(
                                                          ticket,
                                                        ),
                                                  ),
                                                  const SizedBox(
                                                    height: AionSpacing.sp16,
                                                  ),
                                                  Container(
                                                    color: c.border,
                                                    height: 1,
                                                  ),
                                                ] else if (ticket.type ==
                                                        TicketType.task &&
                                                    (isExecuting ||
                                                        executionQueuePosition !=
                                                            null ||
                                                        executionAwaitingReview)) ...[
                                                  const SizedBox(
                                                    height: AionSpacing.sp16,
                                                  ),
                                                  _CodingExecutionSection(
                                                    isExecuting: isExecuting,
                                                    executionQueuePosition:
                                                        executionQueuePosition,
                                                    executionAwaitingReview:
                                                        executionAwaitingReview,
                                                    onMarkReadyForReview: () =>
                                                        context
                                                            .read<
                                                              TicketsCubit
                                                            >()
                                                            .changeTicketStatus(
                                                              ticket,
                                                              TicketStatus
                                                                  .inReview,
                                                            ),
                                                  ),
                                                  const SizedBox(
                                                    height: AionSpacing.sp16,
                                                  ),
                                                  Container(
                                                    color: c.border,
                                                    height: 1,
                                                  ),
                                                ],
                                                const SizedBox(
                                                  height: AionSpacing.sp16,
                                                ),
                                                Text(
                                                  context
                                                      .l10n
                                                      .ticketDetailDescriptionCaption,
                                                  style: AionText.caption
                                                      .copyWith(
                                                        color: c.textMuted,
                                                      ),
                                                ),
                                                const SizedBox(
                                                  height: AionSpacing.sp8,
                                                ),
                                                InlineEditableField<String?>(
                                                  displayText:
                                                      ticket.description ?? '',
                                                  editText:
                                                      ticket.description ?? '',
                                                  maxLines: 6,
                                                  placeholder: context
                                                      .l10n
                                                      .ticketDetailDescriptionPlaceholder,
                                                  textStyle: AionText.body
                                                      .copyWith(
                                                        color: c.textSecondary,
                                                      ),
                                                  semanticsLabel: context
                                                      .l10n
                                                      .ticketDetailEditDescription,
                                                  parser: (raw) {
                                                    final trimmed = raw.trim();
                                                    return trimmed.isEmpty
                                                        ? null
                                                        : trimmed;
                                                  },
                                                  onCommit: (v) => context
                                                      .read<TicketsCubit>()
                                                      .updateTicket(
                                                        ticket.copyWith(
                                                          description: () => v,
                                                        ),
                                                      ),
                                                ),
                                                const SizedBox(
                                                  height: AionSpacing.sp8,
                                                ),
                                                Text(
                                                  context.l10n
                                                      .ticketDetailCreatedOn(
                                                        DateFormat.yMMMd()
                                                            .format(
                                                              ticket.createdAt,
                                                            ),
                                                      ),
                                                  style: AionText.time.copyWith(
                                                    color: c.textMuted,
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                    _ => const SizedBox.shrink(),
                                  };
                                },
                              ),
                            ),
                            BlocBuilder<TicketsCubit, TicketsState>(
                              builder: (context, state) {
                                if (state is! TicketDetailLoaded) {
                                  return const SizedBox.shrink();
                                }
                                final ticket = state.ticket;
                                // `page` tickets never reach this far — the
                                // `TicketDetailLoaded` listener above redirects
                                // them to `PageDetailScreen` first. Only
                                // `resource` renders Linked Tickets/Backlinks
                                // here (sub-pages moved to `PageDetailScreen`
                                // entirely, since only `page` tickets have
                                // sub-pages).
                                if (ticket.type != TicketType.resource) {
                                  return const SizedBox.shrink();
                                }
                                return Column(
                                  children: [
                                    LinkedTicketsSection(
                                      tickets: state.linkedTickets,
                                      onTap: (id) =>
                                          context.go('/workspace/tickets/$id'),
                                      trailing: TicketLinkPicker(
                                        candidatesLoader: () async {
                                          final all = await context
                                              .read<TicketsCubit>()
                                              .getAllTickets();
                                          final linkedIds = {
                                            for (final t in state.linkedTickets)
                                              t.id,
                                            for (final t in state.backlinks)
                                              t.id,
                                          };
                                          return all
                                              .where(
                                                (candidate) =>
                                                    candidate.id != ticket.id &&
                                                    !linkedIds.contains(
                                                      candidate.id,
                                                    ) &&
                                                    candidate.type !=
                                                        TicketType.page &&
                                                    candidate.type !=
                                                        TicketType.resource,
                                              )
                                              .toList();
                                        },
                                        onSelected: (selected) async {
                                          await context
                                              .read<TicketLinkRepository>()
                                              .createLink(
                                                sourceTicketId: ticket.id,
                                                targetTicketId: selected.id,
                                                linkType:
                                                    TicketLinkType.relatesTo,
                                              );
                                          if (!context.mounted) return;
                                          await context
                                              .read<TicketsCubit>()
                                              .loadDocumentRelations(ticket.id);
                                        },
                                      ),
                                    ),
                                    BacklinksSection(
                                      tickets: state.backlinks,
                                      onTap: (id) =>
                                          context.go('/workspace/tickets/$id'),
                                    ),
                                  ],
                                );
                              },
                            ),
                            Container(color: c.border, height: 1),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                              child: BlocBuilder<TicketsCubit, TicketsState>(
                                builder: (context, ticketsState) {
                                  if (ticketsState is! TicketDetailLoaded) {
                                    return const SizedBox.shrink();
                                  }
                                  if (ticketsState.ticket.type ==
                                      TicketType.chat) {
                                    return BlocBuilder<ChatCubit, ChatState>(
                                      builder: (context, state) {
                                        return switch (state) {
                                          ChatInitial() => const Center(
                                            child: AppSpinner(),
                                          ),
                                          ChatError(:final message) => Text(
                                            message,
                                            style: AionText.body.copyWith(
                                              color: c.danger,
                                            ),
                                          ),
                                          ChatLoaded(
                                            :final comments,
                                            :final streamingText,
                                          ) =>
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  context.l10n
                                                      .ticketDetailCommentsCount(
                                                        comments.length,
                                                      ),
                                                  style: AionText.caption
                                                      .copyWith(
                                                        color: c.textMuted,
                                                      ),
                                                ),
                                                const SizedBox(
                                                  height: AionSpacing.sp12,
                                                ),
                                                ListView.builder(
                                                  shrinkWrap: true,
                                                  physics:
                                                      const NeverScrollableScrollPhysics(),
                                                  itemCount: comments.length,
                                                  itemBuilder:
                                                      (context, index) =>
                                                          CommentTile(
                                                            comment:
                                                                comments[index],
                                                          ),
                                                ),
                                                if (streamingText != null)
                                                  _StreamingBubble(
                                                    text: streamingText,
                                                  ),
                                              ],
                                            ),
                                        };
                                      },
                                    );
                                  }
                                  return BlocBuilder<
                                    CommentsCubit,
                                    CommentsState
                                  >(
                                    builder: (context, state) {
                                      return switch (state) {
                                        CommentsLoading() => const Center(
                                          child: AppSpinner(),
                                        ),
                                        CommentsError(:final message) => Text(
                                          message,
                                          style: AionText.body.copyWith(
                                            color: c.danger,
                                          ),
                                        ),
                                        CommentsLoaded(:final comments) ||
                                        CommentAdding(:final comments) ||
                                        CommentAdded(:final comments) => Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              context.l10n
                                                  .ticketDetailCommentsCount(
                                                    comments.length,
                                                  ),
                                              style: AionText.caption.copyWith(
                                                color: c.textMuted,
                                              ),
                                            ),
                                            const SizedBox(
                                              height: AionSpacing.sp12,
                                            ),
                                            ListView.builder(
                                              shrinkWrap: true,
                                              physics:
                                                  const NeverScrollableScrollPhysics(),
                                              itemCount: comments.length,
                                              itemBuilder: (context, index) =>
                                                  CommentTile(
                                                    comment: comments[index],
                                                  ),
                                            ),
                                          ],
                                        ),
                                        _ => const SizedBox.shrink(),
                                      };
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(color: c.border, height: 1),
                  // "Retry validation" bar (design.md §4) — shown only for
                  // a "Design Sync — <Story>" chat whose most recent AI
                  // reply says PENDING. Added for
                  // aion-arch/changes/sdd-design-gate. AnimatedSize per
                  // design.md §4.1 — the bar grows/shrinks in rather than
                  // popping instantly as the gate flips.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 160),
                    alignment: Alignment.topCenter,
                    child: BlocBuilder<TicketsCubit, TicketsState>(
                      builder: (context, ticketsState) {
                        if (ticketsState is! TicketDetailLoaded) {
                          return const SizedBox.shrink();
                        }
                        final chatTicket = ticketsState.ticket;
                        if (chatTicket.type != TicketType.chat ||
                            !chatTicket.title.startsWith('Design Sync — ')) {
                          return const SizedBox.shrink();
                        }
                        return BlocBuilder<ChatCubit, ChatState>(
                          builder: (context, chatState) {
                            if (chatState is! ChatLoaded ||
                                chatState.comments.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            final mostRecent = chatState.comments.reduce(
                              (a, b) =>
                                  a.createdAt.isAfter(b.createdAt) ? a : b,
                            );
                            final isPending =
                                mostRecent.authorType ==
                                    CommentAuthorType.ai &&
                                mostRecent.content.contains(
                                  'DESIGN GATE: PENDING',
                                );
                            if (!isPending) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                10,
                                20,
                                0,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _RetryValidationButton(
                                  isLoading: _retryingDesignSync,
                                  onRetry: () =>
                                      _retryDesignSync(chatTicket),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  ColoredBox(
                    color: c.background,
                    child: ContentMaxWidth(
                      variant: ContentWidthVariant.reading,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: c.secondary,
                                shape: BoxShape.circle,
                              ),
                              child: SizedBox(
                                width: 34,
                                height: 34,
                                child: Center(
                                  child: Text(
                                    'U',
                                    style: AionText.key.copyWith(
                                      color: const Color(0xFFFFFFFF),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: c.surface,
                                  border: Border.all(color: c.border, width: 1),
                                  borderRadius: BorderRadius.all(
                                    AionRadius.pill,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 15,
                                    vertical: 10,
                                  ),
                                  child: Material(
                                    type: MaterialType.transparency,
                                    child: TextField(
                                      controller: _commentController,
                                      maxLines: 1,
                                      style: AionText.bodySm.copyWith(
                                        color: c.textPrimary,
                                        fontSize: 13,
                                      ),
                                      decoration: InputDecoration.collapsed(
                                        hintText: context
                                            .l10n
                                            .ticketDetailCommentHint,
                                        hintStyle: AionText.bodySm.copyWith(
                                          color: c.textMuted,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Semantics(
                              button: true,
                              label: context.l10n.ticketDetailSendComment,
                              child: GestureDetector(
                                onTap: _sendComment,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: c.primary,
                                    borderRadius: BorderRadius.circular(19),
                                    boxShadow: AionShadows.fab(c, t.isDark),
                                  ),
                                  child: SizedBox(
                                    width: 38,
                                    height: 38,
                                    child: Center(
                                      child: PhosphorIcon(
                                        PhosphorIcons.paperPlaneTiltLight,
                                        size: 17,
                                        color: const Color(
                                          0xFFFFFFFF,
                                        ), // white glyph
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [TicketRepairService] is only provided on desktop with a resolved
/// project directory — `null` on mobile/web or if not found, rather
/// than a thrown `ProviderNotFoundException`.
TicketRepairService? _tryReadRepairService(BuildContext context) {
  try {
    return context.read<TicketRepairService>();
  } catch (_) {
    return null;
  }
}

/// The active project's root directory, or `null` if unavailable
/// (mobile/web, or [ActiveProjectProvider] not found — e.g. a screen
/// test that doesn't wrap the full app-root provider tree).
String? _tryReadRootPath(BuildContext context) {
  try {
    return context.read<ActiveProjectProvider>().activeProject?.rootPath;
  } catch (_) {
    return null;
  }
}

/// The [TicketNeedsRepairBanner], wrapped in its own [TicketRepairCubit]
/// scoped to [ticket]'s `ticketId`/rootPath. Only rendered by
/// [_TicketDetailScreenState] when `_isSyncable` and `needsRepair` are
/// both true; still guards [_tryReadRepairService]/[_tryReadRootPath]
/// itself and renders nothing if either is unexpectedly null.
class _RepairBanner extends StatelessWidget {
  const _RepairBanner({required this.ticket, required this.onRepaired});

  /// The `resource` ticket the repair banner is scoped to — see
  /// [_TicketDetailScreenState]'s class doc comment.
  final Ticket ticket;

  /// Called once the repair completes, so the caller can reload the
  /// ticket.
  final VoidCallback onRepaired;

  @override
  Widget build(BuildContext context) {
    final service = _tryReadRepairService(context);
    final rootPath = _tryReadRootPath(context);
    if (service == null || rootPath == null) return const SizedBox.shrink();

    return BlocProvider<TicketRepairCubit>(
      key: ValueKey('repair-${ticket.ticketId}'),
      create: (_) => TicketRepairCubit(service, ticket.ticketId, rootPath),
      child: TicketNeedsRepairBanner(
        // Always `resource` here — see [_TicketDetailScreenState]'s class
        // doc comment.
        isPage: false,
        onRepaired: onRepaired,
      ),
    );
  }
}

/// A single comment bubble: avatar, author label, timestamp, and content.
/// Visually distinguishes [CommentAuthorType.ai] comments (primary-tinted
/// bubble, sparkle avatar, "AI" tag, `via <model>` footer) from
/// [CommentAuthorType.human] ones.
class CommentTile extends StatelessWidget {
  /// Creates a [CommentTile] rendering [comment].
  const CommentTile({super.key, required this.comment});

  /// The comment this tile represents.
  final TicketComment comment;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isAi = comment.authorType == CommentAuthorType.ai;
    final isSystem = comment.authorType == CommentAuthorType.system;

    return Semantics(
      label: '${comment.authorType.name} comment: ${comment.content}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: AionSpacing.sp16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(
              colors: c,
              isAi: isAi,
              isSystem: isSystem,
              isDark: t.isDark,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (isAi) ...[
                        Text(
                          context.l10n.ticketDetailAiAuthor,
                          style: AionText.cardTitle.copyWith(
                            fontSize: 12.5,
                            color: c.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: AionSpacing.sp4),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: c.primarySubtle,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Text(
                              context.l10n.ticketDetailAiTag,
                              style: AionText.prioritySm.copyWith(
                                color: c.primary,
                              ),
                            ),
                          ),
                        ),
                      ] else if (isSystem)
                        Text(
                          context.l10n.ticketDetailSystemAuthor,
                          style: AionText.cardTitle.copyWith(
                            fontSize: 12.5,
                            color: c.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      else
                        Text(
                          context.l10n.ticketDetailYouAuthor,
                          style: AionText.cardTitle.copyWith(
                            fontSize: 12.5,
                            color: c.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      const Spacer(),
                      Text(
                        _formatTime(comment.createdAt),
                        style: AionText.time.copyWith(color: c.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: AionSpacing.sp4),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(3),
                        topRight: AionRadius.lg,
                        bottomLeft: AionRadius.lg,
                        bottomRight: AionRadius.lg,
                      ),
                      color: isAi ? c.primarySubtle : c.surface,
                      border: Border.all(
                        color: isAi
                            ? c.primary.withValues(
                                alpha: t.isDark ? 0.42 : 0.28,
                              )
                            : c.border,
                        width: 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        comment.content,
                        style: AionText.bodySm.copyWith(
                          color: isSystem ? c.textSecondary : c.textPrimary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                  if (isAi && comment.aiModel != null) ...[
                    const SizedBox(height: AionSpacing.sp4),
                    Text(
                      context.l10n.ticketDetailViaModel(comment.aiModel!),
                      style: AionText.time.copyWith(color: c.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

/// [CommentTile]'s leading avatar — a sparkle glyph disc for AI-authored
/// comments, a quiet neutral diamond-glyph square for
/// [CommentAuthorType.system] comments, a "U" initial circle otherwise.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.colors,
    required this.isAi,
    required this.isSystem,
    required this.isDark,
  });

  final AionColors colors;
  final bool isAi;
  final bool isSystem;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    if (isAi) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: c.primary,
          borderRadius: BorderRadius.circular(9),
          boxShadow: AionShadows.aiGlow(c, isDark),
        ),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Center(
            child: PhosphorIcon(
              PhosphorIcons.sparkleLight,
              size: 14,
              color: const Color(0xFFFFFFFF), // white glyph
            ),
          ),
        ),
      );
    }

    if (isSystem) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: c.surfaceHover,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: c.border, width: 1),
        ),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Center(
            child: PhosphorIcon(
              PhosphorIcons.hexagonLight,
              size: 14,
              color: c.textMuted,
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(color: c.secondary, shape: BoxShape.circle),
      child: SizedBox(
        width: 30,
        height: 30,
        child: Center(
          child: Text(
            'U',
            style: AionText.prioritySm.copyWith(color: const Color(0xFFFFFFFF)),
          ),
        ),
      ),
    );
  }
}

/// A compact link chip to a Story's linked design Page, shown directly
/// under the ticket-meta row while `needsDesignReview` is `true` and the
/// design Page exists (design.md §5). Reuses `typePage`'s accent color,
/// the same one `TypeChip`/backlink chips already use for `page`
/// tickets. Added for `aion-arch/changes/sdd-design-gate`.
class _LinkedDesignPageChip extends StatelessWidget {
  const _LinkedDesignPageChip({required this.page, required this.onTap});

  /// The linked design Page ticket (`"Design — <Story title>"`).
  final Ticket page;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return IntrinsicWidth(
      child: Semantics(
        button: true,
        label: page.title,
        child: GestureDetector(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.border, width: 1),
              borderRadius: BorderRadius.all(AionRadius.md),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.typePage.withValues(alpha: 0.11),
                      borderRadius: const BorderRadius.all(
                        Radius.circular(4),
                      ),
                    ),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: Center(
                        child: PhosphorIcon(
                          PhosphorIcons.pencilSimpleLight,
                          size: 10,
                          color: c.typePage,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    page.ticketId,
                    style: AionText.key.copyWith(color: c.typePage),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      page.title,
                      style: AionText.bodySm.copyWith(color: c.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  PhosphorIcon(
                    PhosphorIcons.caretRightLight,
                    size: 13,
                    color: c.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The SDD-stage section shown on epic/story ticket detail, below the
/// ticket-meta row and above the Description block: a variable-length
/// tracker (4 steps — Explore/Propose/Verify/Archive — or 6, with Design
/// Brief/Design Sync inserted between Propose and Verify when
/// [needsDesignReview] isn't `false`; see
/// `aion-arch/changes/sdd-design-gate/design.md` §1), the current-stage
/// line, and one of three mutually-exclusive footers per
/// `aion-arch/changes/sdd-ticket-execution/design.md` §2: when
/// [canAdvance] is `true`, an [automationConfidence]-dependent control
/// (gated banner, plain manual button, or a silent auto-note — see
/// proposal.md's AutomationConfidence semantics section); when it's
/// `false` and [blockReason] is non-null, the "Not ready" hint row (§2.2)
/// explaining what's still pending; otherwise (nothing left to advance
/// to) neither renders.
class _SddStageSection extends StatelessWidget {
  const _SddStageSection({
    required this.ticket,
    required this.canAdvance,
    required this.blockReason,
    required this.automationConfidence,
    required this.onAdvance,
    this.needsDesignReview,
  });

  final Ticket ticket;
  final bool canAdvance;
  final SddStageBlockReason? blockReason;
  final AutomationConfidence? automationConfidence;
  final VoidCallback onAdvance;

  /// Whether [ticket] (a `story`) needs a `designBrief`/`designSync`
  /// pass — `null` while still unknown (before child Tasks exist).
  /// `false` collapses [_stages] to the original 4 nodes; `null`/`true`
  /// show the full 6. Added for `aion-arch/changes/sdd-design-gate`.
  final bool? needsDesignReview;

  static const _fullStages = [
    SddStage.exploring,
    SddStage.proposed,
    SddStage.designBrief,
    SddStage.designSync,
    SddStage.verifying,
    SddStage.archived,
  ];

  static const _collapsedStages = [
    SddStage.exploring,
    SddStage.proposed,
    SddStage.verifying,
    SddStage.archived,
  ];

  List<SddStage> get _stages =>
      needsDesignReview == false ? _collapsedStages : _fullStages;

  String _stageLabel(BuildContext context, SddStage stage) => switch (stage) {
    SddStage.exploring => context.l10n.ticketDetailSddStageExplore,
    SddStage.proposed => context.l10n.ticketDetailSddStagePropose,
    SddStage.designBrief => context.l10n.ticketDetailSddStageDesignBrief,
    SddStage.designSync => context.l10n.ticketDetailSddStageDesignSync,
    SddStage.verifying => context.l10n.ticketDetailSddStageVerify,
    SddStage.archived => context.l10n.ticketDetailSddStageArchive,
  };

  String _stagePresentLabel(BuildContext context, SddStage stage) =>
      switch (stage) {
        SddStage.exploring => context.l10n.ticketDetailSddStageExploring,
        SddStage.proposed => context.l10n.ticketDetailSddStageProposed,
        // Design Brief/Design Sync read naturally as their plain node
        // name — unlike the other stages, no distinct present-
        // progressive form (per design.md §1.3, the approved Claude
        // Design spec's current-stage-line table).
        SddStage.designBrief => context.l10n.ticketDetailSddStageDesignBrief,
        SddStage.designSync => context.l10n.ticketDetailSddStageDesignSync,
        SddStage.verifying => context.l10n.ticketDetailSddStageVerifying,
        SddStage.archived => context.l10n.ticketDetailSddStageArchived,
      };

  /// The stage [canAdvance] would move [ticket] to, or `null` once
  /// [SddStage.archived] is reached — mirrors
  /// `TicketsCubit._nextSddStage` without exposing that private cubit
  /// method to the widget layer. Unlike the cubit's version, this can't
  /// fetch child Tasks itself, so it reads [needsDesignReview] (already
  /// computed by `TicketsCubit.getTicketById`) instead.
  SddStage? _nextStage(SddStage? current) => switch (current) {
    null => SddStage.exploring,
    SddStage.exploring => SddStage.proposed,
    SddStage.proposed => needsDesignReview == true
        ? SddStage.designBrief
        : SddStage.verifying,
    SddStage.designBrief => SddStage.designSync,
    SddStage.designSync => SddStage.verifying,
    SddStage.verifying => SddStage.archived,
    SddStage.archived => null,
  };

  String _blockReasonHint(BuildContext context, SddStageBlockReason reason) =>
      switch (reason) {
        SddStageBlockReason.awaitingChatReply =>
          context.l10n.ticketDetailSddStageHintAwaitingChat,
        SddStageBlockReason.awaitingChildren =>
          ticket.type == TicketType.story
              ? context.l10n.ticketDetailSddStageHintAwaitingTasks
              : context.l10n.ticketDetailSddStageHintAwaitingStories,
        SddStageBlockReason.awaitingDesignPaste =>
          context.l10n.ticketDetailSddStageHintAwaitingDesignPaste,
        SddStageBlockReason.awaitingDesignApproval =>
          context.l10n.ticketDetailSddStageHintAwaitingDesignApproval,
      };

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final currentStage = ticket.sddStage;
    final currentIndex = currentStage == null
        ? -1
        : _stages.indexOf(currentStage);
    final nextStage = _nextStage(currentStage);
    final nextStageLabel = nextStage != null
        ? _stagePresentLabel(context, nextStage)
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.ticketDetailSddStageEyebrow,
          style: AionText.caption.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: AionSpacing.sp12),
        _StageTrackerRow(
          stages: _stages,
          labels: [for (final s in _stages) _stageLabel(context, s)],
          currentIndex: currentIndex,
          // design.md §1.4: 4-node cellW/connGap/label-size vs. 6-node.
          cellW: _stages.length > 4 ? 46 : 54,
          connGap: _stages.length > 4 ? 3 : 4,
          fontSize: _stages.length > 4 ? 10 : 11,
        ),
        const SizedBox(height: AionSpacing.sp8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: c.primary,
                shape: BoxShape.circle,
              ),
              child: const SizedBox(width: 8, height: 8),
            ),
            const SizedBox(width: 8),
            Text(
              currentStage == null
                  ? context.l10n.ticketDetailSddStageNotStarted
                  : _stagePresentLabel(context, currentStage),
              style: AionText.body.copyWith(color: c.textPrimary),
            ),
          ],
        ),
        if (canAdvance && automationConfidence != null) ...[
          const SizedBox(height: AionSpacing.sp12),
          switch (automationConfidence!) {
            AutomationConfidence.gated => _GatedBanner(
              currentStage: currentStage,
              nextStage: nextStage,
              nextStageLabel: nextStageLabel,
              onAdvance: onAdvance,
            ),
            AutomationConfidence.manual => _ManualAdvanceButton(
              nextStageLabel: nextStageLabel,
              onAdvance: onAdvance,
            ),
            // The stage that was just silently advanced to is the
            // *current* one by the time this note renders (the cubit
            // already persisted and re-emitted before this rebuild) --
            // not `nextStageLabel`, which describes where a *further*
            // advance (this refreshed canAdvance being true again) would
            // go next.
            AutomationConfidence.auto => _AutoAdvancedNote(
              stageLabel: currentStage != null
                  ? _stagePresentLabel(context, currentStage)
                  : nextStageLabel,
            ),
          },
        ] else if (!canAdvance && blockReason != null) ...[
          const SizedBox(height: AionSpacing.sp12),
          _NotReadyHint(text: _blockReasonHint(context, blockReason!)),
        ],
      ],
    );
  }
}

/// The "Not ready" state (design.md §2.2): a single hint row explaining
/// what's still blocking [_SddStageSection.onAdvance], shown when the
/// precondition isn't met yet and there's still a next stage to advance
/// to.
class _NotReadyHint extends StatelessWidget {
  const _NotReadyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        PhosphorIcon(PhosphorIcons.infoLight, size: 15, color: c.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AionText.bodySm.copyWith(color: c.textMuted),
          ),
        ),
      ],
    );
  }
}

/// The tracker's node+connector row, per design.md §1.1/§1.4. Stateful
/// only to own the horizontal-scroll fallback's [ScrollController] and
/// jump-to-current-node-on-first-build behavior — the row itself is
/// otherwise a pure function of [stages]/[labels]/[currentIndex]. Added
/// for `aion-arch/changes/sdd-design-gate`, splitting this out of
/// `_SddStageSection` (a [StatelessWidget]) so the scroll state has
/// somewhere to live.
class _StageTrackerRow extends StatefulWidget {
  const _StageTrackerRow({
    required this.stages,
    required this.labels,
    required this.currentIndex,
    required this.cellW,
    required this.connGap,
    required this.fontSize,
  });

  final List<SddStage> stages;
  final List<String> labels;

  /// -1 when [SddStage] is `null` (cycle not started) — no node is
  /// Complete/Current, every node renders Future.
  final int currentIndex;
  final double cellW;
  final double connGap;
  final double fontSize;

  @override
  State<_StageTrackerRow> createState() => _StageTrackerRowState();
}

class _StageTrackerRowState extends State<_StageTrackerRow> {
  final _scrollController = ScrollController();

  /// The row's total natural width if laid out with `Expanded` connectors
  /// replaced by a matching fixed width — used both to decide whether the
  /// narrow-width fallback applies and to size the fallback's scrollable
  /// content.
  double get _naturalWidth {
    final nodes = widget.stages.length;
    if (nodes == 0) return 0;
    const connectorWidth = 24.0;
    return nodes * widget.cellW + (nodes - 1) * connectorWidth;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToCurrent());
  }

  /// Scrolls so the current node is visible on first build, per
  /// design.md §1.4 ("jump the offset so the current node is visible,
  /// via `ScrollController.jumpTo`, not `animateTo` — no entrance
  /// animation"). No-ops if the row isn't actually scrolling (the
  /// controller has no attached `Scrollable`) or nothing is current yet.
  void _jumpToCurrent() {
    if (!mounted || !_scrollController.hasClients) return;
    if (widget.currentIndex < 0) return;
    final nodeCenter =
        widget.currentIndex * widget.cellW + widget.cellW / 2;
    final target = (nodeCenter - _scrollController.position.viewportDimension / 2)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.jumpTo(target);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _row(BuildContext context, {required bool fixedConnectors}) {
    final c = ThemeScope.of(context).colors;
    return Row(
      children: [
        for (var i = 0; i < widget.stages.length; i++) ...[
          _StageNode(
            label: widget.labels[i],
            state: i < widget.currentIndex
                ? _StageNodeState.complete
                : i == widget.currentIndex
                ? _StageNodeState.current
                : _StageNodeState.future,
            width: widget.cellW,
            fontSize: widget.fontSize,
          ),
          if (i < widget.stages.length - 1)
            fixedConnectors
                ? SizedBox(
                    width: 24,
                    child: Container(
                      height: 2,
                      margin: EdgeInsets.only(
                        top: 8,
                        left: widget.connGap,
                        right: widget.connGap,
                      ),
                      color: i < widget.currentIndex ? c.primary : c.border,
                    ),
                  )
                : Expanded(
                    child: Container(
                      height: 2,
                      margin: EdgeInsets.only(
                        top: 8,
                        left: widget.connGap,
                        right: widget.connGap,
                      ),
                      color: i < widget.currentIndex ? c.primary : c.border,
                    ),
                  ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // design.md §1.4: below 336 content width, scroll horizontally
        // (fixed-width connectors, since `Expanded` needs a bounded
        // parent) instead of compressing nodes/clipping labels.
        if (constraints.maxWidth >= 336) {
          return _row(context, fixedConnectors: false);
        }
        return SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: SizedBox(
            width: _naturalWidth,
            child: _row(context, fixedConnectors: true),
          ),
        );
      },
    );
  }
}

/// Visual state of one [_StageNode] relative to the ticket current
/// [SddStage].
enum _StageNodeState { complete, current, future }

/// One node plus label in [_SddStageSection]'s variable-length (4-or-6-step)
/// tracker row. [width]/[fontSize] vary with the tracker's current node
/// count (design.md §1.4's `cellW`/label-size table) — added for
/// `aion-arch/changes/sdd-design-gate`; both default to the original
/// 4-node values so this widget's own behavior is unchanged at that count.
class _StageNode extends StatelessWidget {
  const _StageNode({
    required this.label,
    required this.state,
    this.width = 54,
    this.fontSize = 11,
  });

  final String label;
  final _StageNodeState state;

  /// Fixed cell width per design.md §1.4 (`54` at 4 nodes, `46` at 6).
  final double width;

  /// Label font size per design.md §1.4 (`11` at 4 nodes, `10` at 6) —
  /// still `AionText.time`'s family/weight, only the size varies.
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final isComplete = state == _StageNodeState.complete;
    final isCurrent = state == _StageNodeState.current;

    return SizedBox(
      width: width,
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: isComplete || isCurrent ? c.primary : c.surface,
              shape: BoxShape.circle,
              border: isComplete || isCurrent
                  ? null
                  : Border.all(color: c.borderStrong, width: 1.5),
            ),
            child: SizedBox(
              width: 18,
              height: 18,
              child: Center(
                child: isComplete
                    ? PhosphorIcon(
                        PhosphorIcons.checkLight,
                        size: 10,
                        color: const Color(0xFFFFFFFF),
                      )
                    : isCurrent
                    ? DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFFFFF),
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(width: 6, height: 6),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AionText.time.copyWith(
              fontSize: fontSize,
              height: 1.18,
              color: isCurrent
                  ? c.primary
                  : (isComplete ? c.textSecondary : c.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// AutomationConfidence.gated "ready to advance" banner plus inline
/// confirm button. Design-gate-aware since
/// `aion-arch/changes/sdd-design-gate`: while [currentStage] is
/// [SddStage.designBrief]/[SddStage.designSync], the leading glyph
/// switches to a `typePage`-tinted pencil (design.md §3.2) and a
/// precondition-met sub-line appears under the title (design.md §3.3) —
/// every other stage keeps the original sparkle glyph and single-line
/// title unchanged.
class _GatedBanner extends StatelessWidget {
  const _GatedBanner({
    required this.currentStage,
    required this.nextStage,
    required this.nextStageLabel,
    required this.onAdvance,
  });

  /// [Ticket.sddStage] before this advance — determines the design-stage
  /// glyph/sub-line accent per design.md §3.2/§3.3.
  final SddStage? currentStage;

  /// The stage this advance would move to — combined with [currentStage]
  /// to pick the right sub-line from design.md §3.3's table.
  final SddStage? nextStage;

  /// The present-progressive name of the stage advancing would move to
  /// (e.g. `"Verifying"`), interpolated into the banner title per
  /// design.md §2.3.
  final String nextStageLabel;
  final VoidCallback onAdvance;

  /// The sub-line text from design.md §3.3's table, or `null` for every
  /// transition it doesn't cover (the original explore/propose/verify/
  /// archive stages keep no sub-line at all).
  String? _subLine(BuildContext context) => switch ((currentStage, nextStage)) {
    (SddStage.proposed, SddStage.designBrief) =>
      context.l10n.ticketDetailSddStageSubProposalAccepted,
    (SddStage.designBrief, SddStage.designSync) =>
      context.l10n.ticketDetailSddStageSubDesignPasted,
    (SddStage.designSync, SddStage.verifying) =>
      context.l10n.ticketDetailSddStageSubDesignApproved,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isDesignStage =
        currentStage == SddStage.designBrief ||
        currentStage == SddStage.designSync;
    final subLine = _subLine(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: t.fillAlpha),
        border: Border.all(
          color: c.primary.withValues(alpha: t.isDark ? 0.42 : 0.28),
          width: 1,
        ),
        borderRadius: BorderRadius.all(AionRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            PhosphorIcon(
              isDesignStage
                  ? PhosphorIcons.pencilSimpleLight
                  : PhosphorIcons.sparkleLight,
              size: 18,
              color: isDesignStage ? c.typePage : c.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.ticketDetailSddStageReadyBanner(
                      nextStageLabel,
                    ),
                    style: AionText.cardTitle.copyWith(color: c.textPrimary),
                  ),
                  if (subLine != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subLine,
                      style: AionText.time.copyWith(color: c.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            Semantics(
              button: true,
              label: context.l10n.ticketDetailSddStageAdvance,
              child: GestureDetector(
                onTap: onAdvance,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.primary,
                    borderRadius: BorderRadius.all(AionRadius.md),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 9,
                    ),
                    child: Text(
                      context.l10n.ticketDetailSddStageAdvance,
                      style: AionText.button.copyWith(
                        color: const Color(0xFFFFFFFF),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// AutomationConfidence.manual plain, always-visible advance button --
/// quieter than [_GatedBanner], no banner framing.
class _ManualAdvanceButton extends StatelessWidget {
  const _ManualAdvanceButton({
    required this.nextStageLabel,
    required this.onAdvance,
  });

  /// The present-progressive name of the stage advancing would move to
  /// (e.g. `"Verifying"`), interpolated into the button label per
  /// design.md §2.4 — this button has no banner title to supply that
  /// context, unlike [_GatedBanner]'s inline "Advance".
  final String nextStageLabel;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final label = context.l10n.ticketDetailSddStageAdvanceToStage(
      nextStageLabel,
    );
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onAdvance,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.surfaceHover,
            border: Border.all(color: c.borderStrong, width: 1),
            borderRadius: BorderRadius.all(AionRadius.md),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PhosphorIcon(
                  PhosphorIcons.caretRightLight,
                  size: 14,
                  color: c.primary,
                ),
                const SizedBox(width: 7),
                Text(label, style: AionText.button.copyWith(color: c.primary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The coding-execution section shown on a `task` ticket's detail view,
/// below the ticket-meta row and above the Description block — the same
/// slot [_SddStageSection] occupies for `epic`/`story` tickets (only one
/// of the two ever renders for a given ticket type). Rendered only while
/// [isExecuting], [executionQueuePosition], or [executionAwaitingReview]
/// is truthy — a Task not yet attached to any run shows neither this nor
/// [_SddStageSection]. Reuses the plain-`Column`/divider framing
/// [_SddStageSection] already establishes for this slot rather than
/// wrapping in its own bordered container, per
/// `aion-arch/changes/task-to-coding-execution-trigger/design.md`'s §0
/// container spec (the surrounding divider already supplies the "top
/// border" it describes). Per design.md §0.
class _CodingExecutionSection extends StatelessWidget {
  const _CodingExecutionSection({
    required this.isExecuting,
    required this.executionQueuePosition,
    required this.executionAwaitingReview,
    required this.onMarkReadyForReview,
  });

  final bool isExecuting;
  final int? executionQueuePosition;
  final bool executionAwaitingReview;
  final VoidCallback onMarkReadyForReview;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final (Color dotColor, String statusText) = isExecuting
        ? (c.primary, context.l10n.ticketDetailCodingExecutionStatusExecuting)
        : executionQueuePosition != null
        ? (c.secondary, context.l10n.ticketDetailCodingExecutionStatusQueued)
        : (c.success, context.l10n.ticketDetailCodingExecutionStatusDone);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.ticketDetailCodingExecutionEyebrow,
          style: AionText.caption.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: AionSpacing.sp12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              child: const SizedBox(width: 8, height: 8),
            ),
            const SizedBox(width: 8),
            Text(statusText, style: AionText.body.copyWith(color: c.textPrimary)),
          ],
        ),
        const SizedBox(height: 14),
        if (isExecuting)
          const _ExecutionRunningHint()
        else if (executionQueuePosition != null)
          _ExecutionQueueHint(position: executionQueuePosition!)
        else if (executionAwaitingReview)
          _ExecutionReadyForReviewBanner(onConfirm: onMarkReadyForReview),
      ],
    );
  }
}

/// Shown while the Task's coding-execution chat is actively running.
/// Mirrors [_NotReadyHint]'s informational-row shape (icon + text, no
/// background/border/padding box) but takes an active treatment — a
/// slowly, continuously rotating gear glyph — so it reads as "work in
/// progress," not "blocked/waiting." Per design.md §1.
class _ExecutionRunningHint extends StatefulWidget {
  const _ExecutionRunningHint();

  @override
  State<_ExecutionRunningHint> createState() => _ExecutionRunningHintState();
}

class _ExecutionRunningHintState extends State<_ExecutionRunningHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _gearController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  bool _startedSpinning = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_startedSpinning && !MediaQuery.of(context).disableAnimations) {
      _startedSpinning = true;
      _gearController.repeat();
    }
  }

  @override
  void dispose() {
    _gearController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        RotationTransition(
          turns: _gearController,
          child: PhosphorIcon(
            PhosphorIcons.gearSixLight,
            size: 15,
            color: c.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            context.l10n.ticketDetailCodingExecutionRunningHint,
            style: AionText.bodySm.copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Shown while the Task is waiting behind another in-flight execution
/// (FIFO). Same informational-row shape as [_ExecutionRunningHint] but
/// static/muted, since a queued Task genuinely cannot proceed yet — and
/// displays an interpolated 1-based queue [position] via [ordinal]. Per
/// design.md §2.
class _ExecutionQueueHint extends StatelessWidget {
  const _ExecutionQueueHint({required this.position});

  /// 1-based position in the coding-execution FIFO queue.
  final int position;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final text = position == 1
        ? context.l10n.ticketDetailCodingExecutionQueuedNext
        : context.l10n.ticketDetailCodingExecutionQueuedNth(ordinal(position));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        PhosphorIcon(PhosphorIcons.stackLight, size: 15, color: c.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: AionText.bodySm.copyWith(color: c.textMuted)),
        ),
      ],
    );
  }
}

/// Ordinal string for [n] (`1` → `"1st"`, `2` → `"2nd"`, `11..13` →
/// `"11th"`/`"12th"`/`"13th"`, etc.), for
/// [_ExecutionQueueHint]'s interpolated queue position. Per design.md
/// §2.1/§5.
String ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

/// Shown once the Task's coding-execution run finished successfully (a
/// PR was confirmed opened) and [AutomationConfidence.gated] applies —
/// the human must confirm before the Task flips to "In Review". Mirrors
/// [_GatedBanner]'s tinted container/border/leading-icon shape, re-keyed
/// to [AionColors.success] (a completion moment, not an "advance the SDD
/// stage" prompt), with its action button stacked full-width below the
/// text rather than trailing inline — design.md §3's copy doesn't fit
/// inline beside a two-line title at the narrowest supported phone width
/// without crushing it to 3 lines. The title carries alone with no
/// sub-line: no PR metadata (number, file count) is parsed from the
/// run's reply today — only the confirmation the last line contained
/// `EXECUTION: PR_OPENED` — so per design.md §3.3's fallback rule
/// ("omit only if no PR metadata is available"), the sub-line is
/// omitted rather than showing placeholder copy. Per design.md §3.
class _ExecutionReadyForReviewBanner extends StatelessWidget {
  const _ExecutionReadyForReviewBanner({required this.onConfirm});

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.success.withValues(alpha: t.fillAlpha),
        border: Border.all(
          color: c.success.withValues(alpha: t.isDark ? 0.42 : 0.28),
          width: 1,
        ),
        borderRadius: BorderRadius.all(AionRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                PhosphorIcon(
                  PhosphorIcons.gitPullRequestLight,
                  size: 18,
                  color: c.success,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.l10n.ticketDetailCodingExecutionReadyTitle,
                    style: AionText.cardTitle.copyWith(color: c.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _MarkReadyForReviewButton(onConfirm: onConfirm),
          ],
        ),
      ),
    );
  }
}

/// [_ExecutionReadyForReviewBanner]'s full-width "Mark ready for review"
/// confirm button — solid [AionColors.success] fill/glow, hover/focus/
/// press states mirroring [AppButton]'s own but re-keyed to `success`
/// (which [AppButton]'s fixed variant set doesn't offer). Per design.md
/// §3.4/§3.5.
class _MarkReadyForReviewButton extends StatefulWidget {
  const _MarkReadyForReviewButton({required this.onConfirm});

  final VoidCallback onConfirm;

  @override
  State<_MarkReadyForReviewButton> createState() =>
      _MarkReadyForReviewButtonState();
}

class _MarkReadyForReviewButtonState
    extends State<_MarkReadyForReviewButton> {
  final ValueNotifier<bool> _isHovered = ValueNotifier(false);
  bool _isPressed = false;
  bool _isConfirming = false;

  @override
  void dispose() {
    _isHovered.dispose();
    super.dispose();
  }

  Future<void> _handleConfirm() async {
    if (_isConfirming) return;
    setState(() => _isConfirming = true);
    try {
      widget.onConfirm();
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final label = context.l10n.ticketDetailCodingExecutionMarkReadyButton;

    return Semantics(
      button: true,
      label: label,
      enabled: !_isConfirming,
      child: FocusableActionDetector(
        enabled: !_isConfirming,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              unawaited(_handleConfirm());
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: _isConfirming
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          onEnter: (_) => _isHovered.value = true,
          onExit: (_) => _isHovered.value = false,
          child: GestureDetector(
            onTap: _isConfirming ? null : () => unawaited(_handleConfirm()),
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            child: ValueListenableBuilder<bool>(
              valueListenable: _isHovered,
              builder: (context, hovered, _) {
                final fill = _isConfirming
                    ? c.success.withValues(alpha: 0.45)
                    : (hovered
                          ? Color.lerp(
                              c.success,
                              t.isDark
                                  ? const Color(0xFFFFFFFF)
                                  : const Color(0xFF000000),
                              0.10,
                            )!
                          : c.success);
                final glowBlur = _isPressed ? 0.0 : (hovered ? 22.0 : 18.0);
                return AnimatedScale(
                  scale: !_isConfirming && _isPressed ? 0.98 : 1.0,
                  duration: const Duration(milliseconds: 80),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.all(AionRadius.md),
                      boxShadow: glowBlur > 0
                          ? [
                              BoxShadow(
                                color: c.success.withValues(
                                  alpha: t.isDark ? 0.60 : 0.45,
                                ),
                                blurRadius: glowBlur,
                                spreadRadius: -9,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : const [],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 10,
                      ),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: AionText.button.copyWith(
                          color: const Color(
                            0xFFFFFFFF,
                          ).withValues(alpha: _isConfirming ? 0.45 : 1),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A plain, always-available control for re-running
/// [SddStage.designSync]'s validation after a `DESIGN GATE: PENDING`
/// verdict — styled like [_ManualAdvanceButton] (no banner framing,
/// since this is a recovery utility, not a proactive suggestion), with
/// a refresh glyph instead of a caret. See design.md §4. Added for
/// `aion-arch/changes/sdd-design-gate`.
class _RetryValidationButton extends StatefulWidget {
  const _RetryValidationButton({
    required this.onRetry,
    this.isLoading = false,
  });

  final VoidCallback onRetry;

  /// Disabled/spinning-glyph state (design.md §4.3) while a retry is
  /// already in flight — `IgnorePointer`, `0.45` opacity, `textMuted`
  /// glyph/text, glyph spinning via a 900ms linear loop. Added for
  /// `aion-arch/changes/sdd-design-gate`.
  final bool isLoading;

  @override
  State<_RetryValidationButton> createState() =>
      _RetryValidationButtonState();
}

class _RetryValidationButtonState extends State<_RetryValidationButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isLoading) _spinController.repeat();
  }

  @override
  void didUpdateWidget(_RetryValidationButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading && !oldWidget.isLoading) {
      _spinController.repeat();
    } else if (!widget.isLoading && oldWidget.isLoading) {
      _spinController
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final label = context.l10n.chatRetryValidation;
    final glyphColor = widget.isLoading ? c.textMuted : c.primary;
    final button = DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceHover.withValues(alpha: widget.isLoading ? 0.45 : 1),
        border: Border.all(
          color: c.borderStrong.withValues(alpha: widget.isLoading ? 0.45 : 1),
          width: 1,
        ),
        borderRadius: BorderRadius.all(AionRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotationTransition(
              turns: _spinController,
              child: PhosphorIcon(
                PhosphorIcons.arrowsClockwiseLight,
                size: 14,
                color: glyphColor,
              ),
            ),
            const SizedBox(width: 7),
            Text(label, style: AionText.button.copyWith(color: glyphColor)),
          ],
        ),
      ),
    );
    return Semantics(
      button: true,
      label: label,
      enabled: !widget.isLoading,
      child: IgnorePointer(
        ignoring: widget.isLoading,
        child: GestureDetector(onTap: widget.onRetry, child: button),
      ),
    );
  }
}

/// AutomationConfidence.auto transient confirmation note -- shown while
/// the stage has already silently advanced (or is in flight) via the
/// post-frame callback in _TicketDetailScreenState
/// ._maybeAutoAdvanceSddStage; no button, since auto never asks.
class _AutoAdvancedNote extends StatelessWidget {
  const _AutoAdvancedNote({required this.stageLabel});

  /// The present-progressive name of the stage that was just advanced to
  /// (e.g. `"Verifying"`), interpolated into the note text per
  /// design.md §2.5.
  final String stageLabel;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.success.withValues(alpha: t.fillAlpha),
        border: Border.all(
          color: c.success.withValues(alpha: t.isDark ? 0.42 : 0.28),
          width: 1,
        ),
        borderRadius: BorderRadius.all(AionRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            PhosphorIcon(
              PhosphorIcons.sealCheckLight,
              size: 16,
              color: c.success,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                context.l10n.ticketDetailSddStageAutoAdvancedNote(stageLabel),
                style: AionText.bodySm.copyWith(color: c.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders an in-progress AI reply accumulated [text] at the tail of a
/// chat ticket comment thread, styled like an AI [CommentTile] but with a
/// trailing blinking-caret "typing" indicator instead of a timestamp --
/// see ChatState.ChatLoaded.streamingText.
class _StreamingBubble extends StatefulWidget {
  const _StreamingBubble({required this.text});

  /// The accumulated reply text so far.
  final String text;

  @override
  State<_StreamingBubble> createState() => _StreamingBubbleState();
}

class _StreamingBubbleState extends State<_StreamingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _caretController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _caretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: AionSpacing.sp16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(colors: c, isAi: true, isSystem: false, isDark: t.isDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      context.l10n.ticketDetailAiAuthor,
                      style: AionText.cardTitle.copyWith(
                        fontSize: 12.5,
                        color: c.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      context.l10n.ticketDetailTyping,
                      style: AionText.time.copyWith(color: c.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: AionSpacing.sp4),
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(3),
                      topRight: AionRadius.lg,
                      bottomLeft: AionRadius.lg,
                      bottomRight: AionRadius.lg,
                    ),
                    color: c.primarySubtle,
                    border: Border.all(
                      color: c.primary.withValues(
                        alpha: t.isDark ? 0.42 : 0.28,
                      ),
                      width: 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: RichText(
                      text: TextSpan(
                        style: AionText.bodySm.copyWith(
                          color: c.textPrimary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                        children: [
                          TextSpan(text: widget.text),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: FadeTransition(
                              opacity: _caretController,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: c.primary,
                                  borderRadius: BorderRadius.circular(1),
                                ),
                                child: const SizedBox(width: 2, height: 15),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
