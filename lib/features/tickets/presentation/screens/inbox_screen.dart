// presentation/screens/inbox_screen.dart — InboxScreen root screen (presentation layer).

import 'package:flutter/material.dart' show Material, MaterialType, TextField;
import 'package:flutter/services.dart'
    show TextInputAction, TextInputType;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/inbox_purpose.dart';
import 'package:aion/features/tickets/presentation/cubit/inbox_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/inbox_state.dart';
import 'package:aion/features/tickets/presentation/widgets/inbox_empty_state.dart';
import 'package:aion/features/tickets/presentation/widgets/inbox_history_item.dart';

/// The `/workspace/inbox` route: a launcher for the four Inbox purposes
/// (brain dump, what's next, plan a release, ask a question) plus a
/// reverse-chronological history of past launches. [InboxCubit] is
/// provided per-route by `appRouter`, same pattern as `DocumentationCubit`.
/// Per `aion-arch/changes/new-project-onboarding-inbox/design.md` §2.
class InboxScreen extends StatefulWidget {
  /// Creates an [InboxScreen].
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final _brainDumpController = TextEditingController();
  final _qaController = TextEditingController();

  /// Which inline-input card (brain dump or Q&A) is currently expanded —
  /// `null` when neither is. Only one may be expanded at a time (design.md
  /// §4.6).
  InboxPurpose? _expandedPurpose;

  @override
  void initState() {
    super.initState();
    context.read<InboxCubit>().load();
  }

  @override
  void dispose() {
    _brainDumpController.dispose();
    _qaController.dispose();
    super.dispose();
  }

  void _setExpanded(InboxPurpose? purpose) {
    setState(() => _expandedPurpose = purpose);
  }

