// bin/migrate_aion_arch.dart — Standalone CLI: one-time migration of
// aion-arch's idea/change history into the aion project's own ticket
// store, per
// aion-arch/changes/decommission-aion-arch-cli-workflow-step-1/design.md.
//
// Usage:
//   dart run bin/migrate_aion_arch.dart <aion-arch-root> <aion-project-root> [--import]
//
// Two phases (design.md's "Two-phase architecture"):
//
// Phase A (always runs, pure Dart, no DB): walks
// <aion-arch-root>/ideas/*.md and <aion-arch-root>/changes/archive/*/,
// plus <aion-arch-root>/project.md, converts each into Ticket(s) via
// core/migration/*.dart, serializes them into
// <aion-project-root>/tickets/*.md via the existing
// TicketMarkdownSerializer, and writes every produced TicketLink row to
// <aion-project-root>/tickets/.migration-links.json. Prints one
// generated/skipped-unparseable line per source file/folder and exits
// non-zero (without running Phase B) if anything was skipped.
//
// Phase B (only with --import, touches the DB): opens the aion project's
// own on-disk database directly via dart:io + NativeDatabase (see
// design.md's "Opening the database from a bare CLI" — no Flutter engine
// involved), then:
//   1. Registers every ticket this run generated via
//      TicketRepository.importTicket/updateTicket, keyed by ticketId —
//      done directly against the in-memory Ticket objects Phase A already
//      built (not by re-parsing the files this script just wrote) because
//      only the CLI's own generation pass knows the internal `id` value
//      it assigned each ticket, and TicketMarkdownTemplate's frontmatter
//      schema has no field for `id` at all (only the human-readable
//      `ticketId`) for TicketDbReconstructionService to recover it from —
//      see MigrationLinkRow's dartdoc for the same constraint stated from
//      the link side. While doing so, this step builds `realIdOf`: a map
//      from every ticket's *this-run-only* generated `id` to whatever its
//      real persisted `id` turns out to be (the pre-existing row's `id`
//      when the ticket already existed, or its own freshly-minted `id`
//      when it's genuinely new).
//   2. Re-resolves and writes every non-null `parentId` through `realIdOf`
//      — never a ticket's raw `parentId` field, which is always *this
//      run's own* generated id for its parent, not necessarily the
//      parent's real persisted id. This step is what actually makes every
//      Epic→Story→Task `parentId` this migration writes resolve to the
//      parent's actual persisted `id`, on a fresh run or a re-run alike —
//      see this file's "Idempotency" note below for the corruption a
//      naive per-ticket write (resolving only a ticket's own identity,
//      not what its `parentId` points at) caused before this step
//      existed, found and fixed by a /verify pass and its follow-up
//      corrective data-repair script.
//   3. Calls TicketDbReconstructionService.reconstruct(<aion-project-root>)
//      per design.md — unmodified, exactly as it's used elsewhere. Since
//      every ticketId this run produced already exists in the DB by this
//      point (step 1), this is a benign, idempotent self-consistency pass
//      re-reading the same files, plus the (best-effort, see below)
//      embedding backfill for the newly imported rows.
//   4. Reads .migration-links.json and calls
//      TicketLinkRepository.createLink for every row not already present
//      (checked via getLinksForTicket first) — resolving each row's
//      source/target through the same `realIdOf` map step 1 built, for
//      the identical reason step 2 resolves `parentId` through it.
//
// Embedding caveat: BundledEmbeddingProvider (the app's real
// EmbeddingProvider) depends on `flutter/services.dart` (asset loading),
// which needs a running Flutter engine this bare `dart run` CLI does not
// have. `--import` therefore uses [_NullEmbeddingProvider] below, which
// returns an empty vector — every migrated ticket ends up with a
// non-null-but-meaningless embedding rather than a real semantic one, so
// migrated content won't rank well in similarity/embedding-based search
// until the app recomputes it. No in-app mechanism does that
// automatically today (embeddings are only computed at write time); this
// is a known, accepted gap for a one-time bootstrap migration, not
// something Phase A/B attempts to work around.
//
// Idempotency: Phase A is always safe to re-run — it only ever overwrites
// its own generated `tickets/*.md`/`.migration-links.json` output.
// `--import` is safe to re-run *against the same already-written generated
// files* (ticketId-keyed upsert throughout, matching design.md), and — as
// of the `realIdOf` fix in steps 1/2/4 above — also safe to re-run against
// a *freshly regenerated* Phase A output, unlike an earlier version of this
// file. Before that fix, a re-run's own registration step correctly
// re-pointed each ticket's own `id` back to its already-persisted value,
// but wrote every `parentId`/link reference using the raw, this-run-only
// generated id of the ticket it pointed at — which, for any parent/target
// that *also* already existed and got remapped, was never actually
// persisted anywhere. A real run of this migration hit exactly that: a
// /verify pass found 2,363 of 2,366 migrated `parentId`s and 325 of 575
// `ticket_links` rows dangling in the live database, root-caused to this
// exact gap, and fixed with a one-off corrective script (not this file —
// see that finding's write-up for the data-repair approach, which is the
// same `realIdOf`-style resolution now built into steps 1/2/4 above). A
// future re-run of `--import` no longer needs a repair pass for this
// reason; it still isn't safe to run without first regenerating Phase A
// output that reflects current `aion-arch/` source content, same as ever.
//
// Phase A itself is NOT safe to invoke a second time against a
// `tickets/` directory that already holds this migration's own prior
// output: `_assignTicketIds` picks its starting `AIO-<n>` purely by
// scanning the highest number currently on disk, and every migrator
// mints a fresh random `id` on every call — so a second `_generate` call
// does not overwrite the first run's files, it mints a whole second copy
// of every ticket under new numbers/ids alongside the first. This is
// exactly why `main` always runs Phase A before checking `--import`
// (never the other way around, and never "only if not already
// generated"): the two operational tasks.md steps ("generate, review the
// diff" then "run with --import") describe one clean pass with a human
// pause in the middle, not two independent process invocations against
// a directory `_generate` has already written into. Before invoking this
// script again for real (a genuine Phase A fix, not the first run), reset
// `tickets/` back to its pre-migration baseline (delete every file this
// migration produced, keeping only what predates it) first.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/core/markdown/ticket_markdown_serializer.dart';
import 'package:aion/core/migration/aion_arch_change_migrator.dart';
import 'package:aion/core/migration/aion_arch_idea_migrator.dart';
import 'package:aion/core/migration/aion_arch_project_spec_migrator.dart';
import 'package:aion/core/migration/migration_link_manifest.dart';
import 'package:aion/features/projects/domain/entities/project.dart';
import 'package:aion/features/tickets/data/repositories/drift_ticket_link_repository.dart';
import 'package:aion/features/tickets/data/repositories/drift_ticket_repository.dart';
import 'package:aion/features/tickets/data/services/ticket_db_reconstruction_service.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';

