// design_system/molecules/severity_badge.dart — SeverityBadge + severity picker (design-system layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/tokens/aion_colors.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_shadows.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';
import 'package:aion/features/tickets/domain/enums/ticket_severity.dart';

/// Returns the display label for [severity] (e.g. `"Critical"`). Single
/// one-place-mapping for every screen that renders a severity as text
/// (the severity picker, [SeverityBadge]'s pre-uppercased chip label).
String severityLabel(BuildContext context, TicketSeverity severity) {
  final l10n = context.l10n;
  return switch (severity) {
    TicketSeverity.critical => l10n.ticketSeverityCritical,
    TicketSeverity.high => l10n.ticketSeverityHigh,
    TicketSeverity.medium => l10n.ticketSeverityMedium,
    TicketSeverity.low => l10n.ticketSeverityLow,
  };
}

/// The `severity.{level}Bg`/`Fg` pair for [severity], from [AionColors].
({Color bg, Color fg}) _severityColors(TicketSeverity severity, AionColors c) {
  return switch (severity) {
    TicketSeverity.critical => (bg: c.severity.criticalBg, fg: c.severity.criticalFg),
    TicketSeverity.high => (bg: c.severity.highBg, fg: c.severity.highFg),
    TicketSeverity.medium => (bg: c.severity.mediumBg, fg: c.severity.mediumFg),
    TicketSeverity.low => (bg: c.severity.lowBg, fg: c.severity.lowFg),
  };
}

/// A small pill showing a [TicketType.bug](../../features/tickets/domain/enums/ticket_type.dart)
/// ticket's severity: a leading filled triangle marker plus an
/// uppercase label, colored by [severity]'s `AionSeverityColors` entry.
/// Parallel to `PriorityBadge`, but deliberately distinguished from it by
/// two independent cues (per `AIO-425`
/// §2.1): a single-temperature "ember ramp" palette (rather than
/// `PriorityBadge`'s four-hue set) and the leading triangle marker, which
/// `PriorityBadge` has no equivalent of.
///
/// [severity] is nullable — `null` renders the unselected/placeholder
/// variant (dashed border, outline-only triangle, muted "SEVERITY"/
/// "NOT SET" label) for a not-yet-set severity.
class SeverityBadge extends StatelessWidget {
  /// Creates a [SeverityBadge] for [severity]. [isLarge] selects the
  /// detail-screen-sized variant (`false`, default, renders the
  /// ticket-row/create-form-compact size). [placeholderLabel] is shown
  /// only when [severity] is `null`, defaulting to `"SEVERITY"`.
  const SeverityBadge({
    super.key,
    required this.severity,
    this.isLarge = false,
    this.placeholderLabel,
  });

  /// The severity to render, or `null` for the unselected/placeholder
  /// variant.
  final TicketSeverity? severity;

  /// Whether to use the larger detail-screen sizing (`true`) or the
  /// compact ticket-row/create-form sizing (`false`, default).
  final bool isLarge;

  /// Label shown when [severity] is `null`. Defaults to `"SEVERITY"`.
  final String? placeholderLabel;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final level = severity;

    final Color fill;
    final Color fg;
    final String label;
    final bool dashed;
    if (level == null) {
      fill = c.surfaceHover;
      fg = c.textMuted;
      label = placeholderLabel ?? context.l10n.ticketSeverityPlaceholder;
      dashed = true;
    } else {
      final colors = _severityColors(level, c);
      fill = colors.bg;
      fg = colors.fg;
      label = severityLabel(context, level).toUpperCase();
      dashed = false;
    }

