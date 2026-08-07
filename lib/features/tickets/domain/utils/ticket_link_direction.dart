// domain/utils/ticket_link_direction.dart — Perspective resolution for TicketLink rows (domain layer).

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';

/// The relationship type [row] expresses **from [viewingTicketId]'s point
/// of view**.
///
/// A stored row's [TicketLinkData.linkType] always names the relationship
/// *from source to target* (`ticket_link_dao.dart`'s class doc) — e.g.
/// `{source: A, target: B, linkType: blocks}` means "A blocks B". Read
/// from `A`'s own detail screen, that row should say "Blocks"; read from
/// `B`'s, it should say "Blocked by". This is the single canonical
/// resolution of that flip, replacing what `TicketsCubit
/// ._computeBlockedTicketIds`/`._isTicketBlocked` used to each inline as
/// their own ad hoc switch on the raw string — both now call this
/// instead (see their dartdoc).
///
/// Returns [row.linkType] (parsed via [TicketLinkType.values.byName])
/// unchanged when [viewingTicketId] is the row's source, or its
/// [TicketLinkTypeRelative.inverse] when [viewingTicketId] is the target.
TicketLinkType relativeLinkType(TicketLinkData row, String viewingTicketId) {
  final stored = TicketLinkType.values.byName(row.linkType);
  return row.sourceTicketId == viewingTicketId ? stored : stored.inverse;
}

/// The inverse of [relativeLinkType]: translates a *relative* type a user
/// picked while viewing [viewingTicketId] (e.g. in `LinkedTicketsSection`'s
/// `_LinkTypeEditor`, surfaced to `TicketsCubit.updateTicketLinkType` —
/// the only caller, since it's the one place that already has [row] in
/// hand) back to the *canonical* (source-to-target) type
/// [TicketLinkRepository.updateLinkType](../repositories/ticket_link_repository.dart)
/// expects to persist on [row].
///
/// If [viewingTicketId] is [row]'s source, the relative and canonical
/// readings are already the same value. If it's the target, the relative
/// selection is itself the *other* side's reading, so it must be flipped
/// back via [TicketLinkTypeRelative.inverse] before it's a valid value for
/// [row.sourceTicketId] → [row.targetTicketId].
TicketLinkType toCanonical(
  TicketLinkType relativeSelection,
  TicketLinkData row,
  String viewingTicketId,
) {
  return row.sourceTicketId == viewingTicketId
      ? relativeSelection
      : relativeSelection.inverse;
}
