// design_system/molecules/raise_gap_or_question_picker.dart — RaiseGapOrQuestionPicker widget (design-system layer).

import 'package:flutter/services.dart'
    show KeyDownEvent, LogicalKeyboardKey, TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/atoms/app_button.dart';
import 'package:aion/design_system/atoms/app_text_field.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_shadows.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// A "+ Add" ghost-button trigger that opens [GapsAndOpenQuestionsSection]'s
/// creation popover: a small overlay offering "Raise a known gap" / "Raise an
/// open question", which swaps in a compact title/description form on
/// selection. Follows the same
/// `Overlay`/`LayerLink`/`CompositedTransformFollower` two-step mechanics
/// `TicketOverflowMenu`'s promote chooser uses — a compact overlay, not a
/// screen navigation, per this project's "no Material `Dialog`" convention.
/// This widget performs no repository writes itself — [onCreate] is
/// responsible for that (and any state refresh it implies), mirroring
/// `TicketLinkPicker.onSelected`'s contract; kept callback-based (rather than
/// reading `TicketsCubit` directly) so this design-system-layer widget stays
/// feature-agnostic per project.md's cross-feature rule. [onCreate] returns
/// whether the creation succeeded — a rejected creation (the hard-rule
/// validation in `TicketsCubit.createGapOrQuestion` failing, or the write
/// throwing) keeps the form step open and shows its inline error state
/// (Component Spec §3.3.5) rather than closing the overlay and silently
/// discarding the failure. Added for `AIO-934`; see its linked Documentation
/// page, §6.2 and Component Spec §3.
class RaiseGapOrQuestionPicker extends StatefulWidget {
  /// Creates a [RaiseGapOrQuestionPicker].
  const RaiseGapOrQuestionPicker({super.key, required this.onCreate});

  /// Called with the chosen [TicketType] (`knownGap`/`openQuestion`) and
  /// the form's [title]/[description] once "Create" is committed. The
  /// caller is responsible for actually creating the ticket (e.g. via
  /// `TicketsCubit.createGapOrQuestion`) and returns whether it
  /// succeeded — `false` keeps the form step open and shows its inline
  /// error state (Component Spec §3.3.5) instead of closing the overlay,
  /// so a rejected creation isn't silently discarded.
  final Future<bool> Function(
    TicketType type, {
    required String title,
    String? description,
  })
  onCreate;

  @override
  State<RaiseGapOrQuestionPicker> createState() =>
      _RaiseGapOrQuestionPickerState();
}

class _RaiseGapOrQuestionPickerState extends State<RaiseGapOrQuestionPicker> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  /// The type chosen in step 1, or `null` while the overlay is still
  /// showing the type-choice menu.
  TicketType? _selectedType;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _toggleOverlay() {
    if (_isOpen) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    _selectedType = null;
    _titleController.clear();
    _descriptionController.clear();

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final t = ThemeScope.of(overlayContext);
        final c = t.colors;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeOverlay,
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: const Offset(0, 6),
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              child: Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    _removeOverlay();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border.all(color: c.borderStrong, width: 1),
                    borderRadius: BorderRadius.all(AionRadius.lg),
                    boxShadow: AionShadows.overlay(c, t.isDark),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 276,
                      maxWidth: 276,
                    ),
                    child: StatefulBuilder(
                      builder: (context, setOverlayState) {
                        final type = _selectedType;
                        return AnimatedSize(
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeOut,
                          child: type == null
                              ? _TypeChoiceStep(
                                  onSelected: (picked) => setOverlayState(
                                    () => _selectedType = picked,
                                  ),
                                )
                              : _FormStep(
                                  type: type,
                                  titleController: _titleController,
                                  descriptionController: _descriptionController,
                                  onBack: () => setOverlayState(
                                    () => _selectedType = null,
                                  ),
                                  onCancel: _removeOverlay,
                                  onSubmit: (title, description) =>
                                      widget.onCreate(
                                        type,
                                        title: title,
                                        description: description,
                                      ),
                                  onSuccess: _removeOverlay,
                                ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _selectedType = null;
    if (mounted) {
      setState(() => _isOpen = false);
    } else {
      _isOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: AppButton(
        label: context.l10n.documentationAddAction,
        icon: PhosphorIcons.plusLight,
        variant: AppButtonVariant.ghost,
        onPressed: _toggleOverlay,
      ),
    );
  }
}

/// Step 1: the "Raise a known gap" / "Raise an open question" type-choice
/// menu — Component Spec §3.2.
class _TypeChoiceStep extends StatelessWidget {
  const _TypeChoiceStep({required this.onSelected});

  final ValueChanged<TicketType> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TypeChoiceRow(
            type: TicketType.knownGap,
            title: context.l10n.ticketRaiseKnownGapMenuTitle,
            subtitle: context.l10n.ticketRaiseKnownGapMenuSubtitle,
            onTap: () => onSelected(TicketType.knownGap),
          ),
          _TypeChoiceRow(
            type: TicketType.openQuestion,
            title: context.l10n.ticketRaiseOpenQuestionMenuTitle,
            subtitle: context.l10n.ticketRaiseOpenQuestionMenuSubtitle,
            onTap: () => onSelected(TicketType.openQuestion),
          ),
        ],
      ),
    );
  }
}