Future<void> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final doImport = args.contains('--import');

  if (positional.length < 2) {
    stderr.writeln(
      'Usage: dart run bin/migrate_aion_arch.dart <aion-arch-root> '
      '<aion-project-root> [--import]',
    );
    exitCode = 64; // EX_USAGE
    return;
  }

  final aionArchRoot = positional[0];
  final aionProjectRoot = positional[1];

  final result = await _generate(aionArchRoot, aionProjectRoot);

  stdout.writeln(
    '\n${result.tickets.length} tickets generated across '
    '${result.sourceCount} source files/folders, '
    '${result.skippedPaths.length} skipped-unparseable, '
    '${result.links.length} links.',
  );

  if (result.skippedPaths.isNotEmpty) {
    exitCode = 1;
    stderr.writeln(
      'Not running --import (if requested): ${result.skippedPaths.length} '
      'source file(s) were skipped. Fix them and re-run.',
    );
    return;
  }

  if (doImport) {
    await _import(aionProjectRoot, result);
  }
}

/// Every ticket and link row [_generate] produced, plus bookkeeping for
/// the printed summary.
class _GenerationResult {
  _GenerationResult({
    required this.tickets,
    required this.links,
    required this.skippedPaths,
    required this.sourceCount,
  });

  final List<Ticket> tickets;
  final List<MigrationLinkRow> links;
  final List<String> skippedPaths;
  final int sourceCount;
}