  /// Runs [start], and if it resolves to a non-null chat ticket id,
  /// navigates into that chat's ordinary detail view — every Inbox chat
  /// is a `chat`-type ticket, so its route is always
  /// `/workspace/tickets/:id`, never `ticketDetailRoute`'s `page` branch.
  Future<void> _launch(Future<String?> Function() start) async {
    final id = await start();
    if (id != null && mounted) {
      context.go('/workspace/tickets/$id');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final cubit = context.read<InboxCubit>();

    return BlocListener<InboxCubit, InboxState>(
      listenWhen: (previous, current) => current is InboxError,
      listener: (context, state) {
        AppToast.show(context, (state as InboxError).message);
      },
      child: ColoredBox(
        color: c.background,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AionSpacing.sp20,
            vertical: AionSpacing.sp20,
          ),
          child: ContentMaxWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _InboxHeader(),
                const SizedBox(height: AionSpacing.sp24),
                BlocBuilder<InboxCubit, InboxState>(
                  builder: (context, state) {
                    final launching = state is InboxLaunching
                        ? state.purpose
                        : null;
                    return _LauncherGrid(
                      expandedPurpose: _expandedPurpose,
                      launchingPurpose: launching,
                      brainDumpController: _brainDumpController,
                      qaController: _qaController,
                      onExpand: _setExpanded,
                      onBrainDumpSubmit: () => _launch(
                        () => cubit.startBrainDump(_brainDumpController.text),
                      ),
                      onWhatNextTap: () =>
                          _launch(cubit.startWhatNextGuidance),
                      onReleasePlanningTap: () =>
                          _launch(cubit.startReleasePlanning),
                      onQaSubmit: () =>
                          _launch(() => cubit.startQa(_qaController.text)),
                    );
                  },
                ),
                const SizedBox(height: AionSpacing.sp32),
                BlocBuilder<InboxCubit, InboxState>(
                  builder: (context, state) {
                    final history = state is InboxLoaded
                        ? state.history
                        : const <Ticket>[];
                    final isLoading =
                        state is InboxLoading || state is InboxInitial;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _HistorySectionLabel(count: history.length),
                        const SizedBox(height: AionSpacing.sp12),
                        if (isLoading)
                          const Center(child: AppSpinner())
                        else if (history.isEmpty)
                          const InboxEmptyState()
                        else
                          Column(
                            children: [
                              for (final chat in history) ...[
                                InboxHistoryItem(
                                  ticket: chat,
                                  onTap: () =>
                                      context.go('/workspace/tickets/${chat.id}'),
                                ),
                                const SizedBox(height: AionSpacing.sp8),
                              ],
                            ],
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The screen header — eyebrow, title, one-line subtitle. Per design.md
/// §2.2.
class _InboxHeader extends StatelessWidget {
  const _InboxHeader();

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.inboxScreenEyebrow,
          style: AionText.caption.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: 5),
        Text(
          context.l10n.inboxScreenTitle,
          style: AionText.h1.copyWith(color: c.textPrimary),
        ),
        const SizedBox(height: 5),
        Text(
          context.l10n.inboxScreenSubtitle,
          style: AionText.bodySm.copyWith(color: c.textSecondary),
        ),
      ],
    );
  }
}

/// The history section's small label — `"RECENT"` when empty, `"RECENT ·
/// {n}"` otherwise. Per design.md §2.3.
class _HistorySectionLabel extends StatelessWidget {
  const _HistorySectionLabel({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final text = count == 0
        ? context.l10n.inboxHistorySectionLabel
        : context.l10n.inboxHistorySectionLabelCount(count);
    return Text(text, style: AionText.caption.copyWith(color: c.textMuted));
  }
}

/// The four-entry launcher: 2×2 grid on wide viewports (content column
/// `>= 560`), collapsing to a single stack on narrow ones. Per design.md
/// §3.
class _LauncherGrid extends StatelessWidget {
  const _LauncherGrid({
    required this.expandedPurpose,
    required this.launchingPurpose,
    required this.brainDumpController,
    required this.qaController,
    required this.onExpand,
    required this.onBrainDumpSubmit,
    required this.onWhatNextTap,
    required this.onReleasePlanningTap,
    required this.onQaSubmit,
  });

  final InboxPurpose? expandedPurpose;
  final InboxPurpose? launchingPurpose;
  final TextEditingController brainDumpController;
  final TextEditingController qaController;
  final ValueChanged<InboxPurpose?> onExpand;
  final VoidCallback onBrainDumpSubmit;
  final VoidCallback onWhatNextTap;
  final VoidCallback onReleasePlanningTap;
  final VoidCallback onQaSubmit;

  static const _kWideBreakpoint = 560.0;

  @override
  Widget build(BuildContext context) {
    final brainDump = _PurposeLauncherCard(
      purpose: InboxPurpose.brainDump,
      icon: PhosphorIcons.brainLight,
      title: context.l10n.inboxBrainDumpLabel,
      hint: context.l10n.inboxBrainDumpHint,
      shape: _CardShape.inlineInput,
      expanded: expandedPurpose == InboxPurpose.brainDump,
      launching: false,
      onCollapsedTap: () => onExpand(InboxPurpose.brainDump),
      onClose: () => onExpand(null),
      controller: brainDumpController,
      inputPlaceholder: context.l10n.inboxBrainDumpPlaceholder,
      submitLabel: context.l10n.inboxCreateTicketsButton,
      onSubmit: onBrainDumpSubmit,
      minLines: 3,
      maxLines: 8,
    );
    final whatNext = _PurposeLauncherCard(
      purpose: InboxPurpose.whatNextGuidance,
      icon: PhosphorIcons.compassLight,
      title: context.l10n.inboxWhatNextLabel,
      hint: context.l10n.inboxWhatNextHint,
      shape: _CardShape.oneTap,
      expanded: false,
      launching: launchingPurpose == InboxPurpose.whatNextGuidance,
      inFlightLabel: context.l10n.inboxWhatNextInFlight,
      onCollapsedTap: onWhatNextTap,
    );
    final releasePlanning = _PurposeLauncherCard(
      purpose: InboxPurpose.releasePlanning,
      icon: PhosphorIcons.rocketLaunchLight,
      title: context.l10n.inboxReleasePlanningLabel,
      hint: context.l10n.inboxReleasePlanningHint,
      shape: _CardShape.oneTap,
      expanded: false,
      launching: launchingPurpose == InboxPurpose.releasePlanning,
      inFlightLabel: context.l10n.inboxReleasePlanningInFlight,
      onCollapsedTap: onReleasePlanningTap,
    );
    final qa = _PurposeLauncherCard(
      purpose: InboxPurpose.qa,
      icon: PhosphorIcons.chatCircleTextLight,
      title: context.l10n.inboxQaLabel,
      hint: context.l10n.inboxQaHint,
      shape: _CardShape.inlineInput,
      expanded: expandedPurpose == InboxPurpose.qa,
      launching: false,
      onCollapsedTap: () => onExpand(InboxPurpose.qa),
      onClose: () => onExpand(null),
      controller: qaController,
      inputPlaceholder: context.l10n.inboxQaPlaceholder,
      submitLabel: context.l10n.inboxAskButton,
      onSubmit: onQaSubmit,
      minLines: 2,
      maxLines: 6,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _kWideBreakpoint) {
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: brainDump),
                  const SizedBox(width: AionSpacing.sp16),
                  Expanded(child: whatNext),
                ],
              ),
              const SizedBox(height: AionSpacing.sp16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: releasePlanning),
                  const SizedBox(width: AionSpacing.sp16),
                  Expanded(child: qa),
                ],
              ),
            ],
          );
        }
        return Column(
          children: [
            brainDump,
            const SizedBox(height: AionSpacing.sp12),
            whatNext,
            const SizedBox(height: AionSpacing.sp12),
            releasePlanning,
            const SizedBox(height: AionSpacing.sp12),
            qa,
          ],
        );
      },
    );
  }
}

