// presentation/widgets/ticket_parent_picker.dart — Reusable ticket-parent picker overlay (presentation layer).

import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_overflow_menu.dart';

/// Which visual treatment [TicketParentPicker] renders for its trigger
/// control. Both variants open the same overlay (§[TicketParentPicker]) —
/// only the closed-state appearance differs.
enum TicketParentPickerVariant {
  /// The compact inline trigger used on `TicketDetailScreen`: a small
  /// "+ PARENT" placeholder or a resolved `key — title` row.
  inline,

  /// The full-width, `AppDropdown`-style form-field trigger used on
  /// `CreateTicketScreen`, matching the sibling Type/Priority fields.
  formField,
}

/// Builds a "Grandparent / Parent" breadcrumb string for [ticket] by
/// walking `parentId` upward through [byId] (an id-keyed index of the
/// same candidate list the picker already fetched). Returns null if
/// [ticket] has no parent. Stops after [maxDepth] hops (default 8) as a
/// defensive bound — cycles shouldn't exist given
/// `TicketsCubit.updateTicketParent`'s validation, but this keeps the UI
/// from hanging if one ever slips through.
String? ancestorBreadcrumb(
  Ticket ticket,
  Map<String, Ticket> byId, {
  int maxDepth = 8,
}) {
  final segments = <String>[];
  var currentParentId = ticket.parentId;
  var hops = 0;
  while (currentParentId != null && hops < maxDepth) {
    final parent = byId[currentParentId];
    if (parent == null) break; // ancestor outside the fetched set
    segments.add(parent.title);
    currentParentId = parent.parentId;
    hops++;
  }
  if (segments.isEmpty) return null;
  return segments.reversed.join('  /  ');
}

/// Returns the [AionColors] accent for [type]'s type-square/chip fill.
Color _typeAccent(AionColors c, TicketType type) => switch (type) {
  TicketType.story => c.typeStory,
  TicketType.epic => c.typeEpic,
  _ => c.typeTask,
};

/// Overlay-picker for choosing a ticket's structural parent (`parentId`).
/// Renders one of two trigger appearances depending on [variant]: a
/// compact inline "+ PARENT" trigger (`TicketDetailScreen`'s reparent
/// flow) or a full-width form-field trigger (`CreateTicketScreen`'s
/// parent field). Tapping either opens a searchable, scrollable overlay
/// list of candidates (supplied by [candidatesLoader], already excluding
/// whatever the caller doesn't want offered — e.g. self and descendants
/// for an existing ticket) plus a "No parent" row to clear the selection.
/// Not built on [SelectionMenu] — that widget renders an unbounded,
/// non-scrolling, non-searchable list, which doesn't scale to an
/// open-ended ticket set. Follows [TicketOverflowMenu]'s
/// `Overlay`/`LayerLink`/`CompositedTransformFollower`/`mounted`-guard
/// mechanics instead.
class TicketParentPicker extends StatefulWidget {
  /// Creates a [TicketParentPicker].
  const TicketParentPicker({
    super.key,
    required this.ticketType,
    required this.currentParentId,
    required this.candidatesLoader,
    required this.onParentSelected,
    this.variant = TicketParentPickerVariant.inline,
    this.isDisabled = false,
    this.errorText,
  });

  /// The type of the ticket being edited/created. Callers gate whether to
  /// build this widget at all when [ticketType] is [TicketType.epic]
  /// (epics never take a parent) — the picker itself doesn't check this.
  final TicketType ticketType;

  /// The ticket's current parent id, if any. Drives the trigger's
  /// resolved-title display and the overlay's "current selection" check
  /// mark.
  final String? currentParentId;

  /// Fetches the candidate list to show in the overlay. Each call site
  /// supplies its own semantics: an existing ticket passes
  /// `TicketsCubit.getValidParentCandidates(ticket)` (excludes self and
  /// descendants); a not-yet-created ticket passes
  /// `TicketsCubit.getAllTickets()` (nothing to exclude yet).
  final Future<List<Ticket>> Function() candidatesLoader;

  /// Called with the chosen parent id (`null` clears it) when the user
  /// picks a row. The caller decides whether that means an immediate
  /// persistence call (`TicketDetailScreen`) or just local form state
  /// (`CreateTicketScreen`, deferred until submit).
  final ValueChanged<String?> onParentSelected;