/// Phase A: reads every source file under [aionArchRoot], migrates it,
/// assigns every produced ticket a real sequential `ticketId`, and writes
/// the resulting `tickets/*.md` and `.migration-links.json` files under
/// `<aionProjectRoot>/tickets/`.
Future<_GenerationResult> _generate(
  String aionArchRoot,
  String aionProjectRoot,
) async {
  final skippedPaths = <String>[];
  var sourceCount = 0;
  final tickets = <Ticket>[];
  final resolvedLinks = <MigrationLinkRow>[];

  // --- Ideas ---
  final ideasDir = Directory('$aionArchRoot/ideas');
  final ideaFiles = (await ideasDir.exists())
      ? (await ideasDir.list().toList())
            .whereType<File>()
            .where((f) => f.path.endsWith('.md'))
            .toList()
      : <File>[];
  ideaFiles.sort((a, b) => a.path.compareTo(b.path));

  final migratedIdeaSlugs = {for (final f in ideaFiles) _slugOf(f.path)};

  final ideaMigrator = AionArchIdeaMigrator();
  final ticketBySlug = <String, Ticket>{};
  final pendingIdeaLinks = <MigrationLinkRow>[];

  for (final file in ideaFiles) {
    sourceCount++;
    final content = await file.readAsString();
    if (!content.trimLeft().startsWith('---')) {
      skippedPaths.add(file.path);
      stdout.writeln('skipped-unparseable    ${file.path}');
      continue;
    }
    final (ticket, links) = ideaMigrator.migrate(
      content,
      migratedIdeaSlugs: migratedIdeaSlugs,
    );
    ticketBySlug[_slugOf(file.path)] = ticket;
    tickets.add(ticket);
    pendingIdeaLinks.addAll(links);
    stdout.writeln('generated               ${file.path}');
  }

  for (final row in pendingIdeaLinks) {
    final target = ticketBySlug[row.targetTicketId];
    if (target == null) {
      stderr.writeln(
        'warning: related idea "${row.targetTicketId}" has no migrated '
        'ticket — dropping its relatesTo link.',
      );
      continue;
    }
    resolvedLinks.add(
      MigrationLinkRow(
        sourceTicketId: row.sourceTicketId,
        targetTicketId: target.id,
        type: row.type,
      ),
    );
  }

  // --- Archived changes ---
  final archiveDir = Directory('$aionArchRoot/changes/archive');
  final changeDirs = (await archiveDir.exists())
      ? (await archiveDir.list().toList()).whereType<Directory>().toList()
      : <Directory>[];
  changeDirs.sort((a, b) => a.path.compareTo(b.path));

  final changeMigrator = AionArchChangeMigrator();
  for (final dir in changeDirs) {
    sourceCount++;
    final name = dir.path.split(Platform.pathSeparator).last;
    final proposalFile = File('${dir.path}/proposal.md');
    final designFile = File('${dir.path}/design.md');
    final specFile = File('${dir.path}/specs/spec.md');
    final tasksFile = File('${dir.path}/tasks.md');

    if (!await proposalFile.exists()) {
      skippedPaths.add(dir.path);
      stdout.writeln('skipped-unparseable    ${dir.path}');
      continue;
    }

    final migration = changeMigrator.migrate(
      name,
      proposalMd: await proposalFile.readAsString(),
      designMd: await designFile.exists()
          ? await designFile.readAsString()
          : '',
      specDeltaMd: await specFile.exists() ? await specFile.readAsString() : '',
      tasksMd: await tasksFile.exists() ? await tasksFile.readAsString() : '',
    );

    tickets
      ..add(migration.epic)
      ..addAll(migration.storiesAndTasks)
      ..add(migration.page)
      ..add(migration.spec);
    resolvedLinks.addAll(migration.links);
    stdout.writeln('generated               ${dir.path}');
  }

  // --- project.md ---
  sourceCount++;
  final projectMdFile = File('$aionArchRoot/project.md');
  if (await projectMdFile.exists()) {
    final ticket = AionArchProjectSpecMigrator().migrate(
      await projectMdFile.readAsString(),
    );
    tickets.add(ticket);
    stdout.writeln('generated               ${projectMdFile.path}');
  } else {
    skippedPaths.add(projectMdFile.path);
    stdout.writeln('skipped-unparseable    ${projectMdFile.path}');
  }

  // --- Assign real sequential ticketIds ---
  final finalTickets = await _assignTicketIds(aionProjectRoot, tickets);

  // --- Write output ---
  final ticketsDir = Directory('$aionProjectRoot/tickets');
  await ticketsDir.create(recursive: true);
  final serializer = TicketMarkdownSerializer();
  for (final ticket in finalTickets) {
    await File(
      '${ticketsDir.path}/${ticket.ticketId}.md',
    ).writeAsString(serializer.serialize(ticket));
  }
  await File('${ticketsDir.path}/.migration-links.json').writeAsString(
    const JsonEncoder.withIndent(
      '  ',
    ).convert(MigrationLinkManifest(resolvedLinks).toJson()),
  );

  return _GenerationResult(
    tickets: finalTickets,
    links: resolvedLinks,
    skippedPaths: skippedPaths,
    sourceCount: sourceCount,
  );
}

