// presentation/screens/settings_screen.dart — Settings screen (presentation layer).

import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, TextInputAction, TextInputType;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/projects/presentation/cubit/baseline_upgrade_cubit.dart';
import 'package:aion/features/projects/presentation/cubit/baseline_upgrade_state.dart';
import 'package:aion/features/providers/domain/enums/agent_model.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/enums/provider_connection_status.dart';
import 'package:aion/features/providers/presentation/cubit/automation_settings_cubit.dart';
import 'package:aion/features/providers/presentation/cubit/automation_settings_state.dart';
import 'package:aion/features/providers/presentation/cubit/execution_context_cap_cubit.dart';
import 'package:aion/features/providers/presentation/cubit/execution_context_cap_state.dart';
import 'package:aion/features/providers/presentation/cubit/model_routing_cubit.dart';
import 'package:aion/features/providers/presentation/cubit/model_routing_state.dart';
import 'package:aion/features/providers/presentation/cubit/provider_settings_cubit.dart';
import 'package:aion/features/providers/presentation/cubit/provider_settings_state.dart';
import 'package:aion/features/providers/presentation/widgets/provider_connection_badge.dart';

/// The `/workspace/settings` route: shows the configured provider's
/// connection status (auto-checked on open, with a manual "Test
/// Connection" action), a model picker, automation-confidence pickers, an
/// "OVERRIDES" section linking to `OverridesListScreen`, and a "BASELINE"
/// section (`_BaselineUpgradeSection`) offering a manual baseline-version
/// upgrade — always available regardless of whether
/// `BaselineUpgradeBanner` has already been shown/declined this session
/// (see `aion-arch/changes/baseline-version-upgrade-flow/design.md` §2).
/// Reached from `WorkspaceNavShell`'s secondary-actions popover. Per
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
                            Text(
                              context.l10n.settingsModelsEyebrow,
                              style: AionText.caption.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _ModelPhaseSection(
                              phase: ModelPhase.frontier,
                              label: context.l10n.settingsModelFrontierLabel,
                              description: context
                                  .l10n
                                  .settingsModelFrontierDescription,
                            ),
                            const SizedBox(height: 20),
                            _ModelPhaseSection(
                              phase: ModelPhase.capable,
                              label: context.l10n.settingsModelCapableLabel,
                              description: context
                                  .l10n
                                  .settingsModelCapableDescription,
                            ),
                            const SizedBox(height: 20),
                            _ModelPhaseSection(
                              phase: ModelPhase.execution,
                              label: context.l10n.settingsModelExecutionLabel,
                              description: context
                                  .l10n
                                  .settingsModelExecutionDescription,
                            ),
                            const SizedBox(height: 20),
                            const _ExecutionContextCapSection(),
                            const SizedBox(height: 22),
                            Text(
                              context.l10n.settingsAutomationEyebrow,
                              style: AionText.caption.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _AutomationSection(
                              automationContext: AutomationContext.sddStage,
                              label: context.l10n.settingsAutomationLabel,
                              description:
                                  context.l10n.settingsAutomationDescription,
                            ),
                            const SizedBox(height: 20),
                            _AutomationSection(
                              automationContext:
                                  AutomationContext.codingExecution,
                              label: context
                                  .l10n
                                  .settingsAutomationCodingExecutionLabel,
                              description: context
                                  .l10n
                                  .settingsAutomationCodingExecutionDescription,
                            ),
                            const SizedBox(height: 20),
                            _AutomationSection(
                              automationContext:
                                  AutomationContext.codingExecutionRetry,
                              label: context
                                  .l10n
                                  .settingsAutomationCodingExecutionRetryLabel,
                              description: context
                                  .l10n
                                  .settingsAutomationCodingExecutionRetryDescription,
                            ),
                            const SizedBox(height: 22),
                            Text(
                              context.l10n.settingsOverridesEyebrow,
                              style: AionText.caption.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const _OverridesSummarySection(),
                            const SizedBox(height: 22),
                            Text(
                              context.l10n.settingsBaselineEyebrow,
                              style: AionText.caption.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const _BaselineUpgradeSection(),
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

/// Localized display label for [confidence]. Module-private since
/// [_AutomationSection]/[_AutomationTrigger]/[_AutomationMenuRow] are its
/// only consumers.
String _confidenceLabel(BuildContext context, AutomationConfidence confidence) =>
    switch (confidence) {
      AutomationConfidence.auto => context.l10n.settingsAutomationAuto,
      AutomationConfidence.gated => context.l10n.settingsAutomationGated,
      AutomationConfidence.manual => context.l10n.settingsAutomationManual,
    };

/// One-line explanatory sub-label for [confidence] under [automationContext],
/// shown in [_AutomationMenuRow]. Per design.md §4.4 — the two instances
/// share option names/mode dots but differ in sub-label copy, since they
/// govern different transitions.
String _confidenceSubLabel(
  BuildContext context,
  AutomationContext automationContext,
  AutomationConfidence confidence,
) => switch (automationContext) {
  AutomationContext.sddStage => switch (confidence) {
    AutomationConfidence.auto => context.l10n.settingsAutomationAutoSubLabel,
    AutomationConfidence.gated =>
      context.l10n.settingsAutomationGatedSubLabel,
    AutomationConfidence.manual =>
      context.l10n.settingsAutomationManualSubLabel,
  },
  AutomationContext.codingExecution => switch (confidence) {
    AutomationConfidence.auto =>
      context.l10n.settingsAutomationCodingExecutionAutoSubLabel,
    AutomationConfidence.gated =>
      context.l10n.settingsAutomationCodingExecutionGatedSubLabel,
    AutomationConfidence.manual =>
      context.l10n.settingsAutomationCodingExecutionManualSubLabel,
  },
  AutomationContext.codingExecutionRetry => switch (confidence) {
    AutomationConfidence.auto =>
      context.l10n.settingsAutomationCodingExecutionRetryAutoSubLabel,
    AutomationConfidence.gated =>
      context.l10n.settingsAutomationCodingExecutionRetryGatedSubLabel,
    AutomationConfidence.manual =>
      context.l10n.settingsAutomationCodingExecutionRetryManualSubLabel,
  },
};

/// The mode dot's color, encoding [confidence] per design.md §7's
/// `confidenceDot` resolver — `manual` uses `secondary` (rendered as a
/// `textSecondary`-weight neutral), the §7 code being authoritative over
/// §6.2's restated `textSecondary` prose per proposal.md's Design gate
/// note.
Color _confidenceDotColor(AionColors c, AutomationConfidence confidence) =>
    switch (confidence) {
      AutomationConfidence.auto => c.success,
      AutomationConfidence.gated => c.primary,
      AutomationConfidence.manual => c.secondary,
    };

/// One automation section — a labeled description followed by an
/// [AutomationConfidence] [SelectionMenu] (mode dot + name in the
/// trigger, mode dot + sub-label per menu row — design.md §4.2–§4.4),
/// backed by [AutomationSettingsCubit] (kept separate from
/// [ProviderSettingsCubit] since the two concerns — provider connection
/// vs. automation confidence — are unrelated). Rendered twice on
/// [SettingsScreen] — once per [AutomationContext] — under one shared
/// "AUTOMATION" eyebrow (design.md §4.1). Built on [SelectionMenu]
/// rather than `AppDropdown` since the mode-dot/sub-label row content
/// design.md specifies needs [SelectionMenu.itemBuilder]; `AppDropdown`
/// only renders a plain label per row.
class _AutomationSection extends StatelessWidget {
  const _AutomationSection({
    required this.automationContext,
    required this.label,
    required this.description,
  });

  /// Which [AutomationContext] this instance controls.
  final AutomationContext automationContext;

  /// This instance's label, per design.md §4.3.
  final String label;

  /// This instance's one-line description, per design.md §4.3.
  final String description;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    return BlocBuilder<AutomationSettingsCubit, AutomationSettingsState>(
      builder: (context, state) {
        if (state is! AutomationSettingsReady) {
          return const SizedBox.shrink();
        }
        final confidence =
            state.confidenceByContext[automationContext] ??
            AutomationConfidence.gated;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AionText.label.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: AionSpacing.sp4),
            Text(
              description,
              style: AionText.bodySm.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: AionSpacing.sp8),
            SelectionMenu<AutomationConfidence>(
              semanticsLabel: label,
              items: AutomationConfidence.values,
              itemLabel: (v) => _confidenceLabel(context, v),
              currentValue: confidence,
              onSelected: (v) => context
                  .read<AutomationSettingsCubit>()
                  .selectConfidence(automationContext, v),
              itemBuilder: (context, c, item) => _AutomationMenuRow(
                automationContext: automationContext,
                confidence: item,
              ),
              trigger: _AutomationTrigger(confidence: confidence),
            ),
          ],
        );
      },
    );
  }
}