/// Which interaction shape a [_PurposeLauncherCard] uses (design.md §4).
enum _CardShape {
  /// Tapping the whole card fires the launch directly (What's next, Plan
  /// a release).
  oneTap,

  /// Tapping the collapsed card expands it in place into a text input
  /// plus submit button (Brain dump, Ask a question).
  inlineInput,
}

/// A single purpose-launcher card — shared geometry/states for both
/// [_CardShape]s (design.md §4.1), diverging into either an in-flight
/// one-tap row or an expanded inline-input form.
class _PurposeLauncherCard extends StatefulWidget {
  const _PurposeLauncherCard({
    required this.purpose,
    required this.icon,
    required this.title,
    required this.hint,
    required this.shape,
    required this.expanded,
    required this.launching,
    this.inFlightLabel,
    required this.onCollapsedTap,
    this.onClose,
    this.controller,
    this.inputPlaceholder,
    this.submitLabel,
    this.onSubmit,
    this.minLines,
    this.maxLines,
  });

  final InboxPurpose purpose;
  final IconData icon;
  final String title;
  final String hint;
  final _CardShape shape;

  /// Whether this inline-input card is currently expanded. Always
  /// `false` for a [_CardShape.oneTap] card.
  final bool expanded;

  /// Whether this one-tap card's launch is currently in flight. Always
  /// `false` for a [_CardShape.inlineInput] card (its own submit-button
  /// state carries that instead).
  final bool launching;

  /// The in-flight status line for a one-tap card (e.g. "Thinking about
  /// what's next…"). Required when [shape] is [_CardShape.oneTap].
  final String? inFlightLabel;

  /// Tapped when collapsed — expands (inline-input) or launches (one-tap).
  final VoidCallback onCollapsedTap;

  /// Tapped to collapse an expanded inline-input card. `null` for
  /// one-tap cards.
  final VoidCallback? onClose;

  /// The inline input's text controller. Required when [shape] is
  /// [_CardShape.inlineInput].
  final TextEditingController? controller;
  final String? inputPlaceholder;
  final String? submitLabel;
  final VoidCallback? onSubmit;
  final int? minLines;
  final int? maxLines;

  @override
  State<_PurposeLauncherCard> createState() => _PurposeLauncherCardState();
}

