// presentation/screens/workflow_prompt_templates_screen.dart — WorkflowPromptTemplatesScreen and its supporting private widgets (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/workflow_prompt_template.dart';
import 'package:aion/features/tickets/presentation/cubit/workflow_config_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/workflow_config_state.dart';

/// The `/workspace/settings/workflow/templates` route — a simple
/// list-management screen for [WorkflowPromptTemplate]s: create, edit,
/// delete. Reached from `_AttachmentForm`'s "Manage templates" link and
/// its template picker's "+ New template" row (both in
/// `workflow_status_settings_screen.dart`), and from
/// [WorkflowStatusSettingsScreen]'s own header. See
/// `aion-arch/changes/workflow-skill-attachments/design.md`'s Component
/// Spec §5.
///
/// One deliberate simplification from the pasted Component Spec, noted
/// here rather than silently (mirrors `WorkflowStatusSettingsScreen`'s
/// own precedent): `TemplateRow`'s inline `{{variable}}` highlighting
/// (§5.3) — rendering each placeholder as a `AionText.key`-styled inline
/// span within the body preview — is a rich-text parsing pass this slice
/// skips; the body preview renders as plain [AionText.bodySm] text.
class WorkflowPromptTemplatesScreen extends StatefulWidget {
  /// Creates a [WorkflowPromptTemplatesScreen].
  const WorkflowPromptTemplatesScreen({super.key});

  @override
  State<WorkflowPromptTemplatesScreen> createState() =>
      _WorkflowPromptTemplatesScreenState();
}

