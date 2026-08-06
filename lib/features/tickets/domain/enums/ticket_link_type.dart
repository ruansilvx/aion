// domain/enums/ticket_link_type.dart — TicketLinkType enum + display/relative-view extensions (domain layer).

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/localization/context_localizations_x.dart';

/// The relationship a `ticket_links` row expresses between two tickets.
///
/// Non-hierarchical relationships only. Structural parent/child hierarchy
/// is modelled exclusively by `parentId` on [Ticket](../entities/ticket.dart)
/// — never by a link type.
enum TicketLinkType {
  /// The source ticket blocks the target ticket from proceeding.
  blocks,

  /// The source ticket is blocked by the target ticket. Inverse of [blocks].
  blockedBy,

  /// The tickets are related but neither blocks nor duplicates the other.
  relatesTo,

  /// The source ticket duplicates the target ticket.
  duplicates,

  /// The source ticket is duplicated by the target ticket. Inverse of
  /// [duplicates].
  duplicatedBy,
}

/// Perspective-flipping helpers for [TicketLinkType]. A stored row's
/// [TicketLinkType] always names the relationship *from source to
/// target* (see `ticket_link_dao.dart`'s class doc); this extension
/// answers "how does the same row read from the other ticket's side".
extension TicketLinkTypeRelative on TicketLinkType {
  /// The type that reads the same relationship from the other ticket's
  /// side. [relatesTo] is its own inverse (symmetric).
  TicketLinkType get inverse => switch (this) {
    TicketLinkType.blocks => TicketLinkType.blockedBy,
    TicketLinkType.blockedBy => TicketLinkType.blocks,
    TicketLinkType.relatesTo => TicketLinkType.relatesTo,
    TicketLinkType.duplicates => TicketLinkType.duplicatedBy,
    TicketLinkType.duplicatedBy => TicketLinkType.duplicates,
  };
}

/// Display helpers for [TicketLinkType], shared by every UI that renders a
/// link's type (`TicketLinkPicker`'s `_LinkTypeSelectorRow`,
/// `LinkedTicketsSection`'s row indicator and `_LinkTypeEditor`).
/// Promoted from `ticket_link_picker.dart`'s private top-level
/// `_linkTypeGlyph`/`_linkTypeLabel` functions (Component Spec §1.3) so
/// design-system code that has no reason to depend on a presentation-layer
/// file can reach them too. [PhosphorIconData]/[PhosphorIcons] come from
/// the `phosphoricons_flutter` *package*, not the Flutter framework
/// itself, so this stays consistent with the domain layer's
/// no-Flutter-import rule — the one exception being [label], which takes
/// a [BuildContext] to resolve localized copy via `context.l10n`, exactly
/// as promoted from its presentation-layer origin.
extension TicketLinkTypeDisplay on TicketLinkType {
  /// The directional glyph for this type — monochrome, never a
  /// type-accent hue (Component Spec §1.4: "this is a relationship
  /// picker, not a type picker"). [TicketLinkType.duplicatedBy] is never
  /// offered as a raw creation choice (see
  /// `TicketLinkPicker.linkTypeOptions`'s dartdoc) but still resolves a
  /// glyph here, since it *is* rendered as a relative view.
  PhosphorIconData get glyph => switch (this) {
    TicketLinkType.blocks => PhosphorIcons.arrowRightLight,
    TicketLinkType.blockedBy => PhosphorIcons.arrowLeftLight,
    TicketLinkType.relatesTo => PhosphorIcons.arrowsLeftRightLight,
    TicketLinkType.duplicates => PhosphorIcons.copyLight,
    TicketLinkType.duplicatedBy => PhosphorIcons.copySimpleLight,
  };

  /// The localized label for this type. Unlike the pre-promotion
  /// `_linkTypeLabel`, [TicketLinkType.duplicatedBy] now resolves to a
  /// real label (`ticketLinkTypeDuplicatedBy`, "Duplicated by") instead
  /// of `''` — it was never actually rendered before this change, since
  /// nothing displayed a link's relative type until now.
  String label(BuildContext context) => switch (this) {
    TicketLinkType.blocks => context.l10n.ticketLinkTypeBlocks,
    TicketLinkType.blockedBy => context.l10n.ticketLinkTypeBlockedBy,
    TicketLinkType.relatesTo => context.l10n.ticketLinkTypeRelatesTo,
    TicketLinkType.duplicates => context.l10n.ticketLinkTypeDuplicates,
    TicketLinkType.duplicatedBy => context.l10n.ticketLinkTypeDuplicatedBy,
  };
}