  /// Which trigger appearance to render. Defaults to
  /// [TicketParentPickerVariant.inline].
  final TicketParentPickerVariant variant;

  /// Renders the [TicketParentPickerVariant.formField] trigger's disabled
  /// state (50% opacity, muted glyphs/text, `IgnorePointer`) and blocks
  /// opening the overlay. Meaningful only for that variant — the compact
  /// inline trigger has no disabled treatment in the design spec. Callers
  /// typically wire this to their own submit-in-flight state (e.g.
  /// `CreateTicketScreen`'s `_isSubmitting`).
  final bool isDisabled;

  /// When non-null, renders the [TicketParentPickerVariant.formField]
  /// trigger's error state (danger-colored border/ring) with this text as
  /// a helper line below the control. Meaningful only for that variant.
  /// `null` (the default) means no error is shown.
  final String? errorText;

  @override
  State<TicketParentPicker> createState() => _TicketParentPickerState();
}

class _TicketParentPickerState extends State<TicketParentPicker> {
  final LayerLink _layerLink = LayerLink();
  final TextEditingController _searchController = TextEditingController();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  /// Valid reparent candidates, fetched on mount (and re-fetched whenever
  /// [TicketParentPicker.ticketType] changes, see [didUpdateWidget]) so the
  /// trigger can resolve the current parent's title without waiting for
  /// the overlay to open. `null` while a fetch is in flight.
  List<Ticket>? _candidates;

  @override
  void initState() {
    super.initState();
    _loadCandidates();
    _searchController.addListener(_handleSearchChanged);
  }

