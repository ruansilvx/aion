// design_system/molecules/markdown_editor.dart — MarkdownEditor responsive content editor (design-system layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/atoms/app_button.dart';
import 'package:aion/design_system/atoms/app_text_field.dart';
import 'package:aion/design_system/molecules/markdown_view.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';

/// Responsive Markdown content editor: a view/edit toggle on narrow
/// layouts, a live raw/preview split view on wide layouts (breakpoint
/// `maxWidth <= 640`). Commits only on explicit Save (never on blur),
/// matching [InlineEditableField]'s multiline commit discipline —
/// [onCommit] is called with the trimmed text and never calls a
/// repository or Cubit method itself. Per
/// `aion-arch/changes/page-content-markdown-editor/design.md` §1.
class MarkdownEditor extends StatefulWidget {
  /// Creates a [MarkdownEditor] seeded with [initialValue].
  const MarkdownEditor({
    super.key,
    required this.initialValue,
    required this.onCommit,
    required this.semanticsLabel,
    this.placeholder,
  });

  /// The Markdown source the editor starts with.
  final String initialValue;

  /// Called with the trimmed Markdown source when Save is tapped.
  final ValueChanged<String> onCommit;

  /// Accessibility label for the edit-mode text field.
  final String semanticsLabel;

  /// Placeholder shown in the empty state and the empty edit-mode
  /// textarea.
  final String? placeholder;

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  static const _breakpoint = 640.0;

  late final TextEditingController _controller;

  /// Narrow-layout only: whether the view/edit toggle is currently
  /// showing the editable textarea instead of the rendered preview.
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    widget.onCommit(_controller.text.trim());
    if (mounted) setState(() => _isEditing = false);
  }

  void _cancel() {
    _controller.text = widget.initialValue;
    if (mounted) setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth <= _breakpoint;

        return DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border, width: 1),
            borderRadius: const BorderRadius.all(AionRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'CONTENT',
                  style: AionText.caption.copyWith(color: c.textMuted),
                ),
              ),
              if (isNarrow) _buildNarrow(context) else _buildWide(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNarrow(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    if (!_isEditing) {
      final isEmpty = _controller.text.trim().isEmpty;
      return Padding(
        padding: const EdgeInsets.all(AionSpacing.sp16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Spacer(),
                Semantics(
                  button: true,
                  label: widget.semanticsLabel,
                  child: GestureDetector(
                    onTap: () => setState(() => _isEditing = true),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.all(
                          AionRadius.iconBtnSm,
                        ),
                      ),
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: Center(
                          child: PhosphorIcon(
                            PhosphorIcons.pencilSimpleLight,
                            size: 16,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (isEmpty)
              GestureDetector(
                onTap: () => setState(() => _isEditing = true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.pageDetailContentPlaceholder,
                        style: AionText.body.copyWith(color: c.textMuted),
                      ),
                    ],
                  ),
                ),
              )
            else
              MarkdownView(source: _controller.text),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AionSpacing.sp16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: _controller,
            maxLines: null,
            hintText: widget.placeholder,
          ),
          const SizedBox(height: AionSpacing.sp12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                label: context.l10n.pageDetailMarkdownCancel,
                variant: AppButtonVariant.secondary,
                onPressed: _cancel,
              ),
              const SizedBox(width: AionSpacing.sp8),
              AppButton(
                label: context.l10n.pageDetailMarkdownSave,
                variant: AppButtonVariant.primary,
                onPressed: _save,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWide(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(AionSpacing.sp16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _controller,
                    maxLines: null,
                    hintText: widget.placeholder,
                  ),
                ),
                const SizedBox(width: AionSpacing.sp16),
                DecoratedBox(
                  decoration: BoxDecoration(color: c.border),
                  child: const SizedBox(width: 1),
                ),
                const SizedBox(width: AionSpacing.sp16),
                Expanded(
                  child: ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) =>
                        MarkdownView(source: _controller.text),
                  ),
                ),
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.border, width: 1)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: context.l10n.pageDetailMarkdownCancel,
                  variant: AppButtonVariant.secondary,
                  onPressed: _cancel,
                ),
                const SizedBox(width: AionSpacing.sp8),
                AppButton(
                  label: context.l10n.pageDetailMarkdownSave,
                  variant: AppButtonVariant.primary,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
