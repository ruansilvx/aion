// presentation/widgets/notification_dropdown.dart — NotificationDropdownPanel widget (presentation layer).

import 'dart:async';

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart' hide Notification;
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/localization/context_localizations_x.dart';
import 'package:aion/core/utils/relative_time_format.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/notification.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';

/// The notification-center dropdown's panel content: header (title +
/// "Mark all read"), a scrollable list of [TicketsCubit.getRecentNotifications]
/// rows, or the empty state when there are none. Rendered inside an
/// [OverlayEntry] by `_NotificationBellTrigger` (`workspace_nav_shell.dart`),
/// mirroring `TicketOverflowMenu`'s `Overlay`/`LayerLink`/
/// `CompositedTransformFollower`/`mounted`-guard mechanics — this widget
/// itself is just the panel body, not the overlay plumbing (that lives on
/// the trigger's `State`, same split `TicketOverflowMenu`'s own root-menu
/// content vs. trigger `State` uses). Added for
/// `AIO-1586`; see that
/// change's design.md §6.2 and Component Spec §4-§7.
class NotificationDropdownPanel extends StatefulWidget {
  /// Creates a [NotificationDropdownPanel]. [ticketsCubit] is passed in
  /// (not read via `context.read` inside this widget) because — like
  /// [TicketOverflowMenu]'s own overlay content — this panel is mounted
  /// inside an [OverlayEntry], outside the route's provider scope.
  /// [onDismiss] closes the overlay (called after a row navigates, or the
  /// panel requests to close itself).
  const NotificationDropdownPanel({
    super.key,
    required this.ticketsCubit,
    required this.onDismiss,
  });

  /// The cubit this panel reads/writes notifications through.
  final TicketsCubit ticketsCubit;

  /// Closes the hosting overlay.
  final VoidCallback onDismiss;

  @override
  State<NotificationDropdownPanel> createState() =>
      _NotificationDropdownPanelState();
}

