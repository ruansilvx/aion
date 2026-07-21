// presentation/widgets/provider_connection_badge.dart — ProviderConnectionBadge widget (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/providers/domain/enums/provider_connection_status.dart';

/// A small icon+label status pill showing a [ProviderConnectionStatus],
/// rendered in `SettingsScreen`'s provider status card. Follows
/// `SyncStatusBadge`'s established icon+label pill visual family
/// (`design_system/molecules/sync_status_badge.dart`) but stays
/// feature-local — a one-off status readout for this screen, not yet used
/// anywhere else, so it doesn't meet the design-system promotion bar (see
/// `aion-arch/changes/provider-configuration/design.md` §4.3). Non-
/// interactive (a status readout, not a control): no hover/press/focus
/// treatment.
///
/// The `checking` state reuses [AppSpinner] directly — exactly how
/// `SyncStatusBadge`'s own in-progress state already renders its spinner —
/// rather than a bespoke two-tone `CustomPaint` spinner, per this change's
/// design-sync notes on avoiding a numerically-duplicate implementation.
class ProviderConnectionBadge extends StatelessWidget {
  /// Creates a [ProviderConnectionBadge] for [status].
  const ProviderConnectionBadge({super.key, required this.status});

  /// The connection status to render.
  final ProviderConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    final (
      Widget? iconWidget,
      IconData icon,
      double iconSize,
      String label,
      Color foreground,
      Color? fill,
      Color? border,
      double gap,
      EdgeInsets padding,
    ) = switch (status) {
      ProviderConnectionStatus.unknown => (
        null,
        PhosphorIcons.circleLight,
        13.0,
        context.l10n.settingsProviderStatusUnknown,
        c.textMuted,
        null,
        null,
        6.0,
        const EdgeInsets.fromLTRB(8, 5, 10, 5),
      ),
      ProviderConnectionStatus.checking => (
        const AppSpinner(size: 12),
        PhosphorIcons.circleLight, // unused — iconWidget overrides below
        12.0,
        context.l10n.settingsProviderStatusChecking,
        c.primary,
        c.pendingTint(t.isDark),
        null,
        7.0,
        const EdgeInsets.fromLTRB(9, 5, 11, 5),
      ),
      ProviderConnectionStatus.connected => (
        null,
        PhosphorIcons.sealCheckLight,
        12.0,
        context.l10n.settingsProviderStatusConnected,
        c.success,
        c.connectedTint(t.isDark),
        c.connectedBorderTint(t.isDark),
        6.0,
        const EdgeInsets.fromLTRB(9, 5, 11, 5),
      ),
      ProviderConnectionStatus.disconnected => (
        null,
        PhosphorIcons.warningLight,
        12.0,
        context.l10n.settingsProviderStatusDisconnected,
        c.warning,
        c.disconnectedTint(t.isDark),
        c.disconnectedBorderTint(t.isDark),
        6.0,
        const EdgeInsets.fromLTRB(9, 5, 11, 5),
      ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        border: border != null ? Border.all(color: border) : null,
        borderRadius: const BorderRadius.all(AionRadius.pill),
      ),
      child: Padding(
        padding: padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            iconWidget ??
                PhosphorIcon(icon, size: iconSize, color: foreground),
            SizedBox(width: gap),
            Text(label, style: AionText.chip.copyWith(color: foreground)),
          ],
        ),
      ),
    );
  }
}
