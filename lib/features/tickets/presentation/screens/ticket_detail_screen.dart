import 'package:flutter/material.dart' show Material, MaterialType, TextField, InputDecoration;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/theme/aion_colors.dart';
import 'package:aion/core/theme/aion_radius.dart';
import 'package:aion/core/theme/aion_shadows.dart';
import 'package:aion/core/theme/aion_text.dart';
import 'package:aion/core/theme/theme_scope.dart';
import 'package:aion/core/widgets/app_header.dart';
import 'package:aion/core/widgets/app_spinner.dart';
import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';
import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';
import 'package:aion/features/tickets/presentation/cubit/comments_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/comments_state.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_state.dart';
import 'package:aion/features/tickets/presentation/screens/tickets_list_screen.dart';

class TicketDetailScreen extends StatefulWidget {
  const TicketDetailScreen({super.key, required this.ticketId});

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
    context.read<CommentsCubit>().addComment(ticketId: widget.ticketId, content: content);
    _commentController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return ColoredBox(
      color: c.background,
      child: Column(
        children: [
          BlocBuilder<TicketsCubit, TicketsState>(
            builder: (context, state) {
              final title = state is TicketDetailLoaded ? state.ticket.ticketId : '…';
              return AppHeader(
                title: title,
                showBack: true,
                onBack: () => context.go('/tickets'),
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                trailing: PhosphorIcon(
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
                                TicketsLoading() => const Center(child: AppSpinner()),
                                TicketsError(:final message) => Text(
                                    message,
                                    style: AionText.body.copyWith(color: c.danger),
                                  ),
                                TicketDetailLoaded(:final ticket) => Semantics(
                                    header: true,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        PriorityBadge(priority: ticket.priority, isRow: false),
                                        const SizedBox(height: AionSpacing.sp8),
                                        Text(
                                          ticket.title,
                                          style: AionText.h2.copyWith(color: c.textPrimary),
                                        ),
                                        const SizedBox(height: AionSpacing.sp12),
                                        Row(
                                          children: [
                                            TypeChip(type: ticket.type, isRow: false),
                                            const SizedBox(width: AionSpacing.sp8),
                                            StatusIndicator(status: ticket.status),
                                          ],
                                        ),
                                        const SizedBox(height: AionSpacing.sp16),
                                        if (ticket.description != null) ...[
                                          Container(color: c.border, height: 1),
                                          const SizedBox(height: AionSpacing.sp16),
                                          Text(
                                            'DESCRIPTION',
                                            style: AionText.caption.copyWith(color: c.textMuted),
                                          ),
                                          const SizedBox(height: AionSpacing.sp8),
                                          Text(
                                            ticket.description!,
                                            style: AionText.body.copyWith(color: c.textSecondary),
                                          ),
                                        ],
                                        const SizedBox(height: AionSpacing.sp8),
                                        Text(
                                          'Created ${_formatDate(ticket.createdAt)}',
                                          style: AionText.time.copyWith(color: c.textMuted),
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
                                CommentsLoading() => const Center(child: AppSpinner()),
                                CommentsError(:final message) => Text(
                                    message,
                                    style: AionText.body.copyWith(color: c.danger),
                                  ),
                                CommentsLoaded(:final comments) ||
                                CommentAdding(:final comments) ||
                                CommentAdded(:final comments) =>
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'COMMENTS · ${comments.length}',
                                        style: AionText.caption.copyWith(color: c.textMuted),
                                      ),
                                      const SizedBox(height: AionSpacing.sp12),
                                      ListView.builder(
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        itemCount: comments.length,
                                        itemBuilder: (context, index) =>
                                            CommentTile(comment: comments[index]),
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
                          decoration: BoxDecoration(color: c.secondary, shape: BoxShape.circle),
                          child: SizedBox(
                            width: 34,
                            height: 34,
                            child: Center(
                              child: Text(
                                'U',
                                style: AionText.key.copyWith(color: const Color(0xFFFFFFFF)),
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
                              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                              child: Material(
                                type: MaterialType.transparency,
                                child: TextField(
                                  controller: _commentController,
                                  maxLines: 1,
                                  style: AionText.bodySm.copyWith(color: c.textPrimary, fontSize: 13),
                                  decoration: InputDecoration.collapsed(
                                    hintText: 'Add a comment…',
                                    hintStyle: AionText.bodySm.copyWith(color: c.textMuted, fontSize: 13),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Semantics(
                          button: true,
                          label: 'Send comment',
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
                                    color: const Color(0xFFFFFFFF), // white glyph
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
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class CommentTile extends StatelessWidget {
  const CommentTile({super.key, required this.comment});

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
                          'Aion AI',
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
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Text('AI', style: AionText.prioritySm.copyWith(color: c.primary)),
                          ),
                        ),
                      ] else
                        Text(
                          'You',
                          style: AionText.cardTitle.copyWith(
                            fontSize: 12.5,
                            color: c.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      const Spacer(),
                      Text(_formatTime(comment.createdAt), style: AionText.time.copyWith(color: c.textMuted)),
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
                        color: isAi ? c.primary.withOpacity(t.isDark ? 0.42 : 0.28) : c.border,
                        width: 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                    Text('via ${comment.aiModel}', style: AionText.time.copyWith(color: c.textMuted)),
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
          child: Text('U', style: AionText.prioritySm.copyWith(color: const Color(0xFFFFFFFF))),
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