class _PurposeLauncherCardState extends State<_PurposeLauncherCard> {
  bool _isHovered = false;
  bool _isPressed = false;
  bool _isFocused = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_handleTextChanged);
    _hasText = widget.controller?.text.trim().isNotEmpty ?? false;
  }

  @override
  void didUpdateWidget(covariant _PurposeLauncherCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleTextChanged);
      widget.controller?.addListener(_handleTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_handleTextChanged);
    super.dispose();
  }

  void _handleTextChanged() {
    final hasText = widget.controller!.text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final accent = inboxAccentFor(widget.purpose, c);
    final isExpanded = widget.shape == _CardShape.inlineInput && widget.expanded;

    final borderColor = isExpanded
        ? c.border
        : (_isHovered || _isPressed)
        ? accent.withValues(alpha: t.isDark ? 0.55 : 0.45)
        : c.border;
    final boxShadow = isExpanded
        ? const <BoxShadow>[]
        : _isFocused
        ? AionShadows.focus(c, t.isDark, color: accent)
        : (_isHovered ? AionShadows.card(c, t.isDark) : const <BoxShadow>[]);

    final content = isExpanded
        ? _buildExpandedContent(context, c, accent)
        : _buildCollapsedContent(context, c, accent);

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.all(AionSpacing.sp16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: borderColor, width: 1),
        borderRadius: BorderRadius.all(AionRadius.lg),
        boxShadow: boxShadow,
      ),
      child: content,
    );

    if (isExpanded) return card;

    final canTap = !widget.launching;
    return Semantics(
      button: true,
      label: widget.title,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: FocusableActionDetector(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                if (canTap) widget.onCollapsedTap();
                return null;
              },
            ),
          },
          onShowFocusHighlight: (value) => setState(() => _isFocused = value),
          child: GestureDetector(
            onTap: canTap ? widget.onCollapsedTap : null,
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            child: AnimatedScale(
              scale: _isPressed ? 0.98 : 1.0,
              duration: const Duration(milliseconds: 90),
              child: card,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedContent(BuildContext context, AionColors c, Color accent) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CardBadge(icon: widget.icon, accent: accent),
        const SizedBox(width: AionSpacing.sp12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                style: AionText.inboxCardLabel.copyWith(color: c.textPrimary),
              ),
              const SizedBox(height: 4),
              if (widget.launching)
                Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: _SpinningIcon(color: accent),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.inFlightLabel ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AionText.streamStatus.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                  ],
                )
              else
                Text(
                  widget.hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AionText.bodySm.copyWith(color: c.textMuted),
                ),
            ],
          ),
        ),
        if (widget.shape == _CardShape.oneTap && !widget.launching)
          PhosphorIcon(
            PhosphorIcons.arrowRightLight,
            size: 16,
            color: _isHovered ? accent : c.textMuted,
          ),
      ],
    );
  }

  Widget _buildExpandedContent(BuildContext context, AionColors c, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _CardBadge(icon: widget.icon, accent: accent),
            const SizedBox(width: AionSpacing.sp12),
            Expanded(
              child: Text(
                widget.title,
                style: AionText.inboxCardLabel.copyWith(color: c.textPrimary),
              ),
            ),
            Semantics(
              button: true,
              label: context.l10n.commonBack,
              child: GestureDetector(
                onTap: widget.onClose,
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: Center(
                    child: PhosphorIcon(
                      PhosphorIcons.xLight,
                      size: 14,
                      color: c.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AionSpacing.sp12),
        _InlineInputField(
          controller: widget.controller!,
          placeholder: widget.inputPlaceholder ?? '',
          accent: accent,
          minLines: widget.minLines ?? 2,
          maxLines: widget.maxLines ?? 6,
        ),
        const SizedBox(height: AionSpacing.sp12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _SubmitButton(
              label: widget.submitLabel ?? '',
              enabled: _hasText,
              onTap: widget.onSubmit,
            ),
          ],
        ),
      ],
    );
  }
}

