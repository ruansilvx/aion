// design_system/molecules/markdown_editor.dart — MarkdownEditor responsive content editor (design-system layer).

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/atoms/app_button.dart';
import 'package:aion/design_system/atoms/app_spinner.dart';
import 'package:aion/design_system/atoms/app_text_field.dart';
import 'package:aion/design_system/molecules/markdown_view.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';

/// Responsive Markdown content editor: a view/edit toggle on narrow
/// layouts, a live raw/preview split view on wide layouts (breakpoint
/// `maxWidth <= 640`, live preview debounced 120ms). Commits only on
/// explicit Save (never on blur), matching [InlineEditableField]'s
/// multiline commit discipline. [onCommit] is awaited so Save can show a
/// spinner and, on failure, an inline error row — it never calls a
/// repository or Cubit method itself, only the caller-supplied callback.
/// Per `aion-arch/changes/page-content-markdown-editor/design.md` §1.
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

  /// Called with the trimmed Markdown source when Save is tapped. Awaited —
  /// a thrown error surfaces as this widget's own inline error state
  /// (design.md §1.4) rather than only whatever the caller does with it.
  final Future<void> Function(String value) onCommit;

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
  static const _previewDebounce = Duration(milliseconds: 120);

  late final TextEditingController _controller;
  Timer? _debounceTimer;

  /// Narrow-layout only: whether the view/edit toggle is currently
  /// showing the editable textarea instead of the rendered preview.
  bool _isEditing = false;

  /// Whether [widget.onCommit] is currently in flight — see design.md §1.3.
  bool _isSaving = false;

  /// Non-null when the last Save attempt failed — see design.md §1.4.
  /// Cleared on the next keystroke.
  String? _errorMessage;

  /// Mirrors [_controller]'s text, but only updates [_previewDebounce]
  /// after the last keystroke — the wide-mode split view's live preview
  /// source (design.md §1.5), so a fast typist doesn't re-parse Markdown
  /// on every keystroke.
  late String _previewText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _previewText = widget.initialValue;
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_errorMessage != null) setState(() => _errorMessage = null);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_previewDebounce, () {
      if (mounted) setState(() => _previewText = _controller.text);
    });
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await widget.onCommit(_controller.text.trim());
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _isEditing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = context.l10n.pageDetailMarkdownSaveError;
      });
    }
  }

  void _cancel() {
    _controller.text = widget.initialValue;
    setState(() => _isEditing = false);
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
              if (isNarrow)
                _Narrow(
                  controller: _controller,
                  isEditing: _isEditing,
                  isSaving: _isSaving,
                  errorMessage: _errorMessage,
                  semanticsLabel: widget.semanticsLabel,
                  placeholder: widget.placeholder,
                  onStartEditing: () => setState(() => _isEditing = true),
                  onCancel: _cancel,
                  onSave: _save,
                )
              else
                _Wide(
                  controller: _controller,
                  previewText: _previewText,
                  isSaving: _isSaving,
                  errorMessage: _errorMessage,
                  placeholder: widget.placeholder,
                  onCancel: _cancel,
                  onSave: _save,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The narrow-layout body: a view/edit toggle (design.md §1's narrow
/// breakpoint), either the rendered [MarkdownView] behind a pencil
/// button or the editable textarea plus [_ActionRow]. All interaction
/// state ([MarkdownEditor]'s `_isEditing`/`_isSaving`/`_errorMessage`)
/// stays owned by [_MarkdownEditorState] — this class only renders it.
class _Narrow extends StatelessWidget {
  const _Narrow({
    required this.controller,
    required this.isEditing,
    required this.isSaving,
    required this.errorMessage,
    required this.semanticsLabel,
    required this.placeholder,
    required this.onStartEditing,
    required this.onCancel,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool isEditing;
  final bool isSaving;
  final String? errorMessage;
  final String semanticsLabel;
  final String? placeholder;
  final VoidCallback onStartEditing;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    if (!isEditing) {
      final isEmpty = controller.text.trim().isEmpty;
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
                  label: semanticsLabel,
                  child: GestureDetector(
                    onTap: onStartEditing,
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
                onTap: onStartEditing,
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
              MarkdownView(source: controller.text),
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
            controller: controller,
            maxLines: null,
            hintText: placeholder,
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: AionSpacing.sp8),
            _ErrorRow(message: errorMessage!),
          ],
          const SizedBox(height: AionSpacing.sp12),
          _ActionRow(isSaving: isSaving, onCancel: onCancel, onSave: onSave),
        ],
      ),
    );
  }
}

/// The wide-layout body: a live raw/preview split view (design.md §1.5)
/// plus [_ActionRow]. All interaction state stays owned by
/// [_MarkdownEditorState] — this class only renders it.
class _Wide extends StatelessWidget {
  const _Wide({
    required this.controller,
    required this.previewText,
    required this.isSaving,
    required this.errorMessage,
    required this.placeholder,
    required this.onCancel,
    required this.onSave,
  });

  final TextEditingController controller;
  final String previewText;
  final bool isSaving;
  final String? errorMessage;
  final String? placeholder;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
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
                    controller: controller,
                    maxLines: null,
                    hintText: placeholder,
                  ),
                ),
                const SizedBox(width: AionSpacing.sp16),
                DecoratedBox(
                  decoration: BoxDecoration(color: c.border),
                  child: const SizedBox(width: 1),
                ),
                const SizedBox(width: AionSpacing.sp16),
                Expanded(child: MarkdownView(source: previewText)),
              ],
            ),
          ),
        ),
        if (errorMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _ErrorRow(message: errorMessage!),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.border, width: 1)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _ActionRow(
              isSaving: isSaving,
              onCancel: onCancel,
              onSave: onSave,
            ),
          ),
        ),
      ],
    );
  }
}

/// The Cancel/Save button row shared by [MarkdownEditor]'s narrow and wide
/// layouts, including the saving state (design.md §1.3): a spinner appears
/// beside the buttons and both disable while a commit is in flight.
/// [AppButton] has no built-in loading-label slot (no other screen in this
/// codebase swaps a button's label for a spinner either — see
/// `CreateTicketScreen`'s `_isSubmitting`), so this uses the same
/// disable-while-in-flight convention plus an adjacent [AppSpinner] rather
/// than widening that shared atom's API for one caller.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.isSaving,
    required this.onCancel,
    required this.onSave,
  });

  final bool isSaving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (isSaving) ...[
          const AppSpinner(size: 14),
          const SizedBox(width: AionSpacing.sp8),
        ],
        AppButton(
          label: context.l10n.pageDetailMarkdownCancel,
          variant: AppButtonVariant.secondary,
          onPressed: isSaving ? null : onCancel,
        ),
        const SizedBox(width: AionSpacing.sp8),
        AppButton(
          label: context.l10n.pageDetailMarkdownSave,
          variant: AppButtonVariant.primary,
          onPressed: isSaving ? null : onSave,
        ),
      ],
    );
  }
}

/// The inline danger row shown beneath the textarea when a Save attempt
/// fails — design.md §1.4.
class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PhosphorIcon(
          PhosphorIcons.warningCircleLight,
          size: 16,
          color: c.danger,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            message,
            style: AionText.bodySm.copyWith(color: c.danger),
          ),
        ),
      ],
    );
  }
}
