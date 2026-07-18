// presentation/widgets/ticket_sync_status_badge.dart — TicketSyncStatusBadge (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sync_status.dart';

/// A small icon+label indicator in the ticket detail header's trailing
/// cluster, showing a `resource`/`page` ticket's [TicketSyncStatus].
/// Non-interactive except for a hover tooltip — a status readout, not a
/// control. Per design.md §2, callers only render this for
/// `resource`/`page` tickets; every other type has no file to fall out
/// of sync with, so this widget doesn't build itself for them.
class TicketSyncStatusBadge extends StatefulWidget {
  /// Creates a [TicketSyncStatusBadge] for [status].
  const TicketSyncStatusBadge({super.key, required this.status});

  /// The sync status to render.
  final TicketSyncStatus status;

  @override
  State<TicketSyncStatusBadge> createState() => _TicketSyncStatusBadgeState();
}

class _TicketSyncStatusBadgeState extends State<TicketSyncStatusBadge> {
  final _layerLink = LayerLink();
  OverlayEntry? _tooltipEntry;

  @override
  void dispose() {
    _hideTooltip();
    super.dispose();
  }

  void _showTooltip(BuildContext context) {
    if (_tooltipEntry != null) return;
    final t = ThemeScope.of(context);
    final message = switch (widget.status) {
      TicketSyncStatus.synced =>
        'File and record agree. Any external edit is already reflected here.',
      TicketSyncStatus.pendingReconcile =>
        'Applying an external edit to this ticket — this takes a moment.',
      TicketSyncStatus.needsRepair =>
        "The file couldn't be parsed after an external edit. Use the "
            'banner below to recover.',
    };

    final entry = OverlayEntry(
      builder: (context) => Positioned(
        child: CompositedTransformFollower(
          link: _layerLink,
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 6),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: t.colors.textPrimary,
                  borderRadius: const BorderRadius.all(AionRadius.md),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF000000).withValues(
                        alpha: t.isDark ? 0.55 : 0.30,
                      ),
                      blurRadius: 30,
                      spreadRadius: -12,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
                  child: Text(
                    message,
                    style: AionText.bodySm.copyWith(
                      height: 1.45,
                      color: t.colors.background,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _tooltipEntry = entry;
    Overlay.of(context).insert(entry);
  }

  void _hideTooltip() {
    _tooltipEntry?.remove();
    _tooltipEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    final (
      IconData icon,
      double iconSize,
      Widget? iconWidget,
      String label,
      Color foreground,
      Color? fill,
      Color? border,
      double gap,
    ) = switch (widget.status) {
      TicketSyncStatus.synced => (
        PhosphorIcons.checkLight,
        14.0,
        null,
        'SYNCED',
        c.textMuted,
        null,
        null,
        6.0,
      ),
      TicketSyncStatus.pendingReconcile => (
        PhosphorIcons.checkLight, // unused — iconWidget overrides below
        12.0,
        const AppSpinner(size: 12),
        'SYNCING',
        c.primary,
        c.pendingTint(t.isDark),
        null,
        7.0,
      ),
      TicketSyncStatus.needsRepair => (
        PhosphorIcons.warningLight,
        12.0,
        null,
        'NEEDS REPAIR',
        c.warning,
        c.needsRepairTint(t.isDark),
        c.needsRepairBorderTint(t.isDark),
        6.0,
      ),
    };

    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: (_) => _showTooltip(context),
        onExit: (_) => _hideTooltip(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            border: border != null ? Border.all(color: border) : null,
            borderRadius: const BorderRadius.all(AionRadius.pill),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              fill == null ? 8 : 9,
              5,
              fill == null ? 10 : 11,
              5,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                iconWidget ??
                    PhosphorIcon(icon, size: iconSize, color: foreground),
                SizedBox(width: gap),
                Text(
                  label,
                  style: AionText.chip.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