/// An idea file's slug: its filename with the `.md` extension stripped.
String _slugOf(String path) {
  final base = path.split(Platform.pathSeparator).last;
  return base.endsWith('.md') ? base.substring(0, base.length - 3) : base;
}

/// Assigns every ticket in [tickets] a real `AIO-<n>` `ticketId`,
/// continuing from one past the highest numeric suffix already present
/// under `<aionProjectRoot>/tickets/*.md` (e.g. the project's existing
/// `AIO-1.md`/`AIO-3.md`/`AIO-4.md` → starts at `AIO-5`). Assignment order
/// is [tickets]' own order — stable across a run, though not meaningful
/// beyond that.
Future<List<Ticket>> _assignTicketIds(
  String aionProjectRoot,
  List<Ticket> tickets,
) async {
  final ticketsDir = Directory('$aionProjectRoot/tickets');
  var maxSeq = 0;
  if (await ticketsDir.exists()) {
    await for (final entity in ticketsDir.list()) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;
      final base = entity.path.split(Platform.pathSeparator).last;
      final match = RegExp(r'^AIO-(\d+)\.md$').firstMatch(base);
      if (match == null) continue;
      final n = int.parse(match.group(1)!);
      if (n > maxSeq) maxSeq = n;
    }
  }

  final result = <Ticket>[];
  for (final ticket in tickets) {
    maxSeq++;
    result.add(_withTicketId(ticket, 'AIO-$maxSeq'));
  }
  return result;
}

/// Returns a copy of [ticket] with [ticketId] substituted — `Ticket`'s own
/// `copyWith` deliberately excludes `ticketId` (see its dartdoc), so this
/// rebuilds the object directly, field by field.
Ticket _withTicketId(Ticket ticket, String ticketId) {
  return Ticket(
    id: ticket.id,
    ticketId: ticketId,
    type: ticket.type,
    title: ticket.title,
    description: ticket.description,
    status: ticket.status,
    priority: ticket.priority,
    parentId: ticket.parentId,
    embedding: ticket.embedding,
    syncStatus: ticket.syncStatus,
    estimate: ticket.estimate,
    timeSpent: ticket.timeSpent,
    createdAt: ticket.createdAt,
    updatedAt: ticket.updatedAt,
    deletedAt: ticket.deletedAt,
    complexity: ticket.complexity,
    sddStage: ticket.sddStage,
    severity: ticket.severity,
    stepsToReproduce: ticket.stepsToReproduce,
    expectedBehavior: ticket.expectedBehavior,
    actualBehavior: ticket.actualBehavior,
    suggestedType: ticket.suggestedType,
    inboxPurpose: ticket.inboxPurpose,
    estimateRollup: ticket.estimateRollup,
    timeSpentRollup: ticket.timeSpentRollup,
    complexitySource: ticket.complexitySource,
    estimateSource: ticket.estimateSource,
    predictedExecutionTokensLow: ticket.predictedExecutionTokensLow,
    predictedExecutionTokensHigh: ticket.predictedExecutionTokensHigh,
  );
}

