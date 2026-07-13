// presentation/screens/ticket_detail_screen.dart — Ticket detail screen and comment widgets (presentation layer).

import 'package:flutter/material.dart'
    show Material, MaterialType, TextField, InputDecoration;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:intl/intl.dart' show DateFormat;

import 'package:aion/core/localization/context_localizations_x.dart';
import 'package:aion/core/theme/aion_colors.dart';
import 'package:aion/core/theme/aion_radius.dart';
import 'package:aion/core/theme/aion_shadows.dart';
import 'package:aion/core/theme/aion_text.dart';
import 'package:aion/core/theme/theme_scope.dart';
import 'package:aion/core/utils/duration_format.dart';
import 'package:aion/core/widgets/app_confirm_dialog.dart';
import 'package:aion/core/widgets/app_header.dart';
import 'package:aion/core/widgets/app_spinner.dart';
import 'package:aion/core/widgets/app_toast.dart';
import 'package:aion/core/widgets/selection_menu.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';
import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/presentation/cubit/comments_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/comments_state.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_state.dart';
import 'package:aion/features/tickets/presentation/screens/tickets_board_view.dart';
import 'package:aion/features/tickets/presentation/screens/tickets_list_screen.dart';
import 'package:aion/features/tickets/presentation/widgets/inline_editable_field.dart';

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
        if (state is TicketDeleted) {
          context.go('/tickets');
        } else if (state is TicketsError &&
            state.reason == TicketsErrorReason.hasChildren) {
          AppToast.show(
            context,
            context.l10n.ticketDeleteBlockedByChildren(state.childCount ?? 0),
          );
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
                                            StatusIndicator(
                                              status: ticket.status,
                                            ),
                                          ],
                                        ),
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

/// [TicketDetailScreen]'s header `⋮` trigger: opens a small overlay
/// listing "Delete ticket" (the only action today). Same
/// `Overlay`/`LayerLink`/`CompositedTransformFollower`/`mounted`-guard
/// mechanics as [MoveToStatusMenu] (`tickets_board_view.dart`) — a third
/// instance of that pattern, since this is an *action list* rather than a
/// *value picker* like [SelectionMenu], so it isn't built on top of that
/// widget. Selecting "Delete ticket" opens [showAppConfirmDialog]; on
/// confirmation, calls [TicketsCubit.deleteTicket].
class TicketOverflowMenu extends StatefulWidget {
  /// Creates a [TicketOverflowMenu] for [ticket].
  const TicketOverflowMenu({super.key, required this.ticket});

  /// The ticket this menu's actions apply to.
  final Ticket ticket;

  @override
  State<TicketOverflowMenu> createState() => _TicketOverflowMenuState();
}

class _TicketOverflowMenuState extends State<TicketOverflowMenu> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  @override
  void dispose() {
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
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.borderStrong, width: 1),
                  borderRadius: BorderRadius.all(AionRadius.lg),
                  boxShadow: AionShadows.card(c, t.isDark),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 180,
                    maxWidth: 240,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          button: true,
                          label: overlayContext.l10n.ticketDeleteMenuItem,
                          child: GestureDetector(
                            onTap: () {
                              _removeOverlay();
                              _onDeletePressed();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 9,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  PhosphorIcon(
                                    PhosphorIcons.trashLight,
                                    size: 16,
                                    color: c.danger,
                                  ),
                                  const SizedBox(width: AionSpacing.sp8),
                                  Text(
                                    overlayContext.l10n.ticketDeleteMenuItem,
                                    style: AionText.bodySm.copyWith(
                                      color: c.danger,
                                      fontWeight: FontWeight.w600,
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

  Future<void> _onDeletePressed() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: context.l10n.ticketDeleteConfirmTitle,
      message: context.l10n.ticketDeleteConfirmMessage,
      confirmLabel: context.l10n.ticketDeleteConfirmAction,
      isDestructive: true,
    );
    if (confirmed && mounted) {
      context.read<TicketsCubit>().deleteTicket(widget.ticket.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return CompositedTransformTarget(
      link: _layerLink,
      child: Semantics(
        button: true,
        label: context.l10n.ticketDetailOverflowMenuLabel,
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
                borderRadius: BorderRadius.all(AionRadius.iconBtn),
              ),
              child: SizedBox(
                width: 37,
                height: 37,
                child: Center(
                  child: PhosphorIcon(
                    PhosphorIcons.dotsThreeLight,
                    size: 20,
                    color: c.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