/// [SelectionMenu]`<AutomationConfidence>`'s closed trigger: a mode dot,
/// [confidence]'s name, and a trailing caret. Per design.md §6.2.
class _AutomationTrigger extends StatelessWidget {
  const _AutomationTrigger({required this.confidence});

  final AutomationConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border, width: 1),
        borderRadius: BorderRadius.all(AionRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: _confidenceDotColor(c, confidence),
                shape: BoxShape.circle,
              ),
              child: const SizedBox(width: 8, height: 8),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _confidenceLabel(context, confidence),
                style: AionText.bodySm.copyWith(color: c.textPrimary),
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
    );
  }
}

/// One [SelectionMenu]`<AutomationConfidence>` menu row: the mode dot,
/// [confidence]'s name, and a trailing one-line sub-label (per
/// [automationContext] — design.md §4.4). Per design.md §4.4.
class _AutomationMenuRow extends StatelessWidget {
  const _AutomationMenuRow({
    required this.automationContext,
    required this.confidence,
  });

  /// Which [AutomationContext] this row's sub-label copy is for.
  final AutomationContext automationContext;

  final AutomationConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: _confidenceDotColor(c, confidence),
            shape: BoxShape.circle,
          ),
          child: const SizedBox(width: 8, height: 8),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            _confidenceLabel(context, confidence),
            style: AionText.bodySm.copyWith(color: c.textPrimary),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _confidenceSubLabel(context, automationContext, confidence),
          style: AionText.time.copyWith(color: c.textMuted),
        ),
      ],
    );
  }
}