/// Returns a copy of [ticket] with [id] substituted — the counterpart to
/// [_withTicketId], used by `_import`'s registration step to address an
/// already-existing row by its real internal `id` rather than this run's
/// own freshly-generated one. See `Ticket.copyWith`'s dartdoc for why a
/// direct field-by-field rebuild is needed instead.
Ticket _withId(Ticket ticket, String id) {
  return Ticket(
    id: id,
    ticketId: ticket.ticketId,
    type: ticket.type,
    title: ticket.title,
    description: ticket.description,
    status: ticket.status,
    priority: ticket.priority,
    parentId: ticket.parentId,
    embedding: ticket.embedding,
    syncStatus: ticket.syncStatus,
    estimate: ticket.estimate,
    timeSpent: ticket.timeSpent,
    createdAt: ticket.createdAt,
    updatedAt: ticket.updatedAt,
    deletedAt: ticket.deletedAt,
    complexity: ticket.complexity,
    sddStage: ticket.sddStage,
    severity: ticket.severity,
    stepsToReproduce: ticket.stepsToReproduce,
    expectedBehavior: ticket.expectedBehavior,
    actualBehavior: ticket.actualBehavior,
    suggestedType: ticket.suggestedType,
    inboxPurpose: ticket.inboxPurpose,
    estimateRollup: ticket.estimateRollup,
    timeSpentRollup: ticket.timeSpentRollup,
    complexitySource: ticket.complexitySource,
    estimateSource: ticket.estimateSource,
    predictedExecutionTokensLow: ticket.predictedExecutionTokensLow,
    predictedExecutionTokensHigh: ticket.predictedExecutionTokensHigh,
  );
}

/// [EmbeddingProvider] stand-in for a bare CLI context — see this file's
/// header comment's "Embedding caveat".
class _NullEmbeddingProvider implements EmbeddingProvider {
  @override
  Future<Uint8List> embed(String text) async => Uint8List(0);
}

