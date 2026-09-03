// design_system/molecules/markdown_editor.dart — MarkdownEditor responsive content editor (design-system layer).

import 'dart:async';

import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/atoms/app_button.dart';
import 'package:aion/design_system/atoms/app_spinner.dart';
import 'package:aion/design_system/atoms/app_text_field.dart';
import 'package:aion/design_system/molecules/markdown_view.dart';
import 'package:aion/design_system/molecules/wikilink_suggestion_list.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';

/// Max candidate rows shown by the `[[` autocomplete overlay — design.md
/// §4 ("capped, e.g. 20").
const int _kWikilinkSuggestionCap = 20;

/// Responsive Markdown content editor: a view/edit toggle on narrow layouts, a
/// live raw/preview split view on wide layouts (breakpoint `maxWidth <= 640`,
/// live preview debounced 120ms). Commits only on explicit Save (never on
/// blur), matching [InlineEditableField]'s multiline commit discipline.
/// [onCommit] is awaited so Save can show a spinner and, on failure, an inline
/// error row — it never calls a repository or Cubit method itself, only the
/// caller-supplied callback. Per `AIO-1350` §1.
class MarkdownEditor extends StatefulWidget {
  /// Creates a [MarkdownEditor] seeded with [initialValue].
  const MarkdownEditor({
    super.key,
    required this.initialValue,
    required this.onCommit,
    required this.semanticsLabel,
    this.placeholder,
    this.wikilinkSuggestions,
    this.onCreatePage,
    this.resolveWikilink,
    this.onWikilinkTap,
    this.onCreateWikilinkTarget,
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

  /// Resolves candidates for the `[[`-triggered autocomplete overlay, given
  /// the live in-progress query text. `null` (the default) leaves `[[` inert —
  /// plain literal characters, no overlay — every existing consumer's behavior
  /// is unaffected. Added for `AIO-963`; see its linked Documentation page,
  /// §4.
  final List<WikilinkSuggestionItem> Function(String query)? wikilinkSuggestions;

  /// Called with the typed query when the autocomplete overlay's no-matches
  /// state's create affordance is activated (Enter, or a tap on the "Press ↵
  /// to create it" line) — its returned item is inserted the same way a picked
  /// suggestion is. `null` (the default, and every consumer that doesn't
  /// supply [wikilinkSuggestions] either) leaves that affordance a no-op, per
  /// design.md §4.5. Added for `AIO-963`.
  final Future<WikilinkSuggestionItem?> Function(String title)? onCreatePage;

  /// Forwarded straight through to every internal `MarkdownView(source:
  /// ...)` this widget renders (both the narrow view-mode preview and the
  /// wide split-view preview) — see [MarkdownView.resolveWikilink]'s
  /// dartdoc. `null` (the default) leaves both previews' `[[...]]` text
  /// unrecognized, matching every other `MarkdownView` consumer.
  final Ticket? Function(String target)? resolveWikilink;

  /// Forwarded to every internal `MarkdownView` — see
  /// [MarkdownView.onWikilinkTap].
  final void Function(Ticket ticket)? onWikilinkTap;

  /// Forwarded to every internal `MarkdownView` — see
  /// [MarkdownView.onCreateWikilinkTarget].
  final void Function(String title)? onCreateWikilinkTarget;

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

  /// Whether [widget.onCommit] is currently in flight — see its linked
  /// Documentation page, §1.3.
  bool _isSaving = false;

  /// Non-null when the last Save attempt failed — see its linked
  /// Documentation page, §1.4. Cleared on the next keystroke.
  String? _errorMessage;

  /// Mirrors [_controller]'s text, but only updates [_previewDebounce]
  /// after the last keystroke — the wide-mode split view's live preview
  /// source (design.md §1.5), so a fast typist doesn't re-parse Markdown
  /// on every keystroke.
  late String _previewText;

  /// Anchors the `[[` autocomplete overlay to the live text caret
  /// position — the `CompositedTransformTarget` half lives on whichever
  /// of [_Narrow]/[_Wide] currently renders the editable textarea (see
  /// [_fieldKey]'s dartdoc for why that pairing is safe across the two).
  final LayerLink _wikilinkLayerLink = LayerLink();

  /// Wraps the rendered `AppTextField` so its `RenderBox` (size — needed
  /// to reproduce the field's own text-wrapping width) can be looked up
  /// from [_computeWikilinkCaretOffset]. Both [_Narrow] and [_Wide] key
  /// their editable textarea with this same key — only one is ever
  /// mounted at a time (the `LayoutBuilder` breakpoint switch in [build]),
  /// so there's never a duplicate-key conflict.
  final GlobalKey _fieldKey = GlobalKey();

  OverlayEntry? _wikilinkOverlayEntry;

  /// The index, in [_controller]'s text, of the `[` that starts the
  /// in-progress `[[query` span currently open in the overlay — `null`
  /// when no overlay is open. Where a selected/created reference gets
  /// spliced back in.
  int? _wikilinkTriggerStart;

  /// The live text between the triggering `[[` and the cursor.
  String _wikilinkQuery = '';

  /// The keyboard-highlighted row in the open overlay — see
  /// [WikilinkSuggestionList.highlightedIndex]'s dartdoc for why this is
  /// driven here rather than by real Flutter focus.
  int _wikilinkHighlightedIndex = 0;

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
    _closeWikilinkOverlay();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_errorMessage != null) setState(() => _errorMessage = null);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_previewDebounce, () {
      if (mounted) setState(() => _previewText = _controller.text);
    });
    _updateWikilinkTrigger();
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