/// One "MODELS" section row — a labeled description followed by an
/// `AppDropdown<AgentModel>` picking which model handles [phase]'s model
/// calls, backed by [ModelRoutingCubit]. Rendered three times on
/// [SettingsScreen] — once per [ModelPhase] — under one shared "MODELS"
/// eyebrow, mirroring how [_AutomationSection] is rendered twice under
/// "AUTOMATION". Reuses the plain `AppDropdown<AgentModel>` the old
/// single-model picker already used — no mode-dot treatment, unlike
/// [_AutomationTrigger]/[_AutomationMenuRow], since a model has no mode
/// color. Added for
/// `aion-arch/changes/per-phase-tier-based-model-routing`.
class _ModelPhaseSection extends StatelessWidget {
  const _ModelPhaseSection({
    required this.phase,
    required this.label,
    required this.description,
  });

  /// Which [ModelPhase] this instance's dropdown routes.
  final ModelPhase phase;

  /// This instance's label.
  final String label;

  /// This instance's one-line description of what [phase] drives.
  final String description;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    return BlocBuilder<ModelRoutingCubit, ModelRoutingState>(
      builder: (context, state) {
        if (state is! ModelRoutingReady) {
          return const SizedBox.shrink();
        }
        final model = state.modelByPhase[phase] ?? AgentModel.sonnet;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AionText.label.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: AionSpacing.sp4),
            Text(
              description,
              style: AionText.bodySm.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: AionSpacing.sp8),
            AppDropdown<AgentModel>(
              value: model,
              items: AgentModel.values,
              itemLabel: (m) => m.label,
              semanticsLabel: label,
              onChanged: (m) => context
                  .read<ModelRoutingCubit>()
                  .selectModel(phase, m),
            ),
          ],
        );
      },
    );
  }
}

