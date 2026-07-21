// presentation/screens/settings_screen.dart — Settings screen (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/providers/domain/enums/agent_model.dart';
import 'package:aion/features/providers/domain/enums/provider_connection_status.dart';
import 'package:aion/features/providers/presentation/cubit/automation_settings_cubit.dart';
import 'package:aion/features/providers/presentation/cubit/automation_settings_state.dart';
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
                child:
                    BlocBuilder<ProviderSettingsCubit, ProviderSettingsState>(
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
                              labelText:
                                  context.l10n.settingsModelDropdownLabel,
                              onChanged: (model) => context
                                  .read<ProviderSettingsCubit>()
                                  .selectModel(model),
                            ),
                            const SizedBox(height: AionSpacing.sp24),
                            const _AutomationSection(),
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

/// The "SDD Stage Automation" section: a labeled description followed by
/// an [AutomationConfidence] [SelectionMenu] (mode dot + name in the
/// trigger, mode dot + sub-label per menu row — design.md §6.2/§6.3),
/// backed by [AutomationSettingsCubit] (kept separate from
/// [ProviderSettingsCubit] since the two concerns — provider connection
/// vs. automation confidence — are unrelated). Built on [SelectionMenu]
/// rather than `AppDropdown` since the mode-dot/sub-label row content
/// design.md specifies needs [SelectionMenu.itemBuilder]; `AppDropdown`
/// only renders a plain label per row.
class _AutomationSection extends StatelessWidget {
  const _AutomationSection();

  String _confidenceLabel(BuildContext context, AutomationConfidence c) =>
      switch (c) {
        AutomationConfidence.auto => context.l10n.settingsAutomationAuto,
        AutomationConfidence.gated => context.l10n.settingsAutomationGated,
        AutomationConfidence.manual => context.l10n.settingsAutomationManual,
      };

  String _confidenceSubLabel(BuildContext context, AutomationConfidence c) =>
      switch (c) {
        AutomationConfidence.auto =>
          context.l10n.settingsAutomationAutoSubLabel,
        AutomationConfidence.gated =>
          context.l10n.settingsAutomationGatedSubLabel,
        AutomationConfidence.manual =>
          context.l10n.settingsAutomationManualSubLabel,
      };

  /// The mode dot's color, encoding the confidence level per design.md
  /// §7's `confidenceDot` resolver — `manual` uses `secondary`
  /// (rendered as a `textSecondary`-weight neutral), the §7 code being
  /// authoritative over §6.2's restated `textSecondary` prose per
  /// proposal.md's Design gate note.
  Color _confidenceDotColor(AionColors c, AutomationConfidence confidence) =>
      switch (confidence) {
        AutomationConfidence.auto => c.success,
        AutomationConfidence.gated => c.primary,
        AutomationConfidence.manual => c.secondary,
      };

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    return BlocBuilder<AutomationSettingsCubit, AutomationSettingsState>(
      builder: (context, state) {
        if (state is! AutomationSettingsReady) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.settingsAutomationLabel,
              style: AionText.label.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: AionSpacing.sp4),
            Text(
              context.l10n.settingsAutomationDescription,
              style: AionText.bodySm.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: AionSpacing.sp8),
            SelectionMenu<AutomationConfidence>(
              semanticsLabel: context.l10n.settingsAutomationLabel,
              items: AutomationConfidence.values,
              itemLabel: (v) => _confidenceLabel(context, v),
              currentValue: state.confidence,
              onSelected: (v) =>
                  context.read<AutomationSettingsCubit>().selectConfidence(v),
              itemBuilder: (context, c, item) => Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: _confidenceDotColor(c, item),
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox(width: 8, height: 8),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      _confidenceLabel(context, item),
                      style: AionText.bodySm.copyWith(color: c.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _confidenceSubLabel(context, item),
                    style: AionText.time.copyWith(color: c.textMuted),
                  ),
                ],
              ),
              trigger: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.border, width: 1),
                  borderRadius: BorderRadius.all(AionRadius.lg),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: _confidenceDotColor(c, state.confidence),
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(width: 8, height: 8),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _confidenceLabel(context, state.confidence),
                          style: AionText.bodySm.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      PhosphorIcon(
                        PhosphorIcons.caretDownLight,
                        size: 12,
                        color: c.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
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
                    : () => context
                          .read<ProviderSettingsCubit>()
                          .testConnection(),
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
            style: AionText.bodySm.copyWith(
              color: c.textSecondary,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}