    final trianglePaint = _SeverityTrianglePainter(color: fg, filled: !dashed);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(isLarge ? 6 : 5),
        border: dashed
            ? Border.all(color: c.borderStrong, width: 1)
            : null,
      ),
      child: Padding(
        padding: isLarge
            ? const EdgeInsets.fromLTRB(9, 5, 11, 5)
            : const EdgeInsets.fromLTRB(6, 3, 8, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              size: isLarge ? const Size(9, 8) : const Size(7, 6),
              painter: trianglePaint,
            ),
            SizedBox(width: isLarge ? 5 : 4),
            Text(
              label,
              style:
                  (isLarge ? AionText.priorityBig : AionText.prioritySm)
                      .copyWith(color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws the small ▲ hazard marker used by [SeverityBadge] — a filled
/// triangle for a set severity, an outline-only one for the placeholder
/// variant. `CustomPaint`, never a Material `Icon`.
class _SeverityTrianglePainter extends CustomPainter {
  const _SeverityTrianglePainter({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final paint = Paint()..color = color;
    if (filled) {
      paint.style = PaintingStyle.fill;
    } else {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SeverityTrianglePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.filled != filled;
}

/// A trigger + overlay picker for choosing a [TicketSeverity], shared by
/// `CreateTicketScreen`'s Bug-fields block and the ticket detail screen's
/// "Bug details" section severity row (`AIO-425`
/// §3–§5.2). Structurally mirrors `AppDropdown`'s
/// `CompositedTransformTarget`/`OverlayEntry` overlay mechanics, re-skinned
/// to render a [SeverityBadge] per row instead of a plain label — plain
/// `AppDropdown<T>` has no per-item leading-widget slot, so it can't
/// render this itself.
class SeverityPicker extends StatefulWidget {
  /// Creates a [SeverityPicker]. [value] is the currently selected
  /// severity, `null` if none has been chosen yet. [isLarge] selects
  /// whether the trigger is the large detail-screen badge (`true`) or
  /// the compact create-form dropdown box (`false`, default). [labelText]/
  /// [isRequired]/[errorText] are only meaningful in the compact
  /// (create-form) presentation — the large trigger has no label row of
  /// its own (the caller supplies one, e.g. the "SEVERITY" field caption
  /// in the detail screen).
  const SeverityPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.isLarge = false,
    this.labelText,
    this.isRequired = false,
    this.errorText,
    this.isDisabled = false,
  });

  /// The currently selected severity, or `null` if none is chosen yet.
  final TicketSeverity? value;

  /// Called with the newly selected severity when the user picks one.
  final ValueChanged<TicketSeverity> onChanged;

  /// Whether the trigger is the large detail-screen badge (`true`) or
  /// the compact create-form dropdown box (`false`, default).
  final bool isLarge;

  /// Label rendered above the compact (create-form) trigger. Ignored
  /// when [isLarge] is `true`.
  final String? labelText;

  /// Whether to render a required-field marker next to [labelText], and
  /// (combined with [errorText]) show the error-state border/ring.
  /// Ignored when [isLarge] is `true`.
  final bool isRequired;

  /// Helper text shown under the compact trigger in the error state
  /// (e.g. "Choose a severity"). `null` means no error is currently
  /// shown. Ignored when [isLarge] is `true`.
  final String? errorText;

  /// Disables the trigger (e.g. while a form is submitting).
  final bool isDisabled;

  @override
  State<SeverityPicker> createState() => _SeverityPickerState();
}

class _SeverityPickerState extends State<SeverityPicker> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  void _toggleOverlay() {
    if (widget.isDisabled) return;
    if (_isOpen) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final overlay = Overlay.of(context);

    _overlayEntry = OverlayEntry(
      builder: (context) {
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
              targetAnchor: Alignment.bottomLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.all(AionRadius.lg),
                  border: Border.all(color: c.borderStrong, width: 1),
                  boxShadow: AionShadows.card(c, t.isDark),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: TicketSeverity.values.map((level) {
                      final selected = level == widget.value;
                      return GestureDetector(
                        onTap: () {
                          widget.onChanged(level);
                          _removeOverlay();
                        },
                        child: Container(
                          color: selected ? c.surfaceHover : null,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 9,
                          ),
                          child: Row(
                            children: [
                              SeverityBadge(severity: level),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  severityLabel(context, level),
                                  style: AionText.bodySm.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: c.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) {
      setState(() => _isOpen = false);
    } else {
      _isOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    final trigger = widget.isLarge
        ? SeverityBadge(severity: widget.value, isLarge: true)
        : _CompactTrigger(
            value: widget.value,
            isOpen: _isOpen,
            hasError: widget.errorText != null,
            isDisabled: widget.isDisabled,
          );

    return CompositedTransformTarget(
      link: _layerLink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.isLarge && widget.labelText != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AionSpacing.sp4),
              child: Row(
                children: [
                  Text(
                    widget.labelText!,
                    style: AionText.label.copyWith(color: c.textSecondary),
                  ),
                  if (widget.isRequired)
                    Text(
                      context.l10n.commonRequiredMarker,
                      style: AionText.label.copyWith(color: c.danger),
                    ),
                ],
              ),
            ),
          GestureDetector(
            onTap: _toggleOverlay,
            child: trigger,
          ),
          if (!widget.isLarge && widget.errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                widget.errorText!,
                style: AionText.bodySm.copyWith(color: c.danger),
              ),
            ),
        ],
      ),
    );
  }
}

/// The compact create-form dropdown-box trigger for [SeverityPicker] —
/// a `SeverityBadge`/placeholder plus a trailing chevron, matching the
/// sibling `AppDropdown`s' box geometry
/// (`AIO-425` §4.2).
class _CompactTrigger extends StatelessWidget {
  const _CompactTrigger({
    required this.value,
    required this.isOpen,
    required this.hasError,
    required this.isDisabled,
  });

  final TicketSeverity? value;
  final bool isOpen;
  final bool hasError;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final borderColor = hasError
        ? c.danger
        : isOpen
        ? c.primary
        : c.border;
    final borderWidth = hasError || isOpen ? 1.5 : 1.0;

    return Opacity(
      opacity: isDisabled ? 0.5 : 1,
      child: IgnorePointer(
        ignoring: isDisabled,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.all(AionRadius.lg),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            child: Row(
              children: [
                SeverityBadge(severity: value),
                const Spacer(),
                PhosphorIcon(
                  isOpen ? PhosphorIcons.caretUpLight : PhosphorIcons.caretDownLight,
                  size: 12,
                  color: c.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
