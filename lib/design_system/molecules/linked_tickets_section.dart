// design_system/molecules/linked_tickets_section.dart — LinkedTicketsSection widget (design-system layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/molecules/selection_menu.dart';
import 'package:aion/design_system/tokens/aion_colors.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_shadows.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';
import 'package:aion/features/tickets/domain/entities/linked_ticket_ref.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// A ticket-detail section listing the board tickets (epic/story/task/
/// chat) a `page`/`resource`/`epic`/`story`/`task`/`bug` ticket links to
/// via `TicketLink`. Given [links] (each row's relationship *type*
/// alongside the other-side ticket — see [LinkedTicketRef]) and an
/// [onTap] callback, plus an optional header [trailing] control (e.g. a
/// link picker) — grouping logic (which links belong here vs.
/// [BacklinksSection]) and the actual link-creation call live in the
/// caller/[trailing] widget, not here. Each row also carries a remove
/// action ([onRemove]) and, unless it's read-only (see [linkTypeOptions]/
/// `_LinkRow._editable`), an inline type-change control ([onChangeType])
/// — added for `aion-arch/changes/ticket-link-management-ui` on top of
/// the original read-only row promoted from
/// `DocumentationLinkedTicketsSection` (per `project.md`'s Pattern 2).
/// Per `aion-arch/changes/ticket-link-management-ui/design.md`
/// ("Aion — Linked Ticket Relationships" Component Spec).
class LinkedTicketsSection extends StatelessWidget {
  /// Creates a [LinkedTicketsSection] listing [links].
  const LinkedTicketsSection({
    super.key,
    required this.links,
    required this.onTap,
    required this.onRemove,
    required this.onChangeType,
    required this.linkTypeOptions,
    this.trailing,
  });

  /// The linked tickets to render, most relevant order as provided by the
  /// caller. Each entry's [LinkedTicketRef.relativeType] is already
  /// resolved to read correctly from the viewing ticket's own side.
  final List<LinkedTicketRef> links;

  /// Called with a row's ticket id when it's tapped.
  final ValueChanged<String> onTap;

  /// Called with a row's underlying link id once its removal is
  /// confirmed via the row's remove-confirmation popover.
  final ValueChanged<String> onRemove;

  /// Called with a row's underlying link id and the newly picked
  /// *relative* type once a row's inline `_LinkTypeEditor` commits a
  /// selection. The caller is responsible for translating the relative
  /// selection back to the row's canonical (source-to-target) type
  /// (`ticket_link_direction.dart`'s `toCanonical`) before persisting it.
  final void Function(String linkId, TicketLinkType newRelativeType)
  onChangeType;

  /// The relative-type options a row's `_LinkTypeEditor` offers — the
  /// same set the viewing ticket's own link-creation flow already
  /// restricts to (e.g. `resource`'s `[TicketLinkType.relatesTo]`-only
  /// set), reused as-is for editing rather than a separately configured
  /// set. Never includes [TicketLinkType.duplicatedBy] (see
  /// `TicketLinkPicker.linkTypeOptions`'s dartdoc) — a row whose
  /// [LinkedTicketRef.relativeType] *is* `duplicatedBy` renders no edit
  /// control regardless of this list's contents (Component Spec §7's
  /// carve-out).
  final List<TicketLinkType> linkTypeOptions;