  /// Re-fetches candidates when [TicketParentPicker.ticketType] changes —
  /// candidates depend on `ticketType` via [TicketParentPicker.candidatesLoader],
  /// and `CreateTicketScreen` can change it after this widget is mounted
  /// (its type dropdown), which would otherwise leave a stale candidate
  /// list from the type selected at first build.
  @override
  void didUpdateWidget(covariant TicketParentPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ticketType != oldWidget.ticketType) {
      _loadCandidates();
    }
  }

  Future<void> _loadCandidates() async {
    final candidates = await widget.candidatesLoader();
    if (!mounted) return;
    setState(() => _candidates = candidates);
    _overlayEntry?.markNeedsBuild();
  }

  void _handleSearchChanged() {
    _overlayEntry?.markNeedsBuild();
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
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
      builder: (overlayContext) {
        final query = _searchController.text.trim().toLowerCase();
        final candidates = _candidates;
        final filtered = candidates?.where(
          (cand) =>
              query.isEmpty ||
              cand.ticketId.toLowerCase().contains(query) ||
              cand.title.toLowerCase().contains(query),
        ).toList();
        final byId = <String, Ticket>{
          for (final cand in candidates ?? const <Ticket>[]) cand.id: cand,
        };

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
                      minWidth: 320,
                      maxWidth: 320,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AionSpacing.sp12),
                          child: AppTextField(
                            controller: _searchController,
                            hintText: overlayContext
                                .l10n
                                .ticketDetailParentSearchHint,
                          ),
                        ),
                        Container(color: c.border, height: 1),
                        _NoParentRow(
                          isCurrent: widget.currentParentId == null,
                          onTap: () => _commit(null),
                        ),
                        Container(color: c.border, height: 1),
                        if (candidates == null)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: AionSpacing.sp32,
                            ),
                            child: Center(child: AppSpinner()),
                          )
                        else if (filtered!.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AionSpacing.sp32,
                            ),
                            child: Center(
                              child: Text(
                                overlayContext
                                    .l10n
                                    .ticketDetailParentNoResults,
                                style: AionText.bodySm.copyWith(
                                  color: c.textMuted,
                                ),
                              ),
                            ),
                          )
                        else
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 320),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final candidate = filtered[index];
                                return _CandidateRow(
                                  ticket: candidate,
                                  breadcrumb: ancestorBreadcrumb(
                                    candidate,
                                    byId,
                                  ),
                                  onTap: () => _commit(candidate.id),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
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

  void _commit(String? parentId) {
    widget.onParentSelected(parentId);
    _removeOverlay();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    // Guards against setState-after-dispose — the same class of bug
    // project.md's AppDropdown overlay-dismiss crash note warns about.
    if (mounted) {
      setState(() => _isOpen = false);
    } else {
      _isOpen = false;
    }
  }

  /// Looks up the display title for [parentId] among the already-loaded
  /// [_candidates] — the current parent is always present there (it's
  /// necessarily an ancestor of the ticket being edited, never excluded
  /// by [TicketParentPicker.candidatesLoader]'s self/descendant filter,
  /// or simply present in full for the create-flow's unfiltered loader).
  Ticket? _resolveParent(String parentId) {
    final candidates = _candidates;
    if (candidates == null) return null;
    for (final candidate in candidates) {
      if (candidate.id == parentId) return candidate;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final parentId = widget.currentParentId;
    final resolvedParent = parentId == null ? null : _resolveParent(parentId);

    final trigger = switch (widget.variant) {
      TicketParentPickerVariant.inline => _buildInlineTrigger(
        c,
        resolvedParent,
      ),
      TicketParentPickerVariant.formField => _buildFormFieldTrigger(
        c,
        resolvedParent,
      ),
    };

    final control = CompositedTransformTarget(
      link: _layerLink,
      child: Semantics(
        button: true,
        enabled: !widget.isDisabled,
        label: context.l10n.ticketDetailChangeParent,
        child: FocusableActionDetector(
          enabled: !widget.isDisabled,
          onShowFocusHighlight: (focused) =>
              setState(() => _isFocused = focused),
          onShowHoverHighlight: (hovered) =>
              setState(() => _isHovered = hovered),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _toggleOverlay();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapCancel: () => setState(() => _isPressed = false),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTap: _toggleOverlay,
            child: IgnorePointer(ignoring: widget.isDisabled, child: trigger),
          ),
        ),
      ),
    );

    if (widget.variant != TicketParentPickerVariant.formField ||
        widget.errorText == null) {
      return control;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        control,
        const SizedBox(height: 4),
        Text(
          widget.errorText!,
          style: AionText.bodySm.copyWith(color: c.danger),
        ),
      ],
    );
  }

  /// Compact "+ PARENT" / resolved key-title trigger, used on
  /// `TicketDetailScreen`.
  Widget _buildInlineTrigger(AionColors c, Ticket? resolvedParent) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _isOpen ? c.surfaceHover : const Color(0x00000000),
        borderRadius: BorderRadius.all(AionRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AionSpacing.sp8,
          vertical: 4,
        ),
        child: widget.currentParentId == null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PhosphorIcon(
                    PhosphorIcons.plusLight,
                    size: 12,
                    color: c.textMuted,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    context.l10n.ticketDetailAddParent,
                    style: AionText.label.copyWith(color: c.textMuted),
                  ),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PhosphorIcon(
                    PhosphorIcons.gitBranchLight,
                    size: 14,
                    color: c.textMuted,
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: resolvedParent?.ticketId ?? '…',
                            style: AionText.key.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                          TextSpan(
                            text: '  —  ',
                            style: AionText.bodySm.copyWith(
                              color: c.textMuted,
                            ),
                          ),
                          TextSpan(
                            text: resolvedParent?.title ?? '',
                            style: AionText.bodySm.copyWith(
                              color: c.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// Full-width, `AppDropdown`-style form-field trigger, used on
  /// `CreateTicketScreen`. Renders [TicketParentPicker.isDisabled]'s
  /// muted/`0.5`-opacity treatment and [TicketParentPicker.errorText]'s
  /// danger-colored border/ring, per Component Spec §2.3.
  Widget _buildFormFieldTrigger(AionColors c, Ticket? resolvedParent) {
    final hasError = widget.errorText != null;
    final isActive = _isFocused || _isOpen;
    final borderColor = hasError
        ? c.danger
        : isActive
        ? c.primary
        : _isHovered
        ? c.borderStrong
        : c.border;
    final borderWidth = hasError || isActive ? 1.5 : 1.0;
    final glyphColor = _isHovered || isActive
        ? c.textSecondary
        : c.textMuted;
    final ringColor = hasError ? c.danger : c.primary;

    return Opacity(
      opacity: widget.isDisabled ? 0.5 : 1.0,
      child: AnimatedScale(
        scale: _isPressed ? 0.99 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow: hasError || isActive
                ? [
                    BoxShadow(
                      color: ringColor.withValues(
                        alpha: t.isDark ? 0.30 : 0.16,
                      ),
                      spreadRadius: 3,
                    ),
                  ]
                : null,
          ),
        child: widget.currentParentId == null
            ? Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    PhosphorIcon(
                      PhosphorIcons.gitBranchLight,
                      size: 15,
                      color: glyphColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.l10n.ticketDetailParentFieldPlaceholder,
                        style: AionText.body.copyWith(color: c.textMuted),
                      ),
                    ),
                    PhosphorIcon(
                      PhosphorIcons.caretDownLight,
                      size: 12,
                      color: glyphColor,
                    ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 11, 9),
                child: Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.surfaceHover,
                        border: Border.all(color: c.border, width: 1),
                        borderRadius: BorderRadius.all(AionRadius.sm),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        child: Text(
                          resolvedParent?.ticketId ?? '…',
                          style: AionText.key.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        resolvedParent?.title ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AionText.bodySm.copyWith(color: c.textPrimary),
                      ),
                    ),
                    if (resolvedParent != null) ...[
                      const SizedBox(width: 8),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: _typeAccent(c, resolvedParent.type),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const SizedBox(width: 8, height: 8),
                      ),
                    ],
                    const SizedBox(width: 2),
                    PhosphorIcon(
                      PhosphorIcons.caretDownLight,
                      size: 11,
                      color: glyphColor,
                    ),
                  ],
                ),
              ),
        ),
      ),
    );
  }

  AionThemeData get t => ThemeScope.of(context);
}