class _NotificationDropdownPanelState
    extends State<NotificationDropdownPanel> {
  /// `null` while the initial load is in flight.
  List<Notification>? _notifications;

  /// One [FocusNode] per row in [_notifications], indexed the same way —
  /// lets [_moveRowFocus] move keyboard focus explicitly between rows
  /// (design.md Component Spec §9: "arrow keys move row focus"), rather
  /// than relying on default 2D directional-focus heuristics across an
  /// `Overlay` boundary. Kept in sync with [_notifications]'s length by
  /// [_syncRowFocusNodes], called once per [build].
  final List<FocusNode> _rowFocusNodes = [];

  /// The index of [_rowFocusNodes] that currently holds focus, if any —
  /// updated by each node's own focus listener (added in
  /// [_syncRowFocusNodes]) so [_moveRowFocus] knows where to move from
  /// even when focus arrived via Tab rather than an arrow key.
  int? _focusedRowIndex;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final node in _rowFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// Grows/shrinks [_rowFocusNodes] to match [count], disposing any
  /// removed nodes. Idempotent — safe to call on every [build].
  void _syncRowFocusNodes(int count) {
    while (_rowFocusNodes.length < count) {
      final index = _rowFocusNodes.length;
      final node = FocusNode(debugLabel: 'notification-row-$index');
      node.addListener(() {
        if (node.hasFocus) setState(() => _focusedRowIndex = index);
      });
      _rowFocusNodes.add(node);
    }
    while (_rowFocusNodes.length > count) {
      _rowFocusNodes.removeLast().dispose();
      if (_focusedRowIndex != null && _focusedRowIndex! >= count) {
        _focusedRowIndex = null;
      }
    }
  }

  /// Moves keyboard focus by [delta] rows (`1` down, `-1` up), clamped
  /// to the list bounds rather than wrapping — entering from no focus at
  /// all lands on the first row for a downward move, the last row for
  /// an upward one.
  void _moveRowFocus(int delta) {
    if (_rowFocusNodes.isEmpty) return;
    final current = _focusedRowIndex;
    final next = current == null
        ? (delta > 0 ? 0 : _rowFocusNodes.length - 1)
        : (current + delta).clamp(0, _rowFocusNodes.length - 1);
    _rowFocusNodes[next].requestFocus();
  }

  Future<void> _load() async {
    final notifications = await widget.ticketsCubit.getRecentNotifications();
    if (!mounted) return;
    setState(() => _notifications = notifications);
  }

  /// Marks [notification] read locally (immediate visual feedback — the
  /// dot fades and the title dims without waiting for a full reload) and
  /// persists it via [TicketsCubit.markNotificationRead].
  void _markReadLocally(Notification notification) {
    final current = _notifications;
    if (current == null) return;
    setState(() {
      _notifications = [
        for (final n in current)
          if (n.id == notification.id)
            Notification(
              id: n.id,
              ticketId: n.ticketId,
              ticketKey: n.ticketKey,
              ticketTitle: n.ticketTitle,
              kind: n.kind,
              message: n.message,
              createdAt: n.createdAt,
              readAt: n.readAt ?? DateTime.now(),
            )
          else
            n,
      ];
    });
    unawaited(widget.ticketsCubit.markNotificationRead(notification.id));
  }

  void _markAllReadLocally() {
    final current = _notifications;
    if (current == null || current.every((n) => !n.isUnread)) return;
    final now = DateTime.now();
    setState(() {
      _notifications = [
        for (final n in current)
          Notification(
            id: n.id,
            ticketId: n.ticketId,
            ticketKey: n.ticketKey,
            ticketTitle: n.ticketTitle,
            kind: n.kind,
            message: n.message,
            createdAt: n.createdAt,
            readAt: n.readAt ?? now,
          ),
      ];
    });
    unawaited(widget.ticketsCubit.markAllNotificationsRead());
  }

  void _onRowTap(Notification notification) {
    _markReadLocally(notification);
    context.go('/workspace/tickets/${notification.ticketId}');
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final notifications = _notifications;
    final hasUnread = notifications?.any((n) => n.isUnread) ?? false;
    _syncRowFocusNodes(notifications?.length ?? 0);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _moveRowFocus(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _moveRowFocus(-1),
        const SingleActivator(LogicalKeyboardKey.escape): widget.onDismiss,
      },
      child: Focus(
        autofocus: true,
        // Focusable but not itself an activation target — arrow
        // keys/Escape need somewhere to land on open, before any row
        // has been explicitly focused.
        skipTraversal: true,
        canRequestFocus: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.borderStrong, width: 1),
            borderRadius: BorderRadius.all(AionRadius.lg),
            boxShadow: AionShadows.card(c, t.isDark),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.all(AionRadius.lg),
            child: SizedBox(
              width: 360,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _NotificationDropdownHeader(
                      hasUnread: hasUnread,
                      onMarkAllRead: _markAllReadLocally,
                    ),
                    Flexible(
                      child: notifications == null
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 32),
                              child: Center(child: AppSpinner()),
                            )
                          : notifications.isEmpty
                          ? const _NotificationDropdownEmptyState()
                          : SingleChildScrollView(
                              primary: false,
                              physics: const ClampingScrollPhysics(),
                              child: Column(
                                children: [
                                  for (
                                    var i = 0;
                                    i < notifications.length;
                                    i++
                                  )
                                    _NotificationDropdownRow(
                                      notification: notifications[i],
                                      showDivider:
                                          i < notifications.length - 1,
                                      focusNode: _rowFocusNodes[i],
                                      onTap: () => _onRowTap(notifications[i]),
                                    ),
                                ],
                              ),
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

/// The panel's fixed header strip: title + "Mark all read". Per design.md
/// Component Spec §5.
class _NotificationDropdownHeader extends StatelessWidget {
  const _NotificationDropdownHeader({
    required this.hasUnread,
    required this.onMarkAllRead,
  });

  /// Whether at least one notification is currently unread — drives
  /// "Mark all read"'s enabled/disabled treatment.
  final bool hasUnread;

  final VoidCallback onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border, width: 1)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 12, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                context.l10n.notificationCenterTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AionText.cardTitle.copyWith(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _MarkAllReadButton(enabled: hasUnread, onTap: onMarkAllRead),
          ],
        ),
      ),
    );
  }
}

/// The header's "Mark all read" ghost text action. Per design.md
/// Component Spec §5.2 — disabled (not hidden) at zero unread, so the
/// header layout never shifts.
class _MarkAllReadButton extends StatefulWidget {
  const _MarkAllReadButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_MarkAllReadButton> createState() => _MarkAllReadButtonState();
}

