// presentation/screens/settings_screen.dart — Settings screen (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/providers/domain/enums/agent_model.dart';
import 'package:aion/features/providers/domain/enums/provider_connection_status.dart';
import 'package:aion/features/providers/presentation/cubit/provider_settings_cubit.dart';
import 'package:aion/features/providers/presentation/cubit/provider_settings_state.dart';
import 'package:aion/features/providers/presentation/widgets/provider_connection_badge.dart';

/// The `/workspace/settings` route: shows the configured provider's
/// connection status (auto-checked on open, with a manual "Test
/// Connection" action) and a model picker. Reached from
/// `WorkspaceNavShell`'s secondary-actions popover. Per
/// `aion-arch/changes/provider-configuration/design.md`'s Settings Screen
/// Component Spec §2.
///
/// The back button returns to `/workspace/tickets`, matching `TrashScreen`'s
/// existing back-button convention (a fixed destination, not a dynamic
/// "wherever the popover was opened from") rather than introducing a new
/// navigation-history mechanism unused elsewhere in the app. The content
/// column reuses the existing `ContentMaxWidth(variant: form)` token (520)
/// rather than the Component Spec's bespoke 560 value — `AionContentWidth`'s
/// own dartdoc says every content-constraining screen uses one of its two
/// values, never a raw number.
class SettingsScreen extends StatelessWidget {
  /// Creates a [SettingsScreen].
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return ColoredBox(
      color: c.background,
      child: Column(
        children: [
          AppHeader(
            title: context.l10n.settingsScreenTitle,
            showBack: true,
            onBack: () => context.go('/workspace/tickets'),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AionSpacing.sp20,
                AionSpacing.sp8,
                AionSpacing.sp20,
                AionSpacing.sp32,
              ),
              child: ContentMaxWidth(
                variant: ContentWidthVariant.form,
                child: BlocBuilder<ProviderSettingsCubit, ProviderSettingsState>(
                  builder: (context, state) {
                    if (state is! ProviderSettingsReady) {
                      return const Center(child: AppSpinner());
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ProviderStatusCard(state: state),
                        const SizedBox(height: AionSpacing.sp24),
                        AppDropdown<AgentModel>(
                          value: state.selectedModel,
                          items: AgentModel.values,
                          itemLabel: (model) => model.label,
                          labelText: context.l10n.settingsModelDropdownLabel,
                          onChanged: (model) =>
                              context.read<ProviderSettingsCubit>().selectModel(
                                model,
                              ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The `surface`-toned panel holding the provider identity, the
/// connection badge, the optional status-message line, and the Test
/// Connection button. Per design.md's Component Spec §3.
class _ProviderStatusCard extends StatelessWidget {
  const _ProviderStatusCard({required this.state});

  final ProviderSettingsReady state;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isChecking = state.status == ProviderConnectionStatus.checking;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border, width: 1),
        borderRadius: BorderRadius.all(AionRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.settingsProviderEyebrow,
                  style: AionText.caption.copyWith(color: c.textMuted),
                ),
                const SizedBox(height: AionSpacing.sp4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.settingsProviderCardTitle,
                        style: AionText.cardTitle.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AionSpacing.sp12),
                    ProviderConnectionBadge(status: state.status),
                  ],
                ),
                const SizedBox(height: AionSpacing.sp4),
                Text(
                  context.l10n.settingsProviderSubline,
                  style: AionText.bodySm.copyWith(color: c.textSecondary),
                ),
              ],
            ),
            if (state.statusMessage != null) ...[
              const SizedBox(height: AionSpacing.sp16),
              _StatusMessageLine(
                message: state.statusMessage!,
                isError: state.status == ProviderConnectionStatus.disconnected,
              ),
            ],
            const SizedBox(height: AionSpacing.sp16),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: context.l10n.settingsTestConnectionButtonLabel,
                variant: AppButtonVariant.secondary,
                onPressed: isChecking
                    ? null
                    : () => context.read<ProviderSettingsCubit>().testConnection(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The status-message row shown beneath the connection badge, only when
/// `ProviderSettingsReady.statusMessage` is non-null — a `disconnected`
/// failure reason ([isError]) or an informational `connected` overage
/// notice. Per design.md's Component Spec §7.
class _StatusMessageLine extends StatelessWidget {
  const _StatusMessageLine({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: PhosphorIcon(
            isError ? PhosphorIcons.warningLight : PhosphorIcons.infoLight,
            size: 13,
            color: c.warning,
          ),
        ),
        const SizedBox(width: AionSpacing.sp8),
        Expanded(
          child: Text(
            message,
            style: AionText.bodySm.copyWith(color: c.textSecondary, height: 1.45),
          ),
        ),
      ],
    );
  }
}
