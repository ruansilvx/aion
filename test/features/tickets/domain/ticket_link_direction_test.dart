// test/features/tickets/domain/ticket_link_direction_test.dart — TicketLinkTypeRelative/relativeLinkType/toCanonical tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/utils/ticket_link_direction.dart';

void main() {
  group('TicketLinkTypeRelative.inverse', () {
    test('blocks <-> blockedBy', () {
      expect(TicketLinkType.blocks.inverse, TicketLinkType.blockedBy);
      expect(TicketLinkType.blockedBy.inverse, TicketLinkType.blocks);
    });

    test('duplicates <-> duplicatedBy', () {
      expect(TicketLinkType.duplicates.inverse, TicketLinkType.duplicatedBy);
      expect(TicketLinkType.duplicatedBy.inverse, TicketLinkType.duplicates);
    });

    test('relatesTo is its own inverse (symmetric)', () {
      expect(TicketLinkType.relatesTo.inverse, TicketLinkType.relatesTo);
    });

    test('inverse is an involution for every value', () {
      for (final type in TicketLinkType.values) {
        expect(type.inverse.inverse, type);
      }
    });
  });

  group('relativeLinkType', () {
    TicketLinkData row({
      String source = 'A',
      String target = 'B',
      required TicketLinkType linkType,
    }) => TicketLinkData(
      id: 'link-1',
      sourceTicketId: source,
      targetTicketId: target,
      linkType: linkType.name,
    );

    for (final type in TicketLinkType.values) {
      test(
        'viewed from the source, reads $type unchanged',
        () {
          final r = row(linkType: type);
          expect(relativeLinkType(r, 'A'), type);
        },
      );

      test(
        'viewed from the target, reads ${type.inverse} (the inverse)',
        () {
          final r = row(linkType: type);
          expect(relativeLinkType(r, 'B'), type.inverse);
        },
      );
    }
  });

  group('toCanonical', () {
    TicketLinkData row({
      String source = 'A',
      String target = 'B',
      required TicketLinkType linkType,
    }) => TicketLinkData(
      id: 'link-1',
      sourceTicketId: source,
      targetTicketId: target,
      linkType: linkType.name,
    );

    for (final storedType in TicketLinkType.values) {
      test(
        'round-trips through relativeLinkType from the source side '
        '($storedType)',
        () {
          final r = row(linkType: storedType);
          final relativeFromSource = relativeLinkType(r, 'A');
          expect(toCanonical(relativeFromSource, r, 'A'), storedType);
        },
      );

      test(
        'round-trips through relativeLinkType from the target side '
        '($storedType)',
        () {
          final r = row(linkType: storedType);
          final relativeFromTarget = relativeLinkType(r, 'B');
          expect(toCanonical(relativeFromTarget, r, 'B'), storedType);
        },
      );
    }

    test('viewed from the source, canonical equals the relative selection', () {
      final r = row(linkType: TicketLinkType.blocks);
      expect(toCanonical(TicketLinkType.relatesTo, r, 'A'), TicketLinkType.relatesTo);
    });

    test('viewed from the target, canonical is the inverse of the selection', () {
      final r = row(linkType: TicketLinkType.blocks);
      expect(toCanonical(TicketLinkType.relatesTo, r, 'B'), TicketLinkType.relatesTo);
      expect(toCanonical(TicketLinkType.blocks, r, 'B'), TicketLinkType.blockedBy);
    });
  });
}