/// The "No parent" row always shown first in [TicketParentPicker]'s
/// overlay list, letting the user clear the parent selection back to
/// `null`. Shows a check mark and primary-tinted label when [isCurrent]
/// is true.
class _NoParentRow extends StatefulWidget {
  /// Creates a [_NoParentRow].
  const _NoParentRow({required this.isCurrent, required this.onTap});

  /// Whether the ticket currently has no parent — renders the
  /// "selected" treatment when true.
  final bool isCurrent;

  /// Called when the row is tapped.
  final VoidCallback onTap;

  @override
  State<_NoParentRow> createState() => _NoParentRowState();
}

class _NoParentRowState extends State<_NoParentRow> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final fill = _isPressed
        ? c.border
        : _isHovered
        ? c.surfaceHover
        : const Color(0x00000000);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapCancel: () => setState(() => _isPressed = false),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(color: fill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            child: Row(
              children: [
                PhosphorIcon(
                  PhosphorIcons.xCircleLight,
                  size: 14,
                  color: c.textMuted,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    context.l10n.ticketDetailNoParentOption,
                    style: AionText.bodySm.copyWith(
                      color: widget.isCurrent ? c.primary : c.textMuted,
                    ),
                  ),
                ),
                if (widget.isCurrent)
                  PhosphorIcon(
                    PhosphorIcons.checkLight,
                    size: 14,
                    color: c.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single selectable candidate row in [TicketParentPicker]'s overlay
/// list — a fixed-width monospace ticket key, the ticket's title, an
/// optional ancestor-breadcrumb subtitle (see [ancestorBreadcrumb]), and
/// a trailing type-accent square.
class _CandidateRow extends StatefulWidget {
  /// Creates a [_CandidateRow] for [ticket].
  const _CandidateRow({
    required this.ticket,
    required this.breadcrumb,
    required this.onTap,
  });

  /// The candidate ticket this row represents.
  final Ticket ticket;

  /// The ancestor-path breadcrumb to show under the title, or `null` for
  /// a root-level candidate (no breadcrumb line rendered).
  final String? breadcrumb;

  /// Called when the row is tapped.
  final VoidCallback onTap;

  @override
  State<_CandidateRow> createState() => _CandidateRowState();
}

class _CandidateRowState extends State<_CandidateRow> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final fill = _isPressed
        ? c.border
        : _isHovered
        ? c.surfaceHover
        : const Color(0x00000000);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapCancel: () => setState(() => _isPressed = false),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(color: fill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: SizedBox(
                    width: 52,
                    child: Text(
                      widget.ticket.ticketId,
                      style: AionText.key.copyWith(color: c.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.ticket.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AionText.bodySm.copyWith(color: c.textPrimary),
                      ),
                      if (widget.breadcrumb != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.breadcrumb!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AionText.breadcrumb.copyWith(
                            color: c.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _typeAccent(c, widget.ticket.type),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const SizedBox(width: 8, height: 8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