class _MarkAllReadButtonState extends State<_MarkAllReadButton> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    if (!widget.enabled) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          context.l10n.notificationCenterMarkAllRead,
          style: AionText.bodySm.copyWith(
            color: c.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final fill = _isPressed || _isHovered
        ? c.surfaceHover
        : const Color(0x00000000);
    final boxShadow = _isFocused
        ? AionShadows.focus(c, t.isDark)
        : const <BoxShadow>[];

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: FocusableActionDetector(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        onShowFocusHighlight: (value) => setState(() => _isFocused = value),
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          child: AnimatedScale(
            scale: _isPressed ? 0.98 : 1.0,
            duration: const Duration(milliseconds: 90),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.all(AionRadius.sm),
                boxShadow: boxShadow,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                child: Text(
                  context.l10n.notificationCenterMarkAllRead,
                  style: AionText.bodySm.copyWith(
                    color: c.primary,
                    fontWeight: FontWeight.w600,
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

/// One notification row: leading outcome tile, ticket title + message,
/// trailing relative timestamp + unread dot. Per design.md Component Spec
/// §6.
class _NotificationDropdownRow extends StatefulWidget {
  const _NotificationDropdownRow({
    required this.notification,
    required this.showDivider,
    required this.focusNode,
    required this.onTap,
  });

  final Notification notification;

  /// Whether to render the bottom hairline separator — `false` for the
  /// last row in the list.
  final bool showDivider;

  /// Owned by [_NotificationDropdownPanelState] (one per row, indexed to
  /// match), so [_NotificationDropdownPanelState._moveRowFocus] can move
  /// keyboard focus onto this row explicitly, per design.md Component
  /// Spec §9's arrow-key row navigation.
  final FocusNode focusNode;

  final VoidCallback onTap;

  @override
  State<_NotificationDropdownRow> createState() =>
      _NotificationDropdownRowState();
}

class _NotificationDropdownRowState extends State<_NotificationDropdownRow> {
  bool _isHovered = false;
  bool _isFocused = false;

  /// The outcome tile's glyph + accent color for [kind]. Per design.md
  /// Component Spec §0.4.
  static (IconData, Color Function(AionColors)) _iconAndAccent(
    NotificationKind kind,
  ) => switch (kind) {
    NotificationKind.executionPrOpened => (
      PhosphorIcons.gitPullRequestLight,
      (c) => c.success,
    ),
    NotificationKind.executionVerificationFailed => (
      PhosphorIcons.warningLight,
      (c) => c.danger,
    ),
    NotificationKind.executionFailed => (
      PhosphorIcons.xCircleLight,
      (c) => c.danger,
    ),
    NotificationKind.stageAdvanceCompleted => (
      PhosphorIcons.arrowRightLight,
      (c) => c.primary,
    ),
    NotificationKind.stageAdvanceFailed => (
      PhosphorIcons.warningCircleLight,
      (c) => c.warning,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final n = widget.notification;
    final (icon, accentOf) = _iconAndAccent(n.kind);
    final accent = accentOf(c);
    final isUnread = n.isUnread;

    final fill = _isHovered ? c.surfaceHover : c.surface;
    final boxShadow = _isFocused
        ? AionShadows.focus(c, t.isDark)
        : const <BoxShadow>[];

    return DecoratedBox(
      decoration: BoxDecoration(
        border: widget.showDivider
            ? Border(bottom: BorderSide(color: c.border, width: 1))
            : null,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: FocusableActionDetector(
          focusNode: widget.focusNode,
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap();
                return null;
              },
            ),
          },
          onShowFocusHighlight: (value) => setState(() => _isFocused = value),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              decoration: BoxDecoration(color: fill, boxShadow: boxShadow),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Opacity(
                      opacity: isUnread ? 1.0 : 0.7,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.outcomeTileFill(accent, t.isDark),
                          borderRadius: BorderRadius.all(
                            AionRadius.iconBtnSm,
                          ),
                        ),
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: Center(
                            child: PhosphorIcon(
                              icon,
                              size: 16,
                              color: accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AionSpacing.sp12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n.ticketTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AionText.cardTitle.copyWith(
                              color: isUnread
                                  ? c.textPrimary
                                  : c.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text.rich(
                            TextSpan(
                              children: [
                                if (n.ticketKey.isNotEmpty) ...[
                                  TextSpan(
                                    text: n.ticketKey,
                                    style: AionText.key.copyWith(
                                      color: c.textSecondary,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' · ',
                                    style: AionText.breadcrumb.copyWith(
                                      color: c.textMuted,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                                TextSpan(
                                  text: n.message,
                                  style: AionText.breadcrumb.copyWith(
                                    color: c.textMuted,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AionSpacing.sp8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatRelativeTime(n.createdAt),
                          style: AionText.time.copyWith(color: c.textMuted),
                        ),
                        const SizedBox(height: 6),
                        if (isUnread)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const SizedBox(width: 8, height: 8),
                          ),
                      ],
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

/// Shown when the recent-notifications list is empty. Per design.md
/// Component Spec §7, mirroring [InboxEmptyState]'s existing muted
/// icon + heading + subtitle pattern.
class _NotificationDropdownEmptyState extends StatelessWidget {
  const _NotificationDropdownEmptyState();

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 200),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              PhosphorIcon(
                PhosphorIcons.bellSimpleLight,
                size: 28,
                color: c.textMuted,
              ),
              const SizedBox(height: AionSpacing.sp12),
              Text(
                context.l10n.notificationCenterEmptyState,
                style: AionText.bodySm.copyWith(
                  color: c.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AionSpacing.sp12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  context.l10n.notificationCenterEmptyStateSubtitle,
                  textAlign: TextAlign.center,
                  style: AionText.breadcrumb.copyWith(color: c.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
