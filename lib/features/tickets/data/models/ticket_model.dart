import 'package:drift/drift.dart';

@DataClassName('TicketData')
class TicketsTable extends Table {
  @override
  String get tableName => 'tickets';

  TextColumn get id => text()();
  TextColumn get ticketId => text().named('ticket_id').unique()();
  TextColumn get type => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get status => text()();
  TextColumn get priority => text().withDefault(const Constant('none'))();
  TextColumn get parentId => text().named('parent_id').nullable()();
  BlobColumn get embedding => blob().nullable()();
  IntColumn get estimate => integer().nullable()();
  IntColumn get timeSpent => integer().named('time_spent').nullable()();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get updatedAt => integer().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TicketIdSequenceData')
class TicketIdSequenceTable extends Table {
  @override
  String get tableName => 'ticket_id_sequence';

  IntColumn get id => integer()();
  IntColumn get seq => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
