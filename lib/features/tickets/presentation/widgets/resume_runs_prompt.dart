// presentation/widgets/resume_runs_prompt.dart — ResumeRunsPrompt banner (presentation layer).

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';

/// A one-time-per-launch inline banner pinned to the top of the Board
/// view, listing coding-execution runs `TicketsCubit.restoreExecutionQueue`
/// found interrupted by an app restart under
/// `AutomationConfidence.gated`. Resume re-enqueues every surviving entry
/// (`TicketsCubit.resumePendingExecutions`); Dismiss falls back to
/// `AutomationConfidence.manual`'s behavior — clears the snapshot and
/// relies on the existing orphaned/stalled per-ticket retry banner
/// (`TicketsCubit.dismissPendingResumePrompt`). Rendered only while
/// `TicketsLoaded.pendingResumePrompt` is non-empty — vanishes on its own
/// once either action clears it. Purpose-built to the Claude Design
/// export's exact geometry (design.md §3) rather than `BannerShell` — that
/// shared shell's fixed padding/single-color border doesn't match this
/// banner's `primaryWash` fill + distinct `primary`-alpha border, and its
/// action row has no equivalent elsewhere to reuse. Added for
/// `AIO-1400`; see that change's design.md §3.
class ResumeRunsPrompt extends StatelessWidget {
  /// Creates a [ResumeRunsPrompt] listing [tickets] — the interrupted
  /// runs awaiting a Resume/Dismiss decision.
  const ResumeRunsPrompt({super.key, required this.tickets});

  /// The interrupted Task/Bug tickets to list. Only the first three
  /// render as individual lines (design.md §3.1.1) — the rest collapse
  /// into a trailing "…and N more" line.
  final List<Ticket> tickets;

  /// How many individual run lines render before collapsing the rest
  /// into a trailing "…and N more" line (design.md §3.1.1).
  static const _maxVisibleRuns = 3;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isDark = t.isDark;
    final cubit = context.read<TicketsCubit>();