/// Phase B (`--import`): opens `<aionProjectRoot>`'s own on-disk database
/// directly, registers every generated ticket, runs
/// [TicketDbReconstructionService.reconstruct], then backfills every
/// generated link row. See this file's header comment for the full
/// rationale.
Future<void> _import(String aionProjectRoot, _GenerationResult result) async {
  final dbPath =
      '$aionProjectRoot${Platform.pathSeparator}.aion'
      '${Platform.pathSeparator}data${Platform.pathSeparator}app.db';
  await Directory(
    '$aionProjectRoot${Platform.pathSeparator}.aion${Platform.pathSeparator}data',
  ).create(recursive: true);

  final project = Project(
    id: 'migrate-aion-arch-cli',
    name: 'aion',
    storageKey: 'migrate-aion-arch-cli',
    rootPath: aionProjectRoot,
    baselineVersion: '0.0.0',
    createdAt: DateTime.now(),
    lastOpenedAt: DateTime.now(),
  );
  final db = AppDatabase(
    project,
    NativeDatabase.createInBackground(File(dbPath)),
  );

  try {
    final ticketRepository = DriftTicketRepository(db);
    final linkRepository = DriftTicketLinkRepository(db);

    // Step 1: register every generated ticket's own identity/content
    // directly — see this file's header comment for why this can't be
    // left to TicketDbReconstructionService alone.
    //
    // A re-run against a ticketId that already has a row (see this
    // file's header comment's Idempotency note — deliberately not the
    // common path, but still handled correctly) cannot just call
    // `updateTicket(ticket)` with this run's own freshly-generated
    // `ticket.id`: `importTicket`/`updateTicket` address a row by `id`,
    // not `ticketId`, so passing a new run's own random `id` for an
    // already-existing `ticketId` throws (no row has that `id`) rather
    // than updating the row `ticketId` actually maps to. It also isn't
    // enough to substitute the existing row's `id` and call
    // `updateTicket` alone — that method explicitly excludes `status`
    // and `parentId` (see its own dartdoc), both fields this migration
    // sets and a re-run might have corrected. So: substitute the
    // existing row's `id`, call `updateTicket` for the fields it does
    // cover, then `updateTicketStatus` explicitly for the one it
    // doesn't. `parentId` is deliberately *not* written here — see step
    // 2 below for why resolving it requires every ticket in this batch
    // to have already been registered first.
    //
    // While doing so, builds `realIdOf`: this run's own generated
    // `ticket.id` -> the ticket's real persisted `id` (the existing
    // row's `id` when remapped, or the ticket's own `id` when it was
    // genuinely new). Every other reference to a ticket generated in
    // this pass — a sibling's `parentId`, a link row's source/target —
    // must be resolved through this map before being written, never
    // used raw; see this file's header comment's Idempotency note for
    // the corruption that skipping this step caused.
    final existing = await ticketRepository.getAllTickets();
    final existingByTicketId = {for (final t in existing) t.ticketId: t};
    final realIdOf = <String, String>{};
    var registeredCount = 0;
    for (final ticket in result.tickets) {
      final existingTicket = existingByTicketId[ticket.ticketId];
      if (existingTicket != null) {
        final withExistingId = _withId(ticket, existingTicket.id);
        await ticketRepository.updateTicket(withExistingId);
        await ticketRepository.updateTicketStatus(
          existingTicket.id,
          ticket.status,
        );
        realIdOf[ticket.id] = existingTicket.id;
      } else {
        await ticketRepository.importTicket(ticket);
        realIdOf[ticket.id] = ticket.id;
      }
      registeredCount++;
    }
    stdout.writeln('registered $registeredCount tickets directly.');

    // Step 2: now that every ticket in this batch has a known real id,
    // re-resolve and write every non-null `parentId` through `realIdOf`
    // — never a ticket's raw `parentId` field, which is always *this
    // run's own* generated id for its parent, not necessarily the
    // parent's real persisted id. Skips the write when the resolved
    // value already matches what's persisted, so a genuine no-op re-run
    // doesn't bump every migrated ticket's `updatedAt`.
    var parentFixCount = 0;
    for (final ticket in result.tickets) {
      if (ticket.parentId == null) continue;
      final childRealId = realIdOf[ticket.id]!;
      final parentRealId = realIdOf[ticket.parentId];
      if (parentRealId == null) {
        throw StateError(
          'Ticket ${ticket.ticketId} has parentId ${ticket.parentId} that '
          'does not resolve to any ticket generated in this same pass — '
          'this should be impossible, since every parentId this migration '
          'writes comes from a sibling ticket generated alongside it.',
        );
      }
      final currentParentId = existingByTicketId[ticket.ticketId]?.parentId;
      if (currentParentId == parentRealId) continue;
      await ticketRepository.updateTicketParent(childRealId, parentRealId);
      parentFixCount++;
    }
    stdout.writeln('parentId: $parentFixCount set/corrected.');

    // Step 3: TicketDbReconstructionService.reconstruct, per design.md —
    // unmodified. Every ticketId already exists by this point, so this is
    // an idempotent self-consistency pass (plus the embedding backfill).
    final reconstructionService = TicketDbReconstructionService(
      ticketRepository,
      TicketMarkdownSerializer(),
      _NullEmbeddingProvider(),
    );
    final report = await reconstructionService.reconstruct(aionProjectRoot);
    stdout.writeln(
      'reconstruct: ${report.importedCount} imported, '
      '${report.skippedPaths.length} skipped.',
    );

    // Step 4: link backfill. Resolves each row's source/target through
    // the same `realIdOf` map step 1 built, for the identical reason
    // step 2 resolves `parentId` through it — `row.sourceTicketId`/
    // `targetTicketId` are always this run's own generated ids, never
    // valid to pass to the repository directly.
    var createdLinkCount = 0;
    for (final row in result.links) {
      final sourceRealId = realIdOf[row.sourceTicketId];
      final targetRealId = realIdOf[row.targetTicketId];
      if (sourceRealId == null || targetRealId == null) {
        throw StateError(
          'Link row does not resolve within this generation pass: '
          '${row.sourceTicketId} -> ${row.targetTicketId} (${row.type.name})',
        );
      }
      final existingLinks = await linkRepository.getLinksForTicket(
        sourceRealId,
      );
      final alreadyExists = existingLinks.any(
        (l) =>
            l.sourceTicketId == sourceRealId &&
            l.targetTicketId == targetRealId &&
            l.linkType == row.type.name,
      );
      if (alreadyExists) continue;
      await linkRepository.createLink(
        sourceTicketId: sourceRealId,
        targetTicketId: targetRealId,
        linkType: row.type,
      );
      createdLinkCount++;
    }
    stdout.writeln(
      'links: $createdLinkCount created, '
      '${result.links.length - createdLinkCount} already present.',
    );
  } finally {
    await db.close();
  }
}