  /// Detects a just-typed, still-open `[[query` span on the current line
  /// (the last `[[` before the cursor with no `]]`/`[`/`]` between it and
  /// the cursor) and opens/updates/closes the autocomplete overlay
  /// accordingly. A no-op entirely when [MarkdownEditor.wikilinkSuggestions]
  /// is `null`.
  void _updateWikilinkTrigger() {
    if (widget.wikilinkSuggestions == null) return;
    final text = _controller.text;
    final selection = _controller.selection;
    if (!selection.isValid ||
        !selection.isCollapsed ||
        selection.baseOffset <= 0 ||
        selection.baseOffset > text.length) {
      _closeWikilinkOverlay();
      return;
    }
    final cursor = selection.baseOffset;
    final lineStart = text.lastIndexOf('\n', cursor - 1) + 1;
    final onLine = text.substring(lineStart, cursor);
    final bracketIndex = onLine.lastIndexOf('[[');
    if (bracketIndex == -1) {
      _closeWikilinkOverlay();
      return;
    }
    final query = onLine.substring(bracketIndex + 2);
    if (query.contains(']') || query.contains('[')) {
      _closeWikilinkOverlay();
      return;
    }
    _wikilinkTriggerStart = lineStart + bracketIndex;
    _wikilinkQuery = query;
    _wikilinkHighlightedIndex = 0;
    if (_wikilinkOverlayEntry == null) {
      _openWikilinkOverlay();
    } else {
      _wikilinkOverlayEntry!.markNeedsBuild();
    }
  }

