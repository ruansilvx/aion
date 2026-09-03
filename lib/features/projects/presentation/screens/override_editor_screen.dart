// presentation/screens/override_editor_screen.dart — Override editor screen (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/projects/presentation/cubit/override_editor_cubit.dart';
import 'package:aion/features/projects/presentation/cubit/override_editor_state.dart';

/// Which text [OverrideEditorScreen] was opened on — drives the status line's
/// copy/color (§3.2) and the Save button's label (§3.4). No stored override →
/// [editingDefault]. A view-model enum, per AIO-1654 §5 — carries no design
/// tokens of its own.
enum OverrideEditorMode {
  /// The editor opened on an existing project-local override.
  editingOverride,

  /// The editor opened on the bundled default — no override exists yet
  /// for this asset; saving creates one.
  editingDefault,
}

/// The `/workspace/settings/overrides/:assetKey` route: a full-page plain
/// multi-line editor for one baseline asset's project-local override —
/// its existing override content if one exists, otherwise the bundled
/// default (saving in that case creates a new override). Reached by
/// tapping a row on `OverridesListScreen`.
class OverrideEditorScreen extends StatefulWidget {
  /// Creates an [OverrideEditorScreen] for [assetKey].
  const OverrideEditorScreen({super.key, required this.assetKey});

  /// The `BaselineAsset.key` being edited.
  final String assetKey;

  @override
  State<OverrideEditorScreen> createState() => _OverrideEditorScreenState();
}

class _OverrideEditorScreenState extends State<OverrideEditorScreen> {
  final _controller = TextEditingController();

  /// The content last loaded/saved — compared against [_controller]'s
  /// current text to decide whether Save is enabled (dirty vs pristine).
  String? _baselineContent;

  @override
  void initState() {
    super.initState();
    // Rebuilds on every keystroke so the Save button's dirty/pristine
    // state (via [_isDirty]) tracks the field live, not just on the next
    // cubit-state-driven rebuild.
    _controller.addListener(_handleTextChanged);
  }

  void _handleTextChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    super.dispose();
  }

  bool get _isDirty =>
      _baselineContent != null && _controller.text != _baselineContent;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    return ColoredBox(
      color: c.background,
      child: Column(
        children: [
          AppHeader(
            title: widget.assetKey,
            showBack: true,
            onBack: () => context.go('/workspace/settings/overrides'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Semantics(
              label: context.l10n.overrideEditorTitle,
              child: Text(
                context.l10n.overrideEditorTitle.toUpperCase(),
                style: AionText.caption.copyWith(color: c.textMuted),
              ),
            ),
          ),
          Expanded(
            child: BlocConsumer<OverrideEditorCubit, OverrideEditorState>(
              listener: (context, state) {
                if (state is OverrideEditorReady &&
                    _baselineContent == null) {
                  _controller.text = state.content;
                  setState(() => _baselineContent = state.content);
                } else if (state is OverrideEditorSaved) {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/workspace/settings/overrides');
                  }
                }
              },
              builder: (context, state) {
                return switch (state) {
                  OverrideEditorLoading() => const Center(
                    child: AppSpinner(),
                  ),
                  OverrideEditorError(:final message) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message,
                          style: AionText.body.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AionSpacing.sp12),
                        AppButton(
                          label: context.l10n.commonRetry,
                          onPressed: () =>
                              context.read<OverrideEditorCubit>().load(),
                        ),
                      ],
                    ),
                  ),
                  OverrideEditorReady(:final isOverridden) => _EditorBody(
                    controller: _controller,
                    mode: isOverridden
                        ? OverrideEditorMode.editingOverride
                        : OverrideEditorMode.editingDefault,
                    isDirty: _isDirty,
                    isSaving: false,
                    onSave: () => context
                        .read<OverrideEditorCubit>()
                        .save(_controller.text),
                  ),
                  OverrideEditorSaving() => _EditorBody(
                    controller: _controller,
                    mode: OverrideEditorMode.editingOverride,
                    isDirty: false,
                    isSaving: true,
                    onSave: null,
                  ),
                  OverrideEditorSaved() => const Center(child: AppSpinner()),
                };
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorBody extends StatelessWidget {
  const _EditorBody({
    required this.controller,
    required this.mode,
    required this.isDirty,
    required this.isSaving,
    required this.onSave,
  });

  final TextEditingController controller;
  final OverrideEditorMode mode;
  final bool isDirty;
  final bool isSaving;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final isEditingOverride = mode == OverrideEditorMode.editingOverride;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isEditingOverride
                  ? c.primarySubtle
                  : c.noticeFill(ThemeScope.of(context).isDark),
              border: Border.all(
                color: isEditingOverride
                    ? c.aiBubbleBorder(ThemeScope.of(context).isDark)
                    : c.noticeBorder(ThemeScope.of(context).isDark),
                width: 1,
              ),
              borderRadius: BorderRadius.all(AionRadius.md),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 9,
              ),
              child: Text(
                isEditingOverride
                    ? context.l10n.overrideEditorOverriddenNotice
                    : context.l10n.overrideEditorDefaultNotice,
                style: AionText.bodySm.copyWith(
                  fontSize: 12.5,
                  color: c.textSecondary,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: AppTextField(controller: controller, maxLines: null),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.border, width: 1)),
            color: c.background,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: AppButton(
              label: isSaving
                  ? context.l10n.overrideEditorSavingLabel
                  : isEditingOverride
                  ? context.l10n.overrideEditorSaveButton
                  : context.l10n.overrideEditorCreateButton,
              isFullWidth: true,
              onPressed: isDirty && !isSaving ? onSave : null,
            ),
          ),
        ),
      ],
    );
  }
}