/// A single type-choice row (leading dot, title, subtitle) — Component
/// Spec §3.2.
class _TypeChoiceRow extends StatefulWidget {
  const _TypeChoiceRow({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final TicketType type;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  State<_TypeChoiceRow> createState() => _TypeChoiceRowState();
}

class _TypeChoiceRowState extends State<_TypeChoiceRow> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final accent = widget.type == TicketType.knownGap
        ? c.typeKnownGap
        : c.typeOpenQuestion;
    final fill = _isPressed
        ? c.border
        : (_isHovered || _isFocused ? c.surfaceHover : const Color(0x00000000));

    return Semantics(
      button: true,
      label: widget.title,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Focus(
          onFocusChange: (focused) => setState(() => _isFocused = focused),
          child: GestureDetector(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              color: fill,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const SizedBox(width: 10, height: 10),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            style: AionText.bodySm.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            widget.subtitle,
                            style: AionText.bodySm.copyWith(
                              fontSize: 11.5,
                              color: c.textMuted,
                            ),
                          ),
                        ],
                      ),
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

/// Step 2: the compact title/description form — Component Spec §3.3.
/// Tracks its own submitting/error state (Component Spec §3.3.5) since
/// [onSubmit] is asynchronous and may be rejected by the Cubit's hard-rule
/// validation or throw — a rejected creation keeps this step open and
/// shows the inline error line rather than silently closing the overlay.
class _FormStep extends StatefulWidget {
  const _FormStep({
    required this.type,
    required this.titleController,
    required this.descriptionController,
    required this.onBack,
    required this.onCancel,
    required this.onSubmit,
    required this.onSuccess,
  });

  final TicketType type;
  final TextEditingController titleController;
  final TextEditingController descriptionController;

  /// Returns to step 1 (the type-choice menu) — the back-caret icon.
  final VoidCallback onBack;

  /// Dismisses the overlay entirely — the "Cancel" action button.
  final VoidCallback onCancel;

  /// Performs the actual creation (e.g.
  /// `TicketsCubit.createGapOrQuestion`), returning whether it succeeded.
  final Future<bool> Function(String title, String? description) onSubmit;

  /// Called once [onSubmit] resolves `true` — closes the overlay.
  final VoidCallback onSuccess;

  @override
  State<_FormStep> createState() => _FormStepState();
}

class _FormStepState extends State<_FormStep> {
  bool _isSubmitting = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    widget.titleController.addListener(_handleTitleChanged);
  }

  @override
  void dispose() {
    widget.titleController.removeListener(_handleTitleChanged);
    super.dispose();
  }

  void _handleTitleChanged() => setState(() {});

  Future<void> _submit() async {
    final title = widget.titleController.text.trim();
    if (title.isEmpty || _isSubmitting) return;
    final description = widget.descriptionController.text.trim();
    setState(() {
      _isSubmitting = true;
      _hasError = false;
    });
    final success = await widget.onSubmit(
      title,
      description.isEmpty ? null : description,
    );
    if (!mounted) return;
    if (success) {
      widget.onSuccess();
    } else {
      setState(() {
        _isSubmitting = false;
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isKnownGap = widget.type == TicketType.knownGap;
    final accent = isKnownGap ? c.typeKnownGap : c.typeOpenQuestion;
    final headerLabel = isKnownGap
        ? context.l10n.ticketRaiseKnownGapFormHeader
        : context.l10n.ticketRaiseOpenQuestionFormHeader;
    final titleHint = isKnownGap
        ? context.l10n.ticketRaiseKnownGapTitleHint
        : context.l10n.ticketRaiseOpenQuestionTitleHint;
    final canSubmit =
        widget.titleController.text.trim().isNotEmpty && !_isSubmitting;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Semantics(
                  button: true,
                  label: context.l10n.commonBack,
                  child: GestureDetector(
                    onTap: widget.onBack,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.surfaceHover,
                        borderRadius: BorderRadius.all(AionRadius.iconBtnSm),
                      ),
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: Center(
                          child: PhosphorIcon(
                            PhosphorIcons.caretLeftLight,
                            size: 16,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const SizedBox(width: 9, height: 9),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    headerLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AionText.label.copyWith(color: c.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AionSpacing.sp12),
          AppTextField(
            controller: widget.titleController,
            labelText: context.l10n.createTicketTitleLabel,
            hintText: titleHint,
            isRequired: true,
            isError: _hasError,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AionSpacing.sp12),
          AppTextField(
            controller: widget.descriptionController,
            labelText: context.l10n.createTicketDescriptionLabel,
            hintText: context.l10n.createTicketDescriptionHint,
            isOptional: true,
            maxLines: 3,
          ),
          const SizedBox(height: AionSpacing.sp12),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: context.l10n.commonCancel,
                  variant: AppButtonVariant.secondary,
                  onPressed: _isSubmitting ? null : widget.onCancel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton(
                  label: _isSubmitting
                      ? context.l10n.ticketRaiseGapOrQuestionCreatingAction
                      : context.l10n.ticketRaiseGapOrQuestionCreateAction,
                  onPressed: canSubmit ? _submit : null,
                ),
              ),
            ],
          ),
          if (_hasError) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.ticketRaiseGapOrQuestionErrorMessage,
              style: AionText.bodySm.copyWith(fontSize: 12.5, color: c.danger),
            ),
          ],
        ],
      ),
    );
  }
}