  void _openWikilinkOverlay() {
    final overlay = Overlay.of(context);
    // Inline builder closure (not a separately-named `Widget _buildX`
    // method) — matches `TicketParentPicker._showOverlay`'s own
    // established precedent for this exact
    // `OverlayEntry`/`CompositedTransformFollower` shape elsewhere in
    // this codebase.
    _wikilinkOverlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final items = _currentWikilinkItems();
        final caret = _computeWikilinkCaretOffset();
        final lineHeight =
            AionText.body.fontSize! * (AionText.body.height ?? 1.5);

        var flipAbove = false;
        if (caret != null) {
          final renderBox = _fieldKey.currentContext?.findRenderObject();
          if (renderBox is RenderBox && renderBox.attached) {
            final globalCaretY = renderBox.localToGlobal(caret).dy;
            final viewportHeight = MediaQuery.of(context).size.height;
            const estimatedPanelHeight = 340.0;
            flipAbove = globalCaretY + estimatedPanelHeight > viewportHeight;
          }
        }

        final baseOffset = caret ?? const Offset(0, 0);
        final followerOffset = flipAbove
            ? Offset(baseOffset.dx, baseOffset.dy - 6)
            : Offset(baseOffset.dx, baseOffset.dy + lineHeight + 6);

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeWikilinkOverlay,
              ),
            ),
            CompositedTransformFollower(
              link: _wikilinkLayerLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topLeft,
              followerAnchor: flipAbove
                  ? Alignment.bottomLeft
                  : Alignment.topLeft,
              offset: followerOffset,
              child: WikilinkSuggestionList(
                items: items,
                query: _wikilinkQuery,
                highlightedIndex: _wikilinkHighlightedIndex,
                onSelected: (item) => _insertWikilinkReference(item.ticketId),
                onCreatePressed: widget.onCreatePage == null
                    ? null
                    : _handleCreateWikilinkPage,
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_wikilinkOverlayEntry!);
    HardwareKeyboard.instance.addHandler(_handleWikilinkKeyEvent);
  }

  void _closeWikilinkOverlay() {
    if (_wikilinkOverlayEntry == null) return;
    HardwareKeyboard.instance.removeHandler(_handleWikilinkKeyEvent);
    _wikilinkOverlayEntry?.remove();
    _wikilinkOverlayEntry = null;
    _wikilinkTriggerStart = null;
  }

  /// The current, capped candidate list for [_wikilinkQuery].
  List<WikilinkSuggestionItem> _currentWikilinkItems() {
    final items = widget.wikilinkSuggestions?.call(_wikilinkQuery) ?? const [];
    return items.length > _kWikilinkSuggestionCap
        ? items.sublist(0, _kWikilinkSuggestionCap)
        : items;
  }

  /// Intercepts `Escape`/`↑`/`↓`/`Enter` while the overlay is open, at the
  /// [HardwareKeyboard] level rather than via Flutter's `Focus`/`Shortcuts`
  /// tree — the actual text-input focus must stay on the live `TextField`
  /// so the user can keep typing the query, which means a normal ancestor
  /// `Focus.onKeyEvent` would never even see these keys (`EditableText`'s
  /// own internal key handling — newline-on-Enter, cursor movement on the
  /// arrow keys — consumes them first). Registered only while the overlay
  /// is open (see [_openWikilinkOverlay]/[_closeWikilinkOverlay]).
  bool _handleWikilinkKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _closeWikilinkOverlay();
      return true;
    }
    final items = _currentWikilinkItems();
    if (key == LogicalKeyboardKey.arrowDown) {
      if (items.isEmpty) return false;
      setState(() {
        _wikilinkHighlightedIndex =
            (_wikilinkHighlightedIndex + 1) % items.length;
      });
      _wikilinkOverlayEntry?.markNeedsBuild();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (items.isEmpty) return false;
      setState(() {
        _wikilinkHighlightedIndex =
            (_wikilinkHighlightedIndex - 1 + items.length) % items.length;
      });
      _wikilinkOverlayEntry?.markNeedsBuild();
      return true;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (items.isEmpty) {
        unawaited(_handleCreateWikilinkPage());
      } else {
        final index = _wikilinkHighlightedIndex.clamp(0, items.length - 1);
        _insertWikilinkReference(items[index].ticketId);
      }
      return true;
    }
    return false;
  }

  /// Replaces the in-progress `[[<query>` span with `[[<ticketId>]]` —
  /// bare, no alias — and moves the cursor past the closing brackets, per
  /// design.md's "Resolution model" (an id-anchored reference always
  /// re-resolves to the target's current title live, so the raw source
  /// being less immediately readable than a title trades off against
  /// never needing a rename-rewrite).
  void _insertWikilinkReference(String ticketId) {
    final start = _wikilinkTriggerStart;
    if (start == null) return;
    final text = _controller.text;
    final cursor = _controller.selection.baseOffset;
    final end = (cursor < 0 || cursor > text.length) ? text.length : cursor;
    final replacement = '[[$ticketId]]';
    final newText = text.replaceRange(start, end, replacement);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    _closeWikilinkOverlay();
  }

  /// Calls [MarkdownEditor.onCreatePage] with the current query and
  /// inserts its result the same way a picked suggestion is inserted.
  /// No-op if [MarkdownEditor.onCreatePage] is `null` or resolves `null`.
  Future<void> _handleCreateWikilinkPage() async {
    final onCreatePage = widget.onCreatePage;
    if (onCreatePage == null) return;
    final result = await onCreatePage(_wikilinkQuery);
    if (result != null) _insertWikilinkReference(result.ticketId);
  }

  /// The caret's local pixel offset relative to the editable textarea's
  /// own top-left corner (i.e. relative to [_wikilinkLayerLink]'s
  /// `CompositedTransformTarget` origin) — laid out with a [TextPainter]
  /// matching `AppTextField`'s multiline style/content-padding, using the
  /// field's real rendered width (via [_fieldKey]) so wrapped lines land
  /// in the same place the real `TextField` would put them. Returns
  /// `null` before the field has been laid out (first frame) or if the
  /// current selection is invalid.
  Offset? _computeWikilinkCaretOffset() {
    final renderBox = _fieldKey.currentContext?.findRenderObject();
    if (renderBox is! RenderBox || !renderBox.hasSize) return null;
    final selection = _controller.selection;
    if (!selection.isValid) return null;
    final text = _controller.text;
    final cursor = selection.baseOffset.clamp(0, text.length);
    const contentPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 12);
    final maxWidth = renderBox.size.width - contentPadding.horizontal;
    final painter = TextPainter(
      text: TextSpan(text: text.substring(0, cursor), style: AionText.body),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth < 0 ? 0 : maxWidth);
    final caret = painter.getOffsetForCaret(
      TextPosition(offset: cursor),
      Rect.zero,
    );
    return Offset(
      contentPadding.left + caret.dx,
      contentPadding.top + caret.dy,
    );
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
                  wikilinkLayerLink: _wikilinkLayerLink,
                  fieldKey: _fieldKey,
                  resolveWikilink: widget.resolveWikilink,
                  onWikilinkTap: widget.onWikilinkTap,
                  onCreateWikilinkTarget: widget.onCreateWikilinkTarget,
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
                  wikilinkLayerLink: _wikilinkLayerLink,
                  fieldKey: _fieldKey,
                  resolveWikilink: widget.resolveWikilink,
                  onWikilinkTap: widget.onWikilinkTap,
                  onCreateWikilinkTarget: widget.onCreateWikilinkTarget,
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
    required this.wikilinkLayerLink,
    required this.fieldKey,
    required this.resolveWikilink,
    required this.onWikilinkTap,
    required this.onCreateWikilinkTarget,
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

  /// See [_MarkdownEditorState._wikilinkLayerLink]/`._fieldKey`'s dartdoc.
  final LayerLink wikilinkLayerLink;
  final GlobalKey fieldKey;

  /// Forwarded straight through from [MarkdownEditor] — see its own
  /// same-named parameter's dartdoc.
  final Ticket? Function(String target)? resolveWikilink;
  final void Function(Ticket ticket)? onWikilinkTap;
  final void Function(String title)? onCreateWikilinkTarget;
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
              MarkdownView(
                source: controller.text,
                resolveWikilink: resolveWikilink,
                onWikilinkTap: onWikilinkTap,
                onCreateWikilinkTarget: onCreateWikilinkTarget,
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AionSpacing.sp16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CompositedTransformTarget(
            link: wikilinkLayerLink,
            child: KeyedSubtree(
              key: fieldKey,
              child: AppTextField(
                controller: controller,
                maxLines: null,
                hintText: placeholder,
              ),
            ),
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
    required this.wikilinkLayerLink,
    required this.fieldKey,
    required this.resolveWikilink,
    required this.onWikilinkTap,
    required this.onCreateWikilinkTarget,
    required this.onCancel,
    required this.onSave,
  });

  final TextEditingController controller;
  final String previewText;
  final bool isSaving;
  final String? errorMessage;
  final String? placeholder;

  /// See [_MarkdownEditorState._wikilinkLayerLink]/`._fieldKey`'s dartdoc.
  final LayerLink wikilinkLayerLink;
  final GlobalKey fieldKey;

  /// Forwarded straight through from [MarkdownEditor] — see its own
  /// same-named parameter's dartdoc.
  final Ticket? Function(String target)? resolveWikilink;
  final void Function(Ticket ticket)? onWikilinkTap;
  final void Function(String title)? onCreateWikilinkTarget;
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
                  child: CompositedTransformTarget(
                    link: wikilinkLayerLink,
                    child: KeyedSubtree(
                      key: fieldKey,
                      child: AppTextField(
                        controller: controller,
                        maxLines: null,
                        hintText: placeholder,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AionSpacing.sp16),
                DecoratedBox(
                  decoration: BoxDecoration(color: c.border),
                  child: const SizedBox(width: 1),
                ),
                const SizedBox(width: AionSpacing.sp16),
                Expanded(
                  child: MarkdownView(
                    source: previewText,
                    resolveWikilink: resolveWikilink,
                    onWikilinkTap: onWikilinkTap,
                    onCreateWikilinkTarget: onCreateWikilinkTarget,
                  ),
                ),
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