/// The "MODELS" group's fourth row — a numeric override for the
/// coding-execution context-window handoff cap, backed by
/// [ExecutionContextCapCubit]. Rendered once, directly below the
/// Execution Model [_ModelPhaseSection] row (same shared "MODELS"
/// eyebrow). Its label/description geometry is byte-identical to
/// [_ModelPhaseSection]'s so it reads as one more MODELS row; its input
/// is the existing [AppTextField] atom (digits-only, numeric keyboard);
/// its helper line below the field is the field's sole feedback channel
/// — neutral ("Effective cap: N tokens"), an `OVERRIDE` pill when a valid
/// override is set, or a caution chip when the live entry would be
/// clamped to just under the model's real limit. Per design.md
/// "Execution Context Cap: Settings Component Spec" §1-§2 (some spacing
/// values below are not multiples of 4, per the design gate's explicit
/// note in proposal.md — implemented as specified rather than rounded to
/// the nearest [AionSpacing] token). Uses [AionColorsHubTokens]'s
/// existing `needsRepairTint`/`needsRepairBorderTint` for the clamp
/// chip's fill/border (not new `warningTint`/`warningBorderTint`
/// helpers — see proposal.md's design gate). Added for
/// `aion-arch/changes/dont-spawn-new-chat-ticket-per-execution-trigger`.
class _ExecutionContextCapSection extends StatefulWidget {
  /// Creates an [_ExecutionContextCapSection].
  const _ExecutionContextCapSection();

  @override
  State<_ExecutionContextCapSection> createState() =>
      _ExecutionContextCapSectionState();
}

class _ExecutionContextCapSectionState
    extends State<_ExecutionContextCapSection> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    // Rebuilds on every keystroke so the helper row (derived live from
    // `_controller.text`, never stored — design.md §2.4) tracks what's
    // being typed before it's committed.
    _controller.addListener(() => setState(() {}));
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _commit(_controller.text);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commit(String value) {
    context.read<ExecutionContextCapCubit>().setOverride(
      int.tryParse(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return BlocBuilder<ExecutionContextCapCubit, ExecutionContextCapState>(
      builder: (context, state) {
        if (state is! ExecutionContextCapReady) {
          return const SizedBox.shrink();
        }

        final expected = state.overrideTokens?.toString() ?? '';
        if (!_seeded) {
          _seeded = true;
          _controller.text = expected;
        } else if (!_focusNode.hasFocus && _controller.text != expected) {
          // Re-syncs after a commit clamps (or clears) the value — only
          // when not actively focused, so a live keystroke is never
          // overwritten mid-edit.
          _controller.text = expected;
        }

        final limit = state.modelDefaultTokens;
        final text = _controller.text;
        final parsed = int.tryParse(text);
        final isClamped = parsed != null && parsed >= limit;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.settingsExecutionContextCapLabel,
              style: AionText.label.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.settingsExecutionContextCapDescription,
              style: AionText.bodySm.copyWith(
                color: c.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            AppTextField(
              controller: _controller,
              focusNode: _focusNode,
              hintText: limit.toString(),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLines: 1,
              textInputAction: TextInputAction.done,
              onSubmitted: _commit,
            ),
            SizedBox(height: isClamped ? 6 : 8),
            _ExecutionContextCapHelperRow(
              text: text,
              parsed: parsed,
              limit: limit,
              isClamped: isClamped,
            ),
          ],
        );
      },
    );
  }
}

/// The dynamic helper row below [_ExecutionContextCapSection]'s field —
/// exactly one of three variants per build, chosen from [text]/[isClamped]
/// vs. [limit] (design.md §2.4/§6.1): neutral (no override), an
/// `OVERRIDE`-tagged effective-cap line (a valid override), or a caution
/// chip (the live entry would be clamped). Added for
/// `aion-arch/changes/dont-spawn-new-chat-ticket-per-execution-trigger`.
class _ExecutionContextCapHelperRow extends StatelessWidget {
  /// Creates an [_ExecutionContextCapHelperRow] for the live field
  /// [text]/[parsed] against the model's real [limit], with [isClamped]
  /// (computed once by [_ExecutionContextCapSectionState], which also uses
  /// it for the field-to-helper-row spacing) passed in rather than
  /// re-derived here, so the two can never disagree.
  const _ExecutionContextCapHelperRow({
    required this.text,
    required this.parsed,
    required this.limit,
    required this.isClamped,
  });

