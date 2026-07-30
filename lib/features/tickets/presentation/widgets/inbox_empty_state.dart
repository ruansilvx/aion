// presentation/widgets/inbox_empty_state.dart — InboxEmptyState widget (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';

/// Shown in place of the Inbox history list when no Inbox chat has ever
/// been launched — filled `tray` motif, heading, supporting copy. Purely
/// illustrative, no action button of its own (the launcher above it
/// already is the action), matching the app's other empty-state
/// convention (e.g. Documentation's zero-docs empty state). Per
/// design.md §6.
class InboxEmptyState extends StatelessWidget {
  /// Creates an [InboxEmptyState].
  const InboxEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AionSpacing.sp32,
        horizontal: AionSpacing.sp20,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.primarySubtle,
              shape: BoxShape.circle,
            ),
            child: SizedBox(
              width: 88,
              height: 88,
              child: Center(
                child: PhosphorIcon(
                  PhosphorIcons.trayFill,
                  size: 56,
                  color: c.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: AionSpacing.sp16),
          Text(
            context.l10n.inboxEmptyStateHeading,
            style: AionText.dialogTitle.copyWith(color: c.textPrimary),
          ),
          const SizedBox(height: AionSpacing.sp16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              context.l10n.inboxHistoryEmptyMessage,
              textAlign: TextAlign.center,
              style: AionText.bodySm.copyWith(color: c.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