class _WorkflowPromptTemplatesScreenState
    extends State<WorkflowPromptTemplatesScreen> {
  /// The id of the template currently open for inline editing, or `null`.
  /// Mutually exclusive with [_creating].
  String? _editingId;

  /// Whether [_AddTemplateControl]'s inline "new template" editor is
  /// open. Mutually exclusive with [_editingId].
  bool _creating = false;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    return ColoredBox(
      color: c.background,
      child: Column(
        children: [
          AppHeader(
            title: context.l10n.workflowTemplatesScreenTitle,
            showBack: true,
            onBack: () => context.pop(),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AionSpacing.sp20,
                2,
                AionSpacing.sp20,
                AionSpacing.sp20,
              ),
              child: ContentMaxWidth(
                variant: ContentWidthVariant.form,
                child: BlocBuilder<WorkflowConfigCubit, WorkflowConfigState>(
                  builder: (context, state) {
                    final WorkflowConfigLoaded? loaded = switch (state) {
                      WorkflowConfigLoaded() => state,
                      WorkflowConfigError(:final previous) => previous,
                      WorkflowConfigInitial() => null,
                    };
                    if (loaded == null) {
                      return const Center(child: AppSpinner());
                    }
                    final errorMessage = state is WorkflowConfigError
                        ? state.message
                        : null;
                    final templates = loaded.templates;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
                          child: Text(
                            context.l10n.workflowTemplatesEyebrow,
                            style: AionText.caption.copyWith(
                              color: c.textMuted,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 0, 0, 14),
                          child: Text(
                            context.l10n.workflowTemplatesDescription,
                            style: AionText.bodySm.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                        if (errorMessage != null) ...[
                          _TemplateErrorBanner(message: errorMessage),
                          const SizedBox(height: AionSpacing.sp8),
                        ],
                        if (templates.isEmpty && !_creating)
                          _EmptyTemplatesState(
                            onCreate: () => setState(() {
                              _editingId = null;
                              _creating = true;
                            }),
                          )
                        else ...[
                          for (final template in templates)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _editingId == template.id
                                  ? _TemplateEditor(
                                      existing: template,
                                      allTemplates: templates,
                                      onDone: () =>
                                          setState(() => _editingId = null),
                                    )
                                  : _TemplateRow(
                                      template: template,
                                      onEdit: () => setState(() {
                                        _creating = false;
                                        _editingId = template.id;
                                      }),
                                    ),
                            ),
                          if (_creating)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _TemplateEditor(
                                existing: null,
                                allTemplates: templates,
                                onDone: () =>
                                    setState(() => _creating = false),
                              ),
                            )
                          else
                            _AddTemplateControl(
                              onTap: () => setState(() {
                                _editingId = null;
                                _creating = true;
                              }),
                            ),
                        ],
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

/// The rejection banner shown when [WorkflowConfigCubit] rejects a
/// template write (name collision, or delete-while-referenced). Mirrors
/// `_RoleInvariantBanner` (`workflow_status_settings_screen.dart`).
class _TemplateErrorBanner extends StatelessWidget {
  const _TemplateErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.danger.withValues(alpha: t.isDark ? 0.14 : 0.08),
        border: Border.all(
          color: c.danger.withValues(alpha: t.isDark ? 0.34 : 0.24),
          width: 1,
        ),
        borderRadius: BorderRadius.all(AionRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('▲', style: TextStyle(fontSize: 13, color: c.danger)),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: AionText.bodySm.copyWith(color: c.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One template's card — name, truncated body preview, Edit/Delete
/// actions. Component Spec §5.3.
class _TemplateRow extends StatefulWidget {
  const _TemplateRow({required this.template, required this.onEdit});

  final WorkflowPromptTemplate template;
  final VoidCallback onEdit;

  @override
  State<_TemplateRow> createState() => _TemplateRowState();
}

class _TemplateRowState extends State<_TemplateRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _isHovered ? c.surfaceHover : c.surface,
          border: Border.all(color: c.border, width: 1),
          borderRadius: BorderRadius.all(AionRadius.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.template.name,
                      style: AionText.cardTitle.copyWith(color: c.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      widget.template.body,
                      style: AionText.bodySm.copyWith(
                        fontSize: 13.5,
                        color: c.textMuted,
                        height: 1.5,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _TemplateIconButton(
                icon: PhosphorIcons.pencilSimpleLight,
                semanticsLabel: context.l10n.workflowTemplatesEditTemplate,
                onTap: widget.onEdit,
              ),
              const SizedBox(width: 4),
              _TemplateIconButton(
                icon: PhosphorIcons.trashLight,
                semanticsLabel: context.l10n.workflowTemplatesDeleteTemplate,
                destructive: true,
                onTap: () => context
                    .read<WorkflowConfigCubit>()
                    .deleteTemplate(widget.template.id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small icon-only action button — Edit/Delete on a [_TemplateRow].
class _TemplateIconButton extends StatefulWidget {
  const _TemplateIconButton({
    required this.icon,
    required this.semanticsLabel,
    required this.onTap,
    this.destructive = false,
  });

  final PhosphorIconData icon;
  final String semanticsLabel;
  final VoidCallback onTap;
  final bool destructive;

  @override
  State<_TemplateIconButton> createState() => _TemplateIconButtonState();
}

class _TemplateIconButtonState extends State<_TemplateIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final hoverFill = widget.destructive
        ? c.destructiveTint(t.isDark)
        : c.surfaceHover;
    final glyphColor = _isHovered
        ? (widget.destructive ? c.danger : c.textPrimary)
        : (widget.destructive ? c.textMuted : c.textSecondary);
    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _isHovered ? hoverFill : null,
              borderRadius: BorderRadius.all(AionRadius.iconBtnSm),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: PhosphorIcon(widget.icon, size: 14, color: glyphColor),
            ),
          ),
        ),
      ),
    );
  }
}

/// The collapsed "+ New template" trigger. Component Spec §5.4 —
/// identical shape to `_AddStatusCollapsedButton`
/// (`workflow_status_settings_screen.dart`).
class _AddTemplateControl extends StatefulWidget {
  const _AddTemplateControl({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_AddTemplateControl> createState() => _AddTemplateControlState();
}

class _AddTemplateControlState extends State<_AddTemplateControl> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    return FocusableActionDetector(
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (value) => setState(() => _isFocused = value),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _isHovered
                  ? c.primary.withValues(alpha: t.isDark ? 0.08 : 0.05)
                  : null,
              border: Border.all(
                color: _isHovered || _isFocused ? c.primary : c.borderStrong,
                width: 1.5,
              ),
              borderRadius: BorderRadius.all(AionRadius.lg),
              boxShadow: _isFocused ? AionShadows.focus(c, t.isDark) : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '+',
                    style: AionText.button.copyWith(
                      fontSize: 17,
                      color: c.primary,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    context.l10n.workflowSettingsNewTemplate,
                    style: AionText.button.copyWith(color: c.primary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The inline create/edit editor — name + multiline body fields, Cancel/
/// Save actions. Component Spec §5.5.
class _TemplateEditor extends StatefulWidget {
  const _TemplateEditor({
    required this.existing,
    required this.allTemplates,
    required this.onDone,
  });

  /// The template being edited, or `null` when creating a new one.
  final WorkflowPromptTemplate? existing;

  /// Every project-configured template, used to keep this editor's own
  /// live view of the current name in sync (`WorkflowConfigCubit
  /// .createTemplate`/`.updateTemplate` re-validate uniqueness
  /// server-side regardless).
  final List<WorkflowPromptTemplate> allTemplates;

  final VoidCallback onDone;

  @override
  State<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<_TemplateEditor> {
  static const _uuid = Uuid();

  late final TextEditingController _nameController;
  late final TextEditingController _bodyController;
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _bodyController = TextEditingController(text: widget.existing?.body ?? '');
    // Rebuilds on every keystroke so Save's enabled/disabled state and
    // the name-required error line track what's being typed live —
    // mirrors `_AddStatusControlState`'s established pattern
    // (`workflow_status_settings_screen.dart`).
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  bool get _isNameEmpty => _nameController.text.trim().isEmpty;

  void _save() {
    if (_isNameEmpty) {
      setState(() => _touched = true);
      return;
    }
    final template = WorkflowPromptTemplate(
      id: widget.existing?.id ?? _uuid.v4(),
      name: _nameController.text.trim(),
      body: _bodyController.text,
    );
    final cubit = context.read<WorkflowConfigCubit>();
    if (widget.existing == null) {
      cubit.createTemplate(template);
    } else {
      cubit.updateTemplate(template);
    }
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isEditing = widget.existing != null;
    final showError = _touched && _isNameEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.primary, width: 1.5),
        borderRadius: BorderRadius.all(AionRadius.lg),
        boxShadow: AionShadows.focus(c, t.isDark),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEditing
                  ? context.l10n.workflowTemplatesEditEyebrow
                  : context.l10n.workflowTemplatesNewEyebrow,
              style: AionText.caption.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: 13),
            AppTextField(
              controller: _nameController,
              labelText: context.l10n.workflowTemplatesNameLabel,
              isRequired: true,
              isError: showError,
              onSubmitted: (_) => _save(),
            ),
            if (showError) ...[
              const SizedBox(height: 6),
              Text(
                context.l10n.workflowTemplatesNameRequiredError,
                style: AionText.bodySm.copyWith(fontSize: 12, color: c.danger),
              ),
            ],
            const SizedBox(height: 13),
            Row(
              children: [
                Text(
                  context.l10n.workflowTemplatesBodyLabel,
                  style: AionText.label.copyWith(color: c.textSecondary),
                ),
                const Spacer(),
                Text(
                  context.l10n.workflowTemplatesBodyHint,
                  style: AionText.bodySm.copyWith(
                    fontSize: 11,
                    color: c.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            AppTextField(
              controller: _bodyController,
              maxLines: 6,
            ),
            const SizedBox(height: 13),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: context.l10n.workflowSettingsCancel,
                  variant: AppButtonVariant.ghost,
                  onPressed: widget.onDone,
                ),
                const SizedBox(width: 9),
                AppButton(
                  label: context.l10n.workflowTemplatesSaveTemplate,
                  onPressed: _touched && _isNameEmpty ? null : _save,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The zero-templates empty state, replacing the row list. Component
/// Spec §5.6.
class _EmptyTemplatesState extends StatelessWidget {
  const _EmptyTemplatesState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border, width: 1),
        borderRadius: BorderRadius.all(AionRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: t.isDark ? 0.14 : 0.08),
                borderRadius: BorderRadius.all(AionRadius.lg),
              ),
              child: SizedBox(
                width: 56,
                height: 56,
                child: Center(
                  child: PhosphorIcon(
                    PhosphorIcons.fileTextLight,
                    size: 26,
                    color: c.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              context.l10n.workflowTemplatesEmptyTitle,
              style: AionText.dialogTitle.copyWith(
                fontSize: 17,
                color: c.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                context.l10n.workflowTemplatesEmptySubtitle,
                style: AionText.bodySm.copyWith(
                  fontSize: 13.5,
                  color: c.textMuted,
                  height: 1.55,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 14),
            AppButton(
              label: context.l10n.workflowSettingsNewTemplate,
              icon: PhosphorIcons.plusLight,
              onPressed: onCreate,
            ),
          ],
        ),
      ),
    );
  }
}
