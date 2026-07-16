// presentation/screens/ticket_detail_screen.dart — Ticket detail screen and comment widgets (presentation layer).

import 'package:flutter/material.dart'
    show Material, MaterialType, TextField, InputDecoration;
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:intl/intl.dart' show DateFormat;

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';
import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/presentation/cubit/comments_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/comments_state.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_state.dart';
import 'package:aion/features/tickets/presentation/screens/tickets_board_view.dart';
import 'package:aion/features/tickets/presentation/screens/tickets_list_screen.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_overflow_menu.dart';

/// The `/tickets/:id` route: ticket meta (priority, title, type, status,
/// description, timestamps), a comment thread, and a pinned comment
/// composer. [TicketsCubit] is read from the root-level provider;
/// [CommentsCubit] is provided per-route by [appRouter](../../../../core/routing/app_router.dart)
/// since comments are screen-scoped.
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

  @override
  void initState() {
    super.initState();
    context.read<TicketsCubit>().getTicketById(widget.ticketId);
    context.read<CommentsCubit>().loadComments(widget.ticketId);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
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
          context.go('/tickets');
        } else if (state is TicketsError &&
            state.reason == TicketsErrorReason.invalidParent) {
          AppToast.show(context, context.l10n.ticketInvalidParentError);
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
                  onBack: () => context.go('/tickets'),
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                  trailing: state is TicketDetailLoaded
                      ? TicketOverflowMenu(ticket: state.ticket)
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
                                                  ticketStatusLabel(
                                                    context,
                                                    s,
                                                  ),
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
                                          TicketParentPicker(ticket: ticket),
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
            _buildAvatar(c, isAi, t.isDark),
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

  Widget _buildAvatar(AionColors c, bool isAi, bool isDark) {
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

  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

/// Overlay-picker for reassigning [ticket]'s structural parent
/// (`parentId`). The trigger shows the current parent's ticket key and
/// title, or a "+ PARENT" placeholder when unset; tapping it opens a
/// searchable, scrollable list of valid candidate parents (self and
/// descendants already excluded by [TicketsCubit.getValidParentCandidates])
/// plus a "No parent" row to clear the field. Not built on [SelectionMenu]
/// — that widget renders an unbounded, non-scrolling, non-searchable list,
/// which doesn't scale to an open-ended ticket set. Follows
/// [TicketOverflowMenu]'s `Overlay`/`LayerLink`/
/// `CompositedTransformFollower`/`mounted`-guard mechanics instead.
class TicketParentPicker extends StatefulWidget {
  /// Creates a [TicketParentPicker] for [ticket].
  const TicketParentPicker({super.key, required this.ticket});

  /// The ticket whose parent this picker reassigns.
  final Ticket ticket;

  @override
  State<TicketParentPicker> createState() => _TicketParentPickerState();
}

class _TicketParentPickerState extends State<TicketParentPicker> {
  final LayerLink _layerLink = LayerLink();
  final TextEditingController _searchController = TextEditingController();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  /// Valid reparent candidates, fetched once on mount so the trigger can
  /// resolve the current parent's title without waiting for the overlay
  /// to open. `null` while the initial fetch is in flight.
  List<Ticket>? _candidates;

  @override
  void initState() {
    super.initState();
    _loadCandidates();
    _searchController.addListener(_handleSearchChanged);
  }

  Future<void> _loadCandidates() async {
    final candidates = await context.read<TicketsCubit>().getValidParentCandidates(
      widget.ticket,
    );
    if (!mounted) return;
    setState(() => _candidates = candidates);
    _overlayEntry?.markNeedsBuild();
  }

  void _handleSearchChanged() {
    _overlayEntry?.markNeedsBuild();
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  void _toggleOverlay() {
    if (_isOpen) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final overlay = Overlay.of(context);

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final query = _searchController.text.trim().toLowerCase();
        final candidates = _candidates;
        final filtered = candidates?.where(
          (cand) =>
              query.isEmpty ||
              cand.ticketId.toLowerCase().contains(query) ||
              cand.title.toLowerCase().contains(query),
        ).toList();

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeOverlay,
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: const Offset(0, 6),
              targetAnchor: Alignment.bottomLeft,
              child: Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    _removeOverlay();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border.all(color: c.borderStrong, width: 1),
                    borderRadius: BorderRadius.all(AionRadius.lg),
                    boxShadow: AionShadows.overlay(c, t.isDark),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 320,
                      maxWidth: 320,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AionSpacing.sp12),
                          child: AppTextField(
                            controller: _searchController,
                            hintText: overlayContext
                                .l10n
                                .ticketDetailParentSearchHint,
                          ),
                        ),
                        Container(color: c.border, height: 1),
                        _NoParentRow(
                          isCurrent: widget.ticket.parentId == null,
                          onTap: () => _commit(null),
                        ),
                        Container(color: c.border, height: 1),
                        if (candidates == null)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: AionSpacing.sp32,
                            ),
                            child: Center(child: AppSpinner()),
                          )
                        else if (filtered!.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AionSpacing.sp32,
                            ),
                            child: Center(
                              child: Text(
                                overlayContext
                                    .l10n
                                    .ticketDetailParentNoResults,
                                style: AionText.bodySm.copyWith(
                                  color: c.textMuted,
                                ),
                              ),
                            ),
                          )
                        else
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 320),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final candidate = filtered[index];
                                return _CandidateRow(
                                  ticket: candidate,
                                  onTap: () => _commit(candidate.id),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _commit(String? parentId) {
    context.read<TicketsCubit>().updateTicketParent(widget.ticket, parentId);
    _removeOverlay();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    // Guards against setState-after-dispose — the same class of bug
    // project.md's AppDropdown overlay-dismiss crash note warns about.
    if (mounted) {
      setState(() => _isOpen = false);
    } else {
      _isOpen = false;
    }
  }

  /// Looks up the display title for [parentId] among the already-loaded
  /// [_candidates] — the current parent is always present there (it's
  /// necessarily an ancestor of [widget.ticket], never excluded by
  /// [TicketsCubit.getValidParentCandidates]'s self/descendant filter).
  Ticket? _resolveParent(String parentId) {
    final candidates = _candidates;
    if (candidates == null) return null;
    for (final candidate in candidates) {
      if (candidate.id == parentId) return candidate;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final parentId = widget.ticket.parentId;
    final resolvedParent = parentId == null ? null : _resolveParent(parentId);

    return CompositedTransformTarget(
      link: _layerLink,
      child: Semantics(
        button: true,
        label: context.l10n.ticketDetailChangeParent,
        child: FocusableActionDetector(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _toggleOverlay();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTap: _toggleOverlay,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _isOpen ? c.surfaceHover : const Color(0x00000000),
                borderRadius: BorderRadius.all(AionRadius.md),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AionSpacing.sp8,
                  vertical: 4,
                ),
                child: parentId == null
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PhosphorIcon(
                            PhosphorIcons.plusLight,
                            size: 12,
                            color: c.textMuted,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            context.l10n.ticketDetailAddParent,
                            style: AionText.label.copyWith(
                              color: c.textMuted,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PhosphorIcon(
                            PhosphorIcons.gitBranchLight,
                            size: 14,
                            color: c.textMuted,
                          ),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: resolvedParent?.ticketId ?? '…',
                                    style: AionText.key.copyWith(
                                      color: c.textSecondary,
                                    ),
                                  ),
                                  TextSpan(
                                    text: '  —  ',
                                    style: AionText.bodySm.copyWith(
                                      color: c.textMuted,
                                    ),
                                  ),
                                  TextSpan(
                                    text: resolvedParent?.title ?? '',
                                    style: AionText.bodySm.copyWith(
                                      color: c.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "No parent" row always shown first in [TicketParentPicker]'s
/// overlay list, letting the user clear [Ticket.parentId] back to `null`.
/// Shows a check mark and primary-tinted label when [isCurrent] is true.
class _NoParentRow extends StatefulWidget {
  /// Creates a [_NoParentRow].
  const _NoParentRow({required this.isCurrent, required this.onTap});

  /// Whether the ticket currently has no parent — renders the
  /// "selected" treatment when true.
  final bool isCurrent;

  /// Called when the row is tapped.
  final VoidCallback onTap;

  @override
  State<_NoParentRow> createState() => _NoParentRowState();
}

class _NoParentRowState extends State<_NoParentRow> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final fill = _isPressed
        ? c.border
        : _isHovered
        ? c.surfaceHover
        : const Color(0x00000000);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapCancel: () => setState(() => _isPressed = false),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(color: fill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            child: Row(
              children: [
                PhosphorIcon(
                  PhosphorIcons.xCircleLight,
                  size: 14,
                  color: c.textMuted,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    context.l10n.ticketDetailNoParentOption,
                    style: AionText.bodySm.copyWith(
                      color: widget.isCurrent ? c.primary : c.textMuted,
                    ),
                  ),
                ),
                if (widget.isCurrent)
                  PhosphorIcon(
                    PhosphorIcons.checkLight,
                    size: 14,
                    color: c.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single selectable candidate row in [TicketParentPicker]'s overlay
/// list — a fixed-width monospace ticket key plus the ticket's title.
class _CandidateRow extends StatefulWidget {
  /// Creates a [_CandidateRow] for [ticket].
  const _CandidateRow({required this.ticket, required this.onTap});

  /// The candidate ticket this row represents.
  final Ticket ticket;

  /// Called when the row is tapped.
  final VoidCallback onTap;

  @override
  State<_CandidateRow> createState() => _CandidateRowState();
}

class _CandidateRowState extends State<_CandidateRow> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final fill = _isPressed
        ? c.border
        : _isHovered
        ? c.surfaceHover
        : const Color(0x00000000);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapCancel: () => setState(() => _isPressed = false),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(color: fill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    widget.ticket.ticketId,
                    style: AionText.key.copyWith(color: c.textSecondary),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.ticket.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AionText.bodySm.copyWith(color: c.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
