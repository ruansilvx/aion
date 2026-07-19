// presentation/widgets/ticket_link_picker.dart — Reusable ticket-link picker overlay (presentation layer).

import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';

/// A "+ Add" ghost-button trigger that opens a searchable overlay of
/// [candidatesLoader]'s tickets, calling [onSelected] with the chosen
/// ticket when a row is tapped. Renders the design.md §8.1 "+ Add"
/// affordance for the Documentation section's Sub-pages/Linked Tickets
/// headers — used to attach an *existing* ticket via `TicketLink`, as
/// opposed to `TicketParentPicker` which reassigns structural `parentId`.
/// Follows the same `Overlay`/`LayerLink`/`CompositedTransformFollower`
/// mechanics as `TicketParentPicker` rather than a from-scratch overlay.
/// This widget only renders the trigger and overlay list — it performs no
/// repository writes itself; [onSelected] is responsible for actually
/// creating the `TicketLink` and refreshing whatever state depends on it.
class TicketLinkPicker extends StatefulWidget {
  /// Creates a [TicketLinkPicker].
  const TicketLinkPicker({
    super.key,
    required this.candidatesLoader,
    required this.onSelected,
  });

  /// Fetches the candidate tickets to offer, re-fetched fresh every time
  /// the overlay opens. Callers are expected to have already excluded
  /// whatever shouldn't be offered (e.g. non-board types, already-linked
  /// tickets, the ticket itself).
  final Future<List<Ticket>> Function() candidatesLoader;

  /// Called with the chosen ticket when a row is tapped.
  final ValueChanged<Ticket> onSelected;

  @override
  State<TicketLinkPicker> createState() => _TicketLinkPickerState();
}

class _TicketLinkPickerState extends State<TicketLinkPicker> {
  final LayerLink _layerLink = LayerLink();
  final TextEditingController _searchController = TextEditingController();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  /// Candidates fetched for the currently-open overlay. `null` while a
  /// fetch is in flight; reset on every open so a stale list from an
  /// earlier link never lingers.
  List<Ticket>? _candidates;

  @override
  void dispose() {
    _removeOverlay();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleOverlay() {
    if (_isOpen) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  Future<void> _showOverlay() async {
    final overlay = Overlay.of(context);
    _candidates = null;
    _searchController.clear();
    _searchController.addListener(_handleSearchChanged);

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final t = ThemeScope.of(overlayContext);
        final c = t.colors;
        final query = _searchController.text.trim().toLowerCase();
        final candidates = _candidates;
        final filtered = candidates
            ?.where(
              (cand) =>
                  query.isEmpty ||
                  cand.ticketId.toLowerCase().contains(query) ||
                  cand.title.toLowerCase().contains(query),
            )
            .toList();

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
                      minWidth: 300,
                      maxWidth: 300,
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
                                .ticketLinkPickerSearchHint,
                          ),
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
                                overlayContext.l10n.ticketLinkPickerNoResults,
                                style: AionText.bodySm.copyWith(
                                  color: c.textMuted,
                                ),
                              ),
                            ),
                          )
                        else
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 280),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final candidate = filtered[index];
                                return _LinkCandidateRow(
                                  ticket: candidate,
                                  onTap: () => _commit(candidate),
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

    final candidates = await widget.candidatesLoader();
    if (!mounted) return;
    setState(() => _candidates = candidates);
    _overlayEntry?.markNeedsBuild();
  }

  void _handleSearchChanged() => _overlayEntry?.markNeedsBuild();

  void _commit(Ticket ticket) {
    widget.onSelected(ticket);
    _removeOverlay();
  }

  void _removeOverlay() {
    _searchController.removeListener(_handleSearchChanged);
    _overlayEntry?.remove();
    _overlayEntry = null;
    // Guards against setState-after-dispose — same class of bug
    // project.md's AppDropdown overlay-dismiss crash note warns about.
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

/// A single selectable candidate row in [TicketLinkPicker]'s overlay list —
/// a [TypeChip] plus the ticket's title.
class _LinkCandidateRow extends StatefulWidget {
  const _LinkCandidateRow({required this.ticket, required this.onTap});

  final Ticket ticket;
  final VoidCallback onTap;

  @override
  State<_LinkCandidateRow> createState() => _LinkCandidateRowState();
}

class _LinkCandidateRowState extends State<_LinkCandidateRow> {
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                TypeChip(type: widget.ticket.type, isRow: false),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.ticket.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AionText.bodySm.copyWith(color: c.textPrimary),
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