  /// The field's live, uncommitted text.
  final String text;

  /// `int.tryParse(text)` — `null` for empty/unparseable text (the
  /// digits-only input formatter makes the latter unreachable in
  /// practice).
  final int? parsed;

  /// The execution-phase model's real `AgentModel.contextWindowTokens`.
  final int limit;

  /// Whether [parsed] is at or above [limit] — the live entry would be
  /// clamped on commit.
  final bool isClamped;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final numberFormat = NumberFormat.decimalPattern();

    if (text.isEmpty) {
      return Text(
        context.l10n.settingsExecutionContextCapEffective(
          numberFormat.format(limit),
        ),
        style: AionText.bodySm.copyWith(fontSize: 13, color: c.textMuted),
      );
    }

    if (!isClamped && parsed != null && parsed! >= 1) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              context.l10n.settingsExecutionContextCapEffective(
                numberFormat.format(parsed),
              ),
              style: AionText.bodySm.copyWith(
                fontSize: 13,
                color: c.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.primarySubtle,
              borderRadius: BorderRadius.all(AionRadius.pill),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 2,
              ),
              child: Text(
                context.l10n.settingsExecutionContextCapOverrideTag,
                style: AionText.caption.copyWith(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: c.primary,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Clamped / would-be-invalid — a value at or above the model's real
    // limit. `parsed == null` here is unreachable given non-empty `text`
    // and the digits-only formatter, but this branch is still the safe
    // fallback rather than a thrown assertion.
    final clampedTo = limit - 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.needsRepairTint(t.isDark),
        border: Border.all(
          color: c.needsRepairBorderTint(t.isDark),
          width: 1,
        ),
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.warning,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: Center(
                    child: Text(
                      '!',
                      style: AionText.label.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: c.background,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.settingsExecutionContextCapClampWarning(
                  numberFormat.format(limit),
                  numberFormat.format(clampedTo),
                ),
                style: AionText.bodySm.copyWith(
                  fontSize: 12.5,
                  height: 1.45,
                  color: c.warningText(t.isDark),
                ),
              ),
            ),
          ],
        ),
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

/// "OVERRIDES" section on [SettingsScreen] — a short summary plus a
/// button into `OverridesListScreen`, where a user browses every
/// baseline skill/convention asset for the active project and edits a
/// plain-text local override for any one of them.
class _OverridesSummarySection extends StatelessWidget {
  const _OverridesSummarySection();

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.settingsOverridesSummary,
          style: AionText.bodySm.copyWith(color: c.textMuted, height: 1.5),
        ),
        const SizedBox(height: AionSpacing.sp8),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: context.l10n.settingsOverridesManageButton,
            variant: AppButtonVariant.secondary,
            icon: PhosphorIcons.stackLight,
            onPressed: () => context.go('/workspace/settings/overrides'),
          ),
        ),
      ],
    );
  }
}

/// "BASELINE" section on [SettingsScreen] — a description, the active
/// project's currently pinned baseline version, and a manual upgrade
/// action, mirroring [_OverridesSummarySection]'s shape. Always present
/// regardless of whether `BaselineUpgradeBanner` has already been
/// shown/declined this session. Added for
/// `aion-arch/changes/baseline-version-upgrade-flow`.
class _BaselineUpgradeSection extends StatelessWidget {
  const _BaselineUpgradeSection();

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    return BlocBuilder<BaselineUpgradeCubit, BaselineUpgradeState>(
      builder: (context, state) {
        if (state is! BaselineUpgradeReady) {
          return const Center(child: AppSpinner());
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.settingsBaselineDescription,
              style: AionText.bodySm.copyWith(color: c.textMuted, height: 1.5),
            ),
            const SizedBox(height: 10),
            _CurrentVersionRow(version: state.currentVersion),
            const SizedBox(height: 10),
            if (state.isUpToDate)
              _UpToDateMessage(colors: c)
            else if (state.isUpgrading)
              const _BaselineUpgradingButton()
            else
              _BaselineUpgradeButton(
                label: context.l10n.settingsBaselineUpgradeButton(
                  'v${state.latestVersion}',
                ),
                onTap: () => context.read<BaselineUpgradeCubit>().upgrade(),
              ),
          ],
        );
      },
    );
  }
}

