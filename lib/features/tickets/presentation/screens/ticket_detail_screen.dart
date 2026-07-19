// presentation/screens/ticket_detail_screen.dart — Ticket detail screen and comment widgets (presentation layer).

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
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sync_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_link_repository.dart';
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

/// The `/tickets/:id` route: ticket meta (priority, title, type, status,
/// description, timestamps), a comment thread, and a pinned comment
/// composer. [TicketsCubit] is read from the root-level provider;
/// [CommentsCubit] is provided per-route by [appRouter](../../../../core/routing/app_router.dart)
/// since comments are screen-scoped. For `resource` tickets, also renders
/// two Documentation-section sections — Linked Tickets and Backlinks —
/// populated via [TicketsCubit.loadDocumentRelations]. `page` tickets no
/// longer render here at all: since `page-content-markdown-editor`, a
/// loaded `page` ticket immediately redirects to `PageDetailScreen` via
/// `/workspace/pages/:id` (see the `TicketDetailLoaded` branch below) —
/// this screen now only ever renders `resource`/work-item tickets.
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

  @override
  void initState() {
    super.initState();
    context.read<TicketsCubit>().getTicketById(widget.ticketId);
    context.read<CommentsCubit>().loadComments(widget.ticketId);
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

  /// [TicketRepairService] is only provided on desktop with a resolved
  /// project directory — same nullability rationale as
  /// [_tryReadRegistry].
  TicketRepairService? _tryReadRepairService(BuildContext context) {
    try {
      return context.read<TicketRepairService>();
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

  /// Builds the [TicketNeedsRepairBanner] wrapped in its own
  /// [TicketRepairCubit], scoped to [ticket]'s `ticketId`/rootPath. Only
  /// called when [_isSyncable] and `needsRepair` are both true, at which
  /// point [_tryReadRepairService]/[_tryReadRootPath] are guaranteed
  /// non-null (both gated on the same desktop-with-project condition as
  /// [_tryReadRegistry], which [_isSyncable] already checked).
  Widget _buildRepairBanner(BuildContext context, Ticket ticket) {
    final service = _tryReadRepairService(context);
    final rootPath = _tryReadRootPath(context);
    if (service == null || rootPath == null) return const SizedBox.shrink();

    return BlocProvider<TicketRepairCubit>(
      key: ValueKey('repair-${ticket.ticketId}'),
      create: (_) => TicketRepairCubit(service, ticket.ticketId, rootPath),
      child: TicketNeedsRepairBanner(
        // Always `resource` here — see [_isSyncable]/the class doc comment.
        isPage: false,
        onRepaired: () =>
            context.read<TicketsCubit>().getTicketById(widget.ticketId),
      ),
    );
  }

  void _sendComment() {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;
    context.read<CommentsCubit>().addComment(
      ticketId: widget.ticketId,
      content: content,
    );
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
                              SyncStatusBadge(
                                status: state.ticket.syncStatus,
                              ),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                            child: BlocBuilder<TicketsCubit, TicketsState>(
                              builder: (context, state) {
                                return switch (state) {
                                  TicketsLoading() => const Center(
                                    child: AppSpinner(),
                                  ),
                                  TicketsError(:final message, :final reason) =>
                                    Text(
                                      reason != null
                                          ? ticketsErrorMessage(context, reason)
                                          : message,
                                      style: AionText.body.copyWith(
                                        color: c.danger,
                                      ),
                                    ),
                                  TicketDetailLoaded(:final ticket) => Semantics(
                                    header: true,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (_isSyncable(ticket) &&
                                            ticket.syncStatus ==
                                                TicketSyncStatus.needsRepair)
                                          _buildRepairBanner(context, ticket),
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
                                                        color: c.textMuted,
                                                      ),
                                                )
                                              : PriorityBadge(
                                                  priority: ticket.priority,
                                                  isRow: false,
                                                ),
                                          items: TicketPriority.values,
                                          itemLabel: (p) =>
                                              ticketPriorityLabel(context, p),
                                          currentValue: ticket.priority,
                                          onSelected: (p) => context
                                              .read<TicketsCubit>()
                                              .updateTicket(
                                                ticket.copyWith(priority: p),
                                              ),
                                          semanticsLabel: context
                                              .l10n
                                              .ticketDetailChangePriority,
                                        ),
                                        const SizedBox(height: AionSpacing.sp8),
                                        InlineEditableField<String>(
                                          displayText: ticket.title,
                                          editText: ticket.title,
                                          maxLines: 1,
                                          textStyle: AionText.h2.copyWith(
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
                                                ticket.copyWith(title: v),
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
                                                  ticketTypeLabel(context, ty),
                                              currentValue: ticket.type,
                                              onSelected: (ty) => context
                                                  .read<TicketsCubit>()
                                                  .updateTicket(
                                                    ticket.copyWith(type: ty),
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
                                              items: TicketStatus.values,
                                              itemLabel: (s) =>
                                                  ticketStatusLabel(context, s),
                                              currentValue: ticket.status,
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
                                        if (ticket.type != TicketType.epic) ...[
                                          const SizedBox(
                                            height: AionSpacing.sp8,
                                          ),
                                          TicketParentPicker(
                                            ticketType: ticket.type,
                                            currentParentId: ticket.parentId,
                                            candidatesLoader: () => context
                                                .read<TicketsCubit>()
                                                .getValidParentCandidates(
                                                  ticket,
                                                ),
                                            onParentSelected: (parentId) =>
                                                context
                                                    .read<TicketsCubit>()
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
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  context
                                                      .l10n
                                                      .ticketDetailEstimateCaption,
                                                  style: AionText.caption
                                                      .copyWith(
                                                        color: c.textMuted,
                                                      ),
                                                ),
                                                const SizedBox(
                                                  height: AionSpacing.sp4,
                                                ),
                                                InlineEditableField<int?>(
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
                                                  textStyle: AionText.bodySm
                                                      .copyWith(
                                                        color: c.textPrimary,
                                                        fontWeight:
                                                            FontWeight.w600,
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
                                                      .read<TicketsCubit>()
                                                      .updateTicket(
                                                        ticket.copyWith(
                                                          estimate: () => v,
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
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  context
                                                      .l10n
                                                      .ticketDetailTimeSpentCaption,
                                                  style: AionText.caption
                                                      .copyWith(
                                                        color: c.textMuted,
                                                      ),
                                                ),
                                                const SizedBox(
                                                  height: AionSpacing.sp4,
                                                ),
                                                InlineEditableField<int?>(
                                                  displayText:
                                                      formatDurationMinutes(
                                                        ticket.timeSpent,
                                                        placeholder: '',
                                                      ),
                                                  editText:
                                                      formatDurationMinutes(
                                                        ticket.timeSpent,
                                                        placeholder: '',
                                                      ),
                                                  placeholder: context
                                                      .l10n
                                                      .ticketDetailTimeSpentPlaceholder,
                                                  textStyle: AionText.bodySm
                                                      .copyWith(
                                                        color: c.textPrimary,
                                                        fontWeight:
                                                            FontWeight.w600,
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
                                                      .read<TicketsCubit>()
                                                      .updateTicket(
                                                        ticket.copyWith(
                                                          timeSpent: () => v,
                                                        ),
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(
                                          height: AionSpacing.sp16,
                                        ),
                                        Container(color: c.border, height: 1),
                                        const SizedBox(
                                          height: AionSpacing.sp16,
                                        ),
                                        Text(
                                          context
                                              .l10n
                                              .ticketDetailDescriptionCaption,
                                          style: AionText.caption.copyWith(
                                            color: c.textMuted,
                                          ),
                                        ),
                                        const SizedBox(height: AionSpacing.sp8),
                                        InlineEditableField<String?>(
                                          displayText: ticket.description ?? '',
                                          editText: ticket.description ?? '',
                                          maxLines: 6,
                                          placeholder: context
                                              .l10n
                                              .ticketDetailDescriptionPlaceholder,
                                          textStyle: AionText.body.copyWith(
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
                                        const SizedBox(height: AionSpacing.sp8),
                                        Text(
                                          context.l10n.ticketDetailCreatedOn(
                                            DateFormat.yMMMd().format(
                                              ticket.createdAt,
                                            ),
                                          ),
                                          style: AionText.time.copyWith(
                                            color: c.textMuted,
                                          ),
                                        ),
                                      ],
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
                                              linkType: TicketLinkType.relatesTo,
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
                            child: BlocBuilder<CommentsCubit, CommentsState>(
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
                                        context.l10n.ticketDetailCommentsCount(
                                          comments.length,
                                        ),
                                        style: AionText.caption.copyWith(
                                          color: c.textMuted,
                                        ),
                                      ),
                                      const SizedBox(height: AionSpacing.sp12),
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
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(color: c.border, height: 1),
                  ColoredBox(
                    color: c.background,
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
                                borderRadius: BorderRadius.all(AionRadius.pill),
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
                                      hintText:
                                          context.l10n.ticketDetailCommentHint,
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
                ],
              ),
            ),
          ],
        ),
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

    return Semantics(
      label: '${comment.authorType.name} comment: ${comment.content}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: AionSpacing.sp16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(colors: c, isAi: isAi, isDark: t.isDark),
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
                      ] else
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
                          color: c.textPrimary,
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
/// comments, a "U" initial circle otherwise.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.colors,
    required this.isAi,
    required this.isDark,
  });

  final AionColors colors;
  final bool isAi;
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
