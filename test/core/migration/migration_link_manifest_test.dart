import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/migration/migration_link_manifest.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';

void main() {
  test('round-trips a manifest with rows through toJson/fromJson', () {
    const manifest = MigrationLinkManifest([
      MigrationLinkRow(
        sourceTicketId: 'a',
        targetTicketId: 'b',
        type: TicketLinkType.relatesTo,
      ),
      MigrationLinkRow(
        sourceTicketId: 'c',
        targetTicketId: 'd',
        type: TicketLinkType.blocks,
      ),
    ]);

    final rebuilt = MigrationLinkManifest.fromJson(manifest.toJson());

    expect(rebuilt.rows.length, 2);
    expect(rebuilt.rows[0].sourceTicketId, 'a');
    expect(rebuilt.rows[0].targetTicketId, 'b');
    expect(rebuilt.rows[0].type, TicketLinkType.relatesTo);
    expect(rebuilt.rows[1].type, TicketLinkType.blocks);
  });

  test('round-trips an empty manifest', () {
    const manifest = MigrationLinkManifest([]);
    final rebuilt = MigrationLinkManifest.fromJson(manifest.toJson());
    expect(rebuilt.rows, isEmpty);
  });

  test('fromJson on a missing/non-list value yields an empty manifest', () {
    expect(MigrationLinkManifest.fromJson(null).rows, isEmpty);
    expect(MigrationLinkManifest.fromJson('not a list').rows, isEmpty);
  });

  test(
    'MigrationLinkRow.fromJson throws on an unknown TicketLinkType name',
    () {
      expect(
        () => MigrationLinkRow.fromJson({
          'sourceTicketId': 'a',
          'targetTicketId': 'b',
          'type': 'notARealType',
        }),
        throwsFormatException,
      );
    },
  );
}
