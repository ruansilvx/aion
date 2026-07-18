// data/services/ticket_markdown_watcher_service.dart — TicketMarkdownWatcherService (data layer).

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import 'package:aion/features/tickets/data/services/ticket_markdown_reconciler.dart';

/// Watches `<rootPath>/tickets/` for external edits and debounces them
/// into [TicketMarkdownReconciler.reconcile] calls. Desktop-only,
/// focus-lifecycle-controlled — see `start`/`stop`, driven by
/// `WorkspaceShell`'s `WidgetsBindingObserver`, not by this class itself
/// (it has no opinion on *when* it should run, only *what* to do while
/// running).
///
/// Ticket-type filtering (`resource`/`page` only) happens inside
/// [TicketMarkdownReconciler.reconcile] itself rather than here —
/// consolidating that lookup in one place instead of duplicating a
/// ticketId-\>type check in both the watcher and the reconciler.
class TicketMarkdownWatcherService {
  /// Creates a service that watches [rootPath]'s `tickets/` directory and
  /// forwards debounced changes to [_reconciler]. [debounce] is the
  /// quiet period required after the last detected write on a given file
  /// before reconciling it — default matches the ~1.5s suggested in
  /// design.md; tune per real-world editor save behavior.
  TicketMarkdownWatcherService(
    this._reconciler,
    this._rootPath, {
    this.debounce = const Duration(milliseconds: 1500),
  });

  final TicketMarkdownReconciler _reconciler;
  final String _rootPath;

  /// Quiet period after the last write before reconciling.
  final Duration debounce;

  DirectoryWatcher? _watcher;
  StreamSubscription<WatchEvent>? _subscription;
  final _debounceTimers = <String, Timer>{};

  /// Starts watching, and immediately reconciles every existing ticket
  /// file once — covers edits made to `resource`/`page` files while Aion
  /// was backgrounded, which no filesystem event fires for on resume
  /// (per design.md: "immediately triggers one reconcile pass ...
  /// covering edits made while backgrounded"). Safe to call while
  /// already started (no-op).
  void start() {
    if (_watcher != null) return;
    final ticketsDir = '$_rootPath${Platform.pathSeparator}tickets';
    if (!Directory(ticketsDir).existsSync()) return;

    final watcher = DirectoryWatcher(ticketsDir);
    _watcher = watcher;
    _subscription = watcher.events.listen(_onEvent);

    for (final entity in Directory(ticketsDir).listSync()) {
      if (entity is! File || p.extension(entity.path) != '.md') continue;
      final ticketId = p.basenameWithoutExtension(entity.path);
      unawaited(_reconciler.reconcile(ticketId, _rootPath));
    }
  }

  /// Stops watching and cancels any pending debounce timers. Safe to call
  /// while already stopped (no-op).
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _watcher = null;
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
  }

  void _onEvent(WatchEvent event) {
    if (event.type == ChangeType.REMOVE) return;
    if (p.extension(event.path) != '.md') return;

    final ticketId = p.basenameWithoutExtension(event.path);
    _debounceTimers[ticketId]?.cancel();
    _debounceTimers[ticketId] = Timer(debounce, () {
      _debounceTimers.remove(ticketId);
      unawaited(_reconciler.reconcile(ticketId, _rootPath));
    });
  }
}