/// The 38×38 leading badge — accent tint fill, full-accent icon. Per
/// design.md §4.1.
class _CardBadge extends StatelessWidget {
  const _CardBadge({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: t.fillAlpha),
        borderRadius: BorderRadius.all(AionRadius.md),
      ),
      child: SizedBox(
        width: 38,
        height: 38,
        child: Center(child: PhosphorIcon(icon, size: 20, color: accent)),
      ),
    );
  }
}

/// A continuously-spinning `circle-notch` icon — the one-tap cards'
/// in-flight indicator (design.md §4.3/§4.4).
class _SpinningIcon extends StatefulWidget {
  const _SpinningIcon({required this.color});

  final Color color;

  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: PhosphorIcon(
        PhosphorIcons.circleNotchLight,
        size: 14,
        color: widget.color,
      ),
    );
  }
}

/// The two inline-input purposes' text field — the sanctioned bare
/// `TextField` wrapped in a transparent `Material` ancestor (design.md's
/// "Hard constraint — no Material" exception), styled from tokens
/// rather than reusing `AppTextField` since the accent-colored focus
/// ring/`background` fill here are specific to this card, not
/// `AppTextField`'s fixed styling.
class _InlineInputField extends StatefulWidget {
  const _InlineInputField({
    required this.controller,
    required this.placeholder,
    required this.accent,
    required this.minLines,
    required this.maxLines,
  });

  final TextEditingController controller;
  final String placeholder;
  final Color accent;
  final int minLines;
  final int maxLines;

  @override
  State<_InlineInputField> createState() => _InlineInputFieldState();
}

class _InlineInputFieldState extends State<_InlineInputField> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final borderColor = _isFocused ? widget.accent : c.border;
    final borderWidth = _isFocused ? 1.5 : 1.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.background,
        border: Border.all(color: borderColor, width: borderWidth),
        borderRadius: BorderRadius.all(AionRadius.md),
        boxShadow: _isFocused
            ? AionShadows.focus(c, t.isDark, color: widget.accent)
            : const [],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Material(
          type: MaterialType.transparency,
          child: Focus(
            onFocusChange: (focused) => setState(() => _isFocused = focused),
            child: TextField(
              controller: widget.controller,
              minLines: widget.minLines,
              maxLines: widget.maxLines,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: AionText.body.copyWith(color: c.textPrimary),
              decoration: null,
              cursorColor: c.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The inline-input submit button — the app's standard primary button
/// (`primary` fill, not the entry's own accent), disabled until
/// [enabled]. Per design.md §4.2.1/§4.2.2.
class _SubmitButton extends StatefulWidget {
  const _SubmitButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  State<_SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends State<_SubmitButton> {
  bool _isHovered = false;
  bool _isPressed = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    final fill = !widget.enabled
        ? c.primary.withValues(alpha: 0.38)
        : (_isHovered || _isPressed)
        ? c.primaryHover
        : c.primary;
    final foreground = const Color(0xFFFFFFFF).withValues(
      alpha: widget.enabled ? 1.0 : 0.85,
    );
    final boxShadow = _isFocused && widget.enabled
        ? AionShadows.focus(c, t.isDark)
        : const <BoxShadow>[];

    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.all(AionRadius.md),
        boxShadow: boxShadow,
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.label,
              style: AionText.button.copyWith(color: foreground),
            ),
            const SizedBox(width: 7),
            PhosphorIcon(
              PhosphorIcons.arrowUpLight,
              size: 15,
              color: foreground,
            ),
          ],
        ),
      ),
    );

    if (!widget.enabled) {
      return IgnorePointer(child: button);
    }

    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: FocusableActionDetector(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap?.call();
                return null;
              },
            ),
          },
          onShowFocusHighlight: (value) => setState(() => _isFocused = value),
          child: GestureDetector(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            child: AnimatedScale(
              scale: _isPressed ? 0.97 : 1.0,
              duration: const Duration(milliseconds: 90),
              child: button,
            ),
          ),
        ),
      ),
    );
  }
}
