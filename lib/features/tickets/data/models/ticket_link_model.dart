import 'package:drift/drift.dart';

@DataClassName('TicketLinkData')
class TicketLinksTable extends Table {
  @override
  String get tableName => 'ticket_links';

  TextColumn get id => text()();
  TextColumn get sourceTicketId => text().named('source_ticket_id')();
  TextColumn get targetTicketId => text().named('target_ticket_id')();
  TextColumn get linkType => text().named('link_type')();

  @override
  Set<Column> get primaryKey => {id};
}