/// The "Current version" row inside [_BaselineUpgradeSection], showing
/// the active project's pinned baseline version.
class _CurrentVersionRow extends StatelessWidget {
  const _CurrentVersionRow({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: const BorderRadius.all(Radius.circular(11)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              context.l10n.settingsBaselineCurrentVersionLabel,
              style: AionText.label.copyWith(
                fontSize: 12,
                color: c.textSecondary,
              ),
            ),
            Text(
              'v$version',
              style: AionText.key.copyWith(
                fontSize: 13.5,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The enabled "Upgrade to vX.Y.Z" action inside [_BaselineUpgradeSection]
/// — hand-rolled rather than [AppButton] because design.md §2.2 specifies
/// a `primary`-colored leading icon, which [AppButton]'s secondary
/// variant can't produce (its icon always matches the label color).
/// Mirrors the hover/press treatment `CodebaseAnalysisBanner`'s
/// `_DepthChoiceButton` already hand-rolls for the same kind of
/// AppButton-capability gap.
class _BaselineUpgradeButton extends StatefulWidget {
  /// Creates a [_BaselineUpgradeButton] labeled [label], calling [onTap]
  /// when activated.
  const _BaselineUpgradeButton({required this.label, required this.onTap});

  /// The button's text label (e.g. "Upgrade to v0.3.0").
  final String label;

  /// Called when the button is activated.
  final VoidCallback onTap;

  @override
  State<_BaselineUpgradeButton> createState() =>
      _BaselineUpgradeButtonState();
}

class _BaselineUpgradeButtonState extends State<_BaselineUpgradeButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    final fill = _isPressed
        ? c.surface
        : (_isHovered
              ? Color.alphaBlend(
                  c.primary.withValues(alpha: 0.06),
                  c.surfaceHover,
                )
              : c.surfaceHover);
    final border = _isHovered
        ? c.primary.withValues(alpha: t.isDark ? 0.30 : 0.20)
        : c.borderStrong;

    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          child: AnimatedScale(
            scale: _isPressed ? 0.98 : 1.0,
            duration: const Duration(milliseconds: 80),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                border: Border.all(color: border),
                borderRadius: const BorderRadius.all(AionRadius.md),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PhosphorIcon(
                      PhosphorIcons.arrowUpLight,
                      size: 16,
                      color: c.primary,
                    ),
                    const SizedBox(width: 9),
                    Text(
                      widget.label,
                      style: AionText.button.copyWith(color: c.textPrimary),
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

/// The non-interactive, spinner-labeled "Upgrading…" state
/// [_BaselineUpgradeSection] shows in place of
/// [_BaselineUpgradeButton] while an upgrade is in flight — same
/// footprint as [_BaselineUpgradeButton] so the section doesn't reflow,
/// per design.md §2.3.
class _BaselineUpgradingButton extends StatelessWidget {
  const _BaselineUpgradingButton();

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceHover,
        border: Border.all(color: c.border),
        borderRadius: const BorderRadius.all(AionRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 14, height: 14, child: AppSpinner(size: 14)),
            const SizedBox(width: 9),
            Text(
              context.l10n.settingsBaselineUpgradingLabel,
              style: AionText.button.copyWith(color: c.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// The quiet "up to date" message [_BaselineUpgradeSection] shows in
/// place of an upgrade action when there's nothing to upgrade to.
class _UpToDateMessage extends StatelessWidget {
  const _UpToDateMessage({required this.colors});

  final AionColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PhosphorIcon(
          PhosphorIcons.checkLight,
          size: 16,
          color: colors.success,
        ),
        const SizedBox(width: AionSpacing.sp8),
        Text(
          context.l10n.settingsBaselineUpToDateMessage,
          style: AionText.bodySm.copyWith(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
      ],
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