    final visible = tickets.take(_maxVisibleRuns).toList();
    final overflow = tickets.length - visible.length;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.primaryWash(isDark),
        border: Border.all(color: c.primary.withValues(alpha: isDark ? 0.42 : 0.28)),
        borderRadius: const BorderRadius.all(AionRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  // Pins the glyph to the title's cap-height rather than
                  // the (potentially multi-line) text column's full
                  // height — design.md §3.2's "pinned to start".
                  padding: const EdgeInsets.only(top: 1),
                  child: PhosphorIcon(
                    PhosphorIcons.arrowClockwiseLight,
                    size: 18,
                    color: c.primary,
                  ),
                ),
                const SizedBox(width: AionSpacing.sp12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.resumeRunsPromptTitle(tickets.length),
                        style: AionText.cardTitle.copyWith(color: c.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      for (final ticket in visible)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: _RunLine(ticket: ticket),
                        ),
                      if (overflow > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            context.l10n.resumeRunsPromptMore(overflow),
                            style: AionText.bodySm.copyWith(color: c.textMuted),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AionSpacing.sp12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _DismissButton(
                  label: context.l10n.resumeRunsPromptDismissAction,
                  onPressed: cubit.dismissPendingResumePrompt,
                ),
                const SizedBox(width: AionSpacing.sp8),
                _ResumeButton(
                  label: context.l10n.resumeRunsPromptResumeAction,
                  onPressed: cubit.resumePendingExecutions,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One interrupted-run line inside [ResumeRunsPrompt]'s header — a
/// monospace ticket-id chip beside the ticket's title, ellipsized to one
/// line. Design.md §3.1.1.
class _RunLine extends StatelessWidget {
  const _RunLine({required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.surfaceHover,
            borderRadius: const BorderRadius.all(Radius.circular(5)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              ticket.ticketId,
              style: AionText.key.copyWith(color: c.textSecondary),
            ),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            ticket.title,
            style: AionText.bodySm.copyWith(color: c.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// [ResumeRunsPrompt]'s primary "Resume" action — solid `primary` fill
/// with the app's FAB-style glow, an arrow-clockwise glyph beside the
/// label. Disables itself (rather than relying on the cubit for a busy
/// flag) once tapped, for the run of [onPressed] — mirrors
/// `ExecutionCancelControl`'s own local hover/focus/press statefulness.
/// Design.md §3.3/§3.4.
class _ResumeButton extends StatefulWidget {
  const _ResumeButton({required this.label, required this.onPressed});

  final String label;
  final Future<void> Function() onPressed;

  @override
  State<_ResumeButton> createState() => _ResumeButtonState();
}

class _ResumeButtonState extends State<_ResumeButton> {
  bool _isHovered = false;
  bool _isPressed = false;
  bool _isFocused = false;
  bool _isBusy = false;

  Future<void> _handleActivate() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    await widget.onPressed();
    if (mounted) setState(() => _isBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isDark = t.isDark;

    final Color fill;
    final Color foreground;
    final double glowBlur;
    final bool showGlow;
    if (_isBusy) {
      fill = c.primary.withValues(alpha: 0.45);
      foreground = const Color(0xFFFFFFFF).withValues(alpha: 0.55);
      showGlow = false;
      glowBlur = 18;
    } else if (_isPressed) {
      fill = c.primaryHover;
      foreground = const Color(0xFFFFFFFF);
      showGlow = false;
      glowBlur = 18;
    } else if (_isHovered) {
      fill = c.primaryHover;
      foreground = const Color(0xFFFFFFFF);
      showGlow = true;
      glowBlur = 22;
    } else {
      fill = c.primary;
      foreground = const Color(0xFFFFFFFF);
      showGlow = true;
      glowBlur = 18;
    }

    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: _isBusy
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: FocusableActionDetector(
          enabled: !_isBusy,
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                unawaited(_handleActivate());
                return null;
              },
            ),
          },
          onShowFocusHighlight: (value) => setState(() => _isFocused = value),
          child: GestureDetector(
            onTap: _isBusy ? null : () => unawaited(_handleActivate()),
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            child: AnimatedScale(
              scale: _isPressed ? 0.98 : 1.0,
              duration: const Duration(milliseconds: 80),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: const BorderRadius.all(AionRadius.md),
                  boxShadow: [
                    if (showGlow)
                      BoxShadow(
                        color: c.primary.withValues(alpha: isDark ? 0.60 : 0.45),
                        blurRadius: glowBlur,
                        spreadRadius: -9,
                        offset: const Offset(0, 8),
                      ),
                    if (_isFocused)
                      BoxShadow(
                        color: c.focusRing(isDark),
                        blurRadius: 0,
                        spreadRadius: 3,
                      ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PhosphorIcon(
                        PhosphorIcons.arrowClockwiseLight,
                        size: 15,
                        color: foreground,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        widget.label,
                        style: AionText.button.copyWith(color: foreground),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [ResumeRunsPrompt]'s secondary "Dismiss" action — text-only, no fill
/// or border at rest, matching the app's confirm/dismiss weight pairing.
/// Design.md §3.3/§3.4.
class _DismissButton extends StatefulWidget {
  const _DismissButton({required this.label, required this.onPressed});

  final String label;
  final Future<void> Function() onPressed;

  @override
  State<_DismissButton> createState() => _DismissButtonState();
}

class _DismissButtonState extends State<_DismissButton> {
  bool _isHovered = false;
  bool _isPressed = false;
  bool _isFocused = false;
  bool _isBusy = false;

  Future<void> _handleActivate() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    await widget.onPressed();
    if (mounted) setState(() => _isBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isDark = t.isDark;

    final Color fill;
    final Color textColor;
    if (_isBusy) {
      fill = const Color(0x00000000);
      textColor = c.textSecondary.withValues(alpha: 0.45);
    } else if (_isPressed) {
      fill = c.border;
      textColor = c.textPrimary;
    } else if (_isHovered) {
      fill = c.surfaceHover;
      textColor = c.textPrimary;
    } else {
      fill = const Color(0x00000000);
      textColor = c.textSecondary;
    }

    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: _isBusy
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: FocusableActionDetector(
          enabled: !_isBusy,
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                unawaited(_handleActivate());
                return null;
              },
            ),
          },
          onShowFocusHighlight: (value) => setState(() => _isFocused = value),
          child: GestureDetector(
            onTap: _isBusy ? null : () => unawaited(_handleActivate()),
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            child: AnimatedScale(
              scale: _isPressed ? 0.98 : 1.0,
              duration: const Duration(milliseconds: 80),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: const BorderRadius.all(AionRadius.md),
                  boxShadow: _isFocused
                      ? [
                          BoxShadow(
                            color: c.focusRing(isDark),
                            blurRadius: 0,
                            spreadRadius: 3,
                          ),
                        ]
                      : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Text(
                    widget.label,
                    style: AionText.button.copyWith(color: textColor),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