  /// The header's trailing "+ Add" affordance, e.g. a link picker.
  /// `null` renders no trailing control.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border, width: 1)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  context.l10n.documentationLinkedTicketsLabel,
                  style: AionText.caption.copyWith(color: c.textMuted),
                ),
                if (links.isNotEmpty) ...[
                  const SizedBox(width: AionSpacing.sp8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.surfaceHover,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        '${links.length}',
                        style: AionText.key.copyWith(color: c.textSecondary),
                      ),
                    ),
                  ),
                ],
                if (trailing != null) ...[const Spacer(), trailing!],
              ],
            ),
            const SizedBox(height: AionSpacing.sp12),
            if (links.isEmpty)
              Text(
                context.l10n.documentationLinkedTicketsEmpty,
                style: AionText.bodySm.copyWith(color: c.textMuted),
              )
            else
              Column(
                children: [
                  for (final link in links) ...[
                    _LinkRow(
                      link: link,
                      linkTypeOptions: linkTypeOptions,
                      onTap: () => onTap(link.ticket.id),
                      onRemove: () => onRemove(link.linkId),
                      onChangeType: (newType) =>
                          onChangeType(link.linkId, newType),
                    ),
                    if (link != links.last)
                      const SizedBox(height: AionSpacing.sp8),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// All eight non-task types resolve to their own dedicated token; only
// `task` itself falls through to the `typeTask` catch-all — mirrors
// `TypeChip`'s own switch. Kept as a top-level function (rather than
// `_LinkRowState`-private) so `_LinkTypeEditor`'s use elsewhere in this
// file doesn't need a second copy.
Color _typeColor(AionColors c, TicketType type) => switch (type) {
  TicketType.story => c.typeStory,
  TicketType.epic => c.typeEpic,
  TicketType.resource => c.typeResource,
  TicketType.page => c.typePage,
  TicketType.idea => c.typeIdea,
  TicketType.knownGap => c.typeKnownGap,
  TicketType.openQuestion => c.typeOpenQuestion,
  TicketType.release => c.typeRelease,
  TicketType.chat => c.typeChat,
  TicketType.bug => c.typeBug,
  _ => c.typeTask,
};

/// A single link row: type-color dot, mono ticket key, title, and (per
/// Component Spec §0–§3) a trailing [_RelationshipIndicator] plus
/// hover-revealed edit/remove actions. Component Spec §2.
class _LinkRow extends StatefulWidget {
  const _LinkRow({
    required this.link,
    required this.linkTypeOptions,
    required this.onTap,
    required this.onRemove,
    required this.onChangeType,
  });

  final LinkedTicketRef link;
  final List<TicketLinkType> linkTypeOptions;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final ValueChanged<TicketLinkType> onChangeType;

  @override
  State<_LinkRow> createState() => _LinkRowState();
}

class _LinkRowState extends State<_LinkRow> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;
  bool _isEditingType = false;
  bool _isConfirmingRemove = false;

  final LayerLink _removeButtonLink = LayerLink();
  OverlayEntry? _removeOverlayEntry;

  /// Component Spec §0's edit-affordance rule: a `duplicatedBy` row is
  /// always derived, never directly editable; every other row needs at
  /// least one *other* option in [LinkedTicketsSection.linkTypeOptions]
  /// to switch to (a single-option set, e.g. `resource`'s `relatesTo`-
  /// only, has nothing to offer).
  bool get _editable =>
      widget.link.relativeType != TicketLinkType.duplicatedBy &&
      widget.linkTypeOptions.any((t) => t != widget.link.relativeType);

  @override
  void dispose() {
    _removeOverlayEntry?.remove();
    _removeOverlayEntry = null;
    super.dispose();
  }

  void _openRemoveConfirmation() {
    final overlay = Overlay.of(context);
    _removeOverlayEntry = OverlayEntry(
      builder: (overlayContext) => _RemoveConfirmationOverlay(
        layerLink: _removeButtonLink,
        targetTicketKey: widget.link.ticket.ticketId,
        onCancel: _closeRemoveConfirmation,
        onConfirm: () {
          _closeRemoveConfirmation();
          widget.onRemove();
        },
      ),
    );
    overlay.insert(_removeOverlayEntry!);
    setState(() => _isConfirmingRemove = true);
  }

  void _closeRemoveConfirmation() {
    _removeOverlayEntry?.remove();
    _removeOverlayEntry = null;
    if (mounted) {
      setState(() => _isConfirmingRemove = false);
    } else {
      _isConfirmingRemove = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final link = widget.link;
    final ticket = link.ticket;
    final typeColor = _typeColor(c, ticket.type);
    final isRevealed = _isHovered || _isFocused;
    final isRaised = isRevealed || _isEditingType || _isConfirmingRemove;

    return Semantics(
      button: true,
      label: ticket.title,
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
            child: AnimatedScale(
              scale: _isPressed ? 0.995 : 1.0,
              duration: const Duration(milliseconds: 80),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: isRaised ? c.surfaceHover : c.surface,
                  border: Border.all(
                    color: isRaised ? c.borderStrong : c.border,
                    width: 1,
                  ),
                  borderRadius: BorderRadius.all(AionRadius.md),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AionSpacing.sp12,
                    vertical: AionSpacing.sp8 + 2,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: typeColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const SizedBox(width: 8, height: 8),
                      ),
                      const SizedBox(width: AionSpacing.sp8 + 2),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.surfaceHover,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            ticket.ticketId,
                            style: AionText.key.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AionSpacing.sp8 + 2),
                      Expanded(
                        child: Text(
                          ticket.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AionText.cardTitle.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (_isEditingType)
                        _LinkTypeEditor(
                          value: link.relativeType,
                          options: widget.linkTypeOptions,
                          onChanged: (newType) {
                            widget.onChangeType(newType);
                            setState(() => _isEditingType = false);
                          },
                          onDismiss: () =>
                              setState(() => _isEditingType = false),
                        )
                      else
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _RelationshipIndicator(
                              relativeType: link.relativeType,
                            ),
                            _RevealedRowActions(
                              revealed: isRevealed,
                              editable: _editable,
                              removeLayerLink: _removeButtonLink,
                              isConfirmingRemove: _isConfirmingRemove,
                              onEdit: () =>
                                  setState(() => _isEditingType = true),
                              onRemove: _openRemoveConfirmation,
                            ),
                          ],
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

/// The glyph + short label at the trailing end of every link row —
/// Component Spec §1. Non-interactive; hover/focus/active states belong
/// to the row and the controls that replace or sit beside it.
class _RelationshipIndicator extends StatelessWidget {
  const _RelationshipIndicator({required this.relativeType});

  final TicketLinkType relativeType;

  /// Whether [relativeType] is one of the two dependency relations
  /// (`blocks`/`blockedBy`), which read as *active/attention-worthy* in
  /// `textSecondary` — every other (associative) relation reads *quieter*
  /// in `textMuted`. Component Spec §1.2.
  bool get _isDirectional =>
      relativeType == TicketLinkType.blocks ||
      relativeType == TicketLinkType.blockedBy;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final tone = _isDirectional ? c.textSecondary : c.textMuted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 16,
          child: PhosphorIcon(relativeType.glyph, size: 14, color: tone),
        ),
        const SizedBox(width: 6),
        Text(relativeType.label(context), style: AionText.key.copyWith(color: tone)),
      ],
    );
  }
}

/// The hover-revealed edit (when [editable]) + remove action buttons
/// beside [_RelationshipIndicator] — Component Spec §2.3/§3. Collapses to
/// zero width and ignores pointer events while ![revealed], so it never
/// pushes the row's title when hidden.
class _RevealedRowActions extends StatelessWidget {
  const _RevealedRowActions({
    required this.revealed,
    required this.editable,
    required this.removeLayerLink,
    required this.isConfirmingRemove,
    required this.onEdit,
    required this.onRemove,
  });

  final bool revealed;
  final bool editable;
  final LayerLink removeLayerLink;
  final bool isConfirmingRemove;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    // Reveal via AnimatedAlign's widthFactor (0 -> 1) rather than
    // animating a literal pixel width directly: the buttons are a fixed
    // size and can't compress, so animating a `width` from 0 up to their
    // full extent would overflow the RenderFlex on every intermediate
    // frame. `Align` instead always lays its child out at its natural
    // size and only scales how much of that size counts toward this
    // widget's own reported width, which `ClipRect` then trims visually.
    return ClipRect(
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        alignment: Alignment.centerRight,
        widthFactor: revealed ? 1 : 0,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          opacity: revealed ? 1 : 0,
          child: IgnorePointer(
            ignoring: !revealed,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (editable) ...[
                  _EditButton(onTap: onEdit),
                  const SizedBox(width: 4),
                ],
                CompositedTransformTarget(
                  link: removeLayerLink,
                  child: _RemoveButton(
                    isActive: isConfirmingRemove,
                    onTap: onRemove,
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

/// The pencil-simple edit-trigger button — Component Spec §3.2.
class _EditButton extends StatefulWidget {
  const _EditButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_EditButton> createState() => _EditButtonState();
}

class _EditButtonState extends State<_EditButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    final Color fill;
    final Color iconColor;
    if (_isPressed) {
      fill = c.border;
      iconColor = c.textPrimary;
    } else if (_isHovered) {
      fill = c.surfaceHover;
      iconColor = c.textPrimary;
    } else {
      fill = const Color(0x00000000);
      iconColor = c.textSecondary;
    }

    return Semantics(
      button: true,
      label: context.l10n.linkedTicketsChangeTypeAction,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.all(AionRadius.iconBtnSm),
            ),
            child: Center(
              child: PhosphorIcon(
                PhosphorIcons.pencilSimpleLight,
                size: 16,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The trash-simple remove-trigger button — Component Spec §3.3. Holds
/// its hover appearance ([isActive]) while the row's remove-confirmation
/// popover is open.
class _RemoveButton extends StatefulWidget {
  const _RemoveButton({required this.isActive, required this.onTap});

  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_RemoveButton> createState() => _RemoveButtonState();
}

class _RemoveButtonState extends State<_RemoveButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    final Color fill;
    if (_isPressed) {
      fill = c.pressedAccentTint(c.danger, t.isDark);
    } else if (_isHovered || widget.isActive) {
      fill = c.destructiveTint(t.isDark);
    } else {
      fill = const Color(0x00000000);
    }
    final iconColor = _isHovered || _isPressed || widget.isActive
        ? c.danger
        : c.textSecondary;

    return Semantics(
      button: true,
      label: context.l10n.linkedTicketsRemoveAction,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.all(AionRadius.iconBtnSm),
            ),
            child: Center(
              child: PhosphorIcon(
                PhosphorIcons.trashSimpleLight,
                size: 16,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact, row-embedded type picker that replaces
/// [_RelationshipIndicator] in place while editing — Component Spec §4.
/// Mirrors `ticket_link_picker.dart`'s `_LinkTypeSelectorRow` mechanics
/// (a [SelectionMenu] with a glyph+label+chevron trigger), shrunk to fit
/// inside a row. [options] is the row's caller-supplied allowed set
/// (already excludes [TicketLinkType.duplicatedBy] — a row whose
/// [_LinkRowState._editable] is `false` never renders this widget at
/// all). Committing a choice calls [onChanged]; dismissing without one
/// calls [onDismiss] — both revert the trailing area back to the static
/// indicator (owned by the parent `_LinkRow`, via its `_isEditingType`
/// state).
class _LinkTypeEditor extends StatefulWidget {
  const _LinkTypeEditor({
    required this.value,
    required this.options,
    required this.onChanged,
    required this.onDismiss,
  });

  /// The row's current relative type — always a valid selection, so this
  /// trigger never renders a placeholder/unset appearance.
  final TicketLinkType value;

  /// The offered options, in canonical order (`duplicatedBy` never
  /// included).
  final List<TicketLinkType> options;

  /// Called with the newly picked relative type when a menu row commits.
  final ValueChanged<TicketLinkType> onChanged;

  /// Called when the menu closes without a selection.
  final VoidCallback onDismiss;

  @override
  State<_LinkTypeEditor> createState() => _LinkTypeEditorState();
}

class _LinkTypeEditorState extends State<_LinkTypeEditor> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isOpen = false;
  bool _committed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isEmphasized = _isFocused || _isOpen;
    final borderColor = isEmphasized
        ? c.primary
        : _isHovered
        ? c.borderStrong
        : c.border;
    final boxShadow = isEmphasized
        ? [
            BoxShadow(
              color: c.primary.withValues(alpha: t.isDark ? 0.30 : 0.16),
              blurRadius: 0,
              spreadRadius: 3,
            ),
          ]
        : const <BoxShadow>[];
    final chevronColor = isEmphasized || _isHovered
        ? c.textSecondary
        : c.textMuted;

    final trigger = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.all(AionRadius.iconBtnSm),
          border: Border.all(color: borderColor, width: isEmphasized ? 1.5 : 1),
          boxShadow: boxShadow,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 15,
                child: PhosphorIcon(
                  widget.value.glyph,
                  size: 13,
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                widget.value.label(context),
                style: AionText.key.copyWith(color: c.textPrimary),
              ),
              const SizedBox(width: 6),
              PhosphorIcon(
                _isOpen ? PhosphorIcons.caretUpLight : PhosphorIcons.caretDownLight,
                size: 9,
                color: chevronColor,
              ),
            ],
          ),
        ),
      ),
    );

    return SelectionMenu<TicketLinkType>(
      trigger: trigger,
      items: widget.options,
      currentValue: widget.value,
      onSelected: (type) {
        _committed = true;
        widget.onChanged(type);
      },
      onOpenChanged: (open) {
        setState(() => _isOpen = open);
        // Fires once the overlay finishes closing, whether that was a
        // committed selection (onSelected already ran above) or an
        // outside-tap dismissal — either way the parent row reverts its
        // trailing area back to the static indicator.
        if (!open && !_committed) widget.onDismiss();
      },
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      semanticsLabel: context.l10n.linkedTicketsChangeTypeAction,
      itemLabel: (type) => type.label(context),
      itemBuilder: (context, c, item) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            child: PhosphorIcon(item.glyph, size: 14, color: c.textSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.label(context),
              style: AionText.bodySm.copyWith(
                color: c.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The [Overlay] content behind a row's remove-confirmation popover —
/// Component Spec §5. A lightweight, low-ceremony popover (not a full-
/// screen dialog) anchored below-right of the remove button via
/// [layerLink], since removing a link is reversible-feeling: only the
/// link is affected, both tickets survive.
class _RemoveConfirmationOverlay extends StatelessWidget {
  const _RemoveConfirmationOverlay({
    required this.layerLink,
    required this.targetTicketKey,
    required this.onCancel,
    required this.onConfirm,
  });

  final LayerLink layerLink;

  /// The other-side ticket's mono key (e.g. `AIO-9`), named in the
  /// confirmation body per Component Spec §5.2 — `{key}` in
  /// `linkedTicketsRemoveConfirmBody`.
  final String targetTicketKey;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onCancel,
          ),
        ),
        CompositedTransformFollower(
          link: layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 8),
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.borderStrong, width: 1),
              borderRadius: BorderRadius.all(AionRadius.lg),
              boxShadow: AionShadows.overlay(c, t.isDark),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AionSpacing.sp16 - 2),
              child: SizedBox(
                width: 264,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.l10n.linkedTicketsRemoveConfirmTitle,
                      style: AionText.cardTitle.copyWith(color: c.textPrimary),
                    ),
                    const SizedBox(height: AionSpacing.sp12),
                    Text(
                      context.l10n.linkedTicketsRemoveConfirmBody(
                        targetTicketKey,
                      ),
                      style: AionText.bodySm.copyWith(
                        color: c.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: AionSpacing.sp12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _CancelButton(onTap: onCancel),
                        const SizedBox(width: AionSpacing.sp8),
                        _ConfirmRemoveButton(onTap: onConfirm),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The popover's ghost/secondary "Cancel" button — Component Spec §5.3.
class _CancelButton extends StatefulWidget {
  const _CancelButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_CancelButton> createState() => _CancelButtonState();
}

class _CancelButtonState extends State<_CancelButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isRaised = _isHovered || _isPressed;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _isPressed ? c.border : (isRaised ? c.surfaceHover : const Color(0x00000000)),
              border: Border.all(
                color: isRaised ? c.borderStrong : c.border,
                width: 1,
              ),
              borderRadius: BorderRadius.all(AionRadius.md),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(
                context.l10n.commonCancel,
                style: AionText.button.copyWith(color: c.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The popover's solid destructive "Remove" button — Component Spec
/// §5.4. There is no `dangerHover`/`dangerPressed` token, so hover/
/// pressed are a documented `Color.alphaBlend`-darkened `danger`, per
/// the Component Spec's own §5.4 note.
class _ConfirmRemoveButton extends StatefulWidget {
  const _ConfirmRemoveButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_ConfirmRemoveButton> createState() => _ConfirmRemoveButtonState();
}

class _ConfirmRemoveButtonState extends State<_ConfirmRemoveButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    final Color fill;
    if (_isPressed) {
      fill = Color.alphaBlend(
        const Color(0x33000000), // black @ 0.20
        c.danger,
      );
    } else if (_isHovered) {
      fill = Color.alphaBlend(
        const Color(0x1F000000), // black @ 0.12
        c.danger,
      );
    } else {
      fill = c.danger;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.all(AionRadius.md),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(
                context.l10n.linkedTicketsRemoveConfirmAction,
                style: AionText.button.copyWith(color: const Color(0xFFFFFFFF)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
