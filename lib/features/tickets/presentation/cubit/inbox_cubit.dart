// presentation/cubit/inbox_cubit.dart — InboxCubit business logic (presentation layer).

import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/core/contracts/agent_provider.dart';
import 'package:aion/core/contracts/provider_registry.dart';
import 'package:aion/core/git/git_repository_client.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/repositories/model_routing_repository.dart';
import 'package:aion/features/tickets/domain/entities/chat_turn_result.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';
import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';
import 'package:aion/features/tickets/domain/enums/inbox_purpose.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/comment_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_link_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/chat_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/inbox_state.dart';

/// Launches and tracks the Inbox's four purpose-specific chats
/// (brain-dump, what-next guidance, release planning, Q&A) and lists past
/// launches — see
/// `AIO-1300` §5.
/// Provided fresh per route entry to `/workspace/inbox` (not root-scoped),
/// mirroring `DocumentationCubit`'s own per-route provisioning.
///
/// Constructed with [_ticketRepository]/[_commentRepository]/
/// [_linkRepository]/[_providerRegistry]/[_modelRoutingRepository] per
/// design.md §5's stated dependency list — all five required, since
/// every one of the Inbox's four purposes *is* an agent call; unlike
/// `TicketsCubit`, there's no reduced ticket-CRUD-only "core" mode to
/// fall back to without them. [_gitClient]/[_projectRootPath] are two
/// further dependencies design.md's own constructor list omitted, needed
/// only by [startQa]: §3's decision requires mirroring
/// `TicketsCubit._runFullSummarization`'s exact worktree-create/run/
/// remove-in-`finally` shape, which needs a [GitRepositoryClient] and the
/// project's root path. These two *are* optional (`null` on mobile/web,
/// which has no user-chosen project directory — see
/// `Project.rootPath`'s own dartdoc, and `app_router.dart`'s existing
/// `if (rootPath != null)`-gated provisioning of the same two
/// dependencies for `TicketsCubit`) — [startQa] emits [InboxError]
/// immediately if constructed without either, rather than crashing.
class InboxCubit extends Cubit<InboxState> {
  /// Creates an [InboxCubit].
  InboxCubit(
    this._ticketRepository,
    this._commentRepository,
    this._linkRepository,
    this._providerRegistry,
    this._modelRoutingRepository, {
    GitRepositoryClient? gitClient,
    String? projectRootPath,
  }) : super(const InboxInitial()) {
    _gitClient = gitClient;
    _projectRootPath = projectRootPath;
  }

  final TicketRepository _ticketRepository;
  final CommentRepository _commentRepository;
  final TicketLinkRepository _linkRepository;
  final ProviderRegistry _providerRegistry;
  final ModelRoutingRepository _modelRoutingRepository;
  late final GitRepositoryClient? _gitClient;
  late final String? _projectRootPath;

  static const _uuid = Uuid();

  /// Every Inbox-spawned chat is a parentless `chat` ticket — the only
  /// type [load] queries for.
  static const _chatTypes = [TicketType.chat];

  /// Resolves [phase] to its currently configured [AgentModelDescriptor]
  /// (via [_modelRoutingRepository]) and that model's [AgentProvider]
  /// (via [_providerRegistry]). Shared helper so every one of the four
  /// launch methods resolves the pair identically — see
  /// `AIO-1544` §7.
  Future<(AgentModelDescriptor, AgentProvider)> _resolveModelAndProvider(
    ModelPhase phase,
  ) async {
    final model = await _modelRoutingRepository.getModelForPhase(phase);
    final provider = _providerRegistry.providerById(model.providerId);
    return (model, provider);
  }

  /// Fetches every Inbox-spawned chat (`getTicketsByParent(null, types:
  /// [TicketType.chat])`, filtered defensively to `inboxPurpose != null`
  /// even though nothing else can currently produce a parentless chat),
  /// sorted by `createdAt` descending. Emits [InboxLoading] then
  /// [InboxLoaded] on success, or [InboxError] if the repository call
  /// throws.
  Future<void> load() async {
    emit(const InboxLoading());
    try {
      final chats = await _ticketRepository.getTicketsByParent(
        null,
        types: _chatTypes,
      );
      final history = chats.where((t) => t.inboxPurpose != null).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      emit(InboxLoaded(history: history));
    } catch (e) {
      emit(InboxError(e.toString()));
    }
  }

  /// Classifies [rawText] into one or more `idea` tickets. Creates a
  /// parentless `chat` ticket (`inboxPurpose: brainDump`), posts the
  /// brain-dump prompt as a system comment, runs the opening turn
  /// (`toolsEnabled: false`, [ModelPhase.frontier]), then parses the
  /// reply (§5.1) into `idea` tickets each carrying a
  /// `Ticket.suggestedType`. Returns the created chat ticket's id, or
  /// `null` if the launch failed (in which case [InboxError] was
  /// emitted). Reloads [history] before returning either way.
  Future<String?> startBrainDump(String rawText) async {
    emit(const InboxLaunching(InboxPurpose.brainDump));
    try {
      final chat = await _createInboxChat(
        InboxPurpose.brainDump,
        _titleForExcerpt('Brain dump', rawText),
      );
      final prompt = _brainDumpPrompt(rawText);
      await _postSystemPrompt(chat.id, prompt);
      final (model, provider) = await _resolveModelAndProvider(
        ModelPhase.frontier,
      );
      final result = await ChatCubit.runChatTurn(
        client: provider.client,
        provider: provider,
        commentRepo: _commentRepository,
        ticketRepository: _ticketRepository,
        chatTicketId: chat.id,
        prompt: prompt,
        model: model,
      );
      // No `runId` is passed above, so ChatTurnCancelled can never
      // actually occur here in practice — handled defensively anyway,
      // preserving today's exact bool-equivalent behavior.
      if (result is ChatTurnSuccess) {
        final reply = await _lastCommentContent(chat.id);
        if (reply != null) {
          await _materializeBrainDumpIdeas(reply);
        }
      }
      await load();
      return chat.id;
    } catch (e) {
      emit(InboxError(e.toString()));
      return null;
    }
  }

  /// Advisory guidance on what to work on next — a literal port of the
  /// CLI `/what-next` skill's priority order (§5.2) onto ticket/page data.
  /// Creates the chat (`inboxPurpose: whatNextGuidance`), assembles
  /// context, and runs the opening turn (`toolsEnabled: false`,
  /// [ModelPhase.frontier]). Never parses the reply — the model's
  /// response is advisory prose only. Returns the created chat ticket's
  /// id, or `null` on failure (see [startBrainDump]).
  Future<String?> startWhatNextGuidance() async {
    emit(const InboxLaunching(InboxPurpose.whatNextGuidance));
    try {
      final chat = await _createInboxChat(
        InboxPurpose.whatNextGuidance,
        "What's next",
      );
      final prompt = await _assembleWhatNextContext();
      await _postSystemPrompt(chat.id, prompt);
      final (model, provider) = await _resolveModelAndProvider(
        ModelPhase.frontier,
      );
      await ChatCubit.runChatTurn(
        client: provider.client,
        provider: provider,
        commentRepo: _commentRepository,
        ticketRepository: _ticketRepository,
        chatTicketId: chat.id,
        prompt: prompt,
        model: model,
      );
      await load();
      return chat.id;
    } catch (e) {
      emit(InboxError(e.toString()));
      return null;
    }
  }

  /// Converses about which tickets belong in an upcoming release.
  /// Creates the chat (`inboxPurpose: releasePlanning`), assembles
  /// read-only Epic/Story/Task/Bug context (§5.3), and runs the opening
  /// turn (`toolsEnabled: false`, [ModelPhase.frontier]) — genuinely
  /// multi-turn-conversational, so the opening turn may just be a
  /// clarifying question. Runs [handleReleasePlanningReply] on the
  /// opening reply too (every later human-follow-up turn re-runs it from
  /// the caller, per that method's own dartdoc). Returns the created chat
  /// ticket's id, or `null` on failure (see [startBrainDump]).
  Future<String?> startReleasePlanning() async {
    emit(const InboxLaunching(InboxPurpose.releasePlanning));
    try {
      final chat = await _createInboxChat(
        InboxPurpose.releasePlanning,
        'Plan a release',
      );
      final prompt = await _assembleReleasePlanningContext();
      await _postSystemPrompt(chat.id, prompt);
      final (model, provider) = await _resolveModelAndProvider(
        ModelPhase.frontier,
      );
      final result = await ChatCubit.runChatTurn(
        client: provider.client,
        provider: provider,
        commentRepo: _commentRepository,
        ticketRepository: _ticketRepository,
        chatTicketId: chat.id,
        prompt: prompt,
        model: model,
      );
      // No `runId` is passed above, so ChatTurnCancelled can never
      // actually occur here in practice — handled defensively anyway,
      // preserving today's exact bool-equivalent behavior.
      if (result is ChatTurnSuccess) {
        final reply = await _lastCommentContent(chat.id);
        if (reply != null) {
          await handleReleasePlanningReply(chat.id, reply);
        }
      }
      await load();
      return chat.id;
    } catch (e) {
      emit(InboxError(e.toString()));
      return null;
    }
  }

  /// Checks [aiCommentText] — an AI comment that just persisted in the
  /// release-planning chat [chatTicketId], whether the opening turn or a
  /// later human-follow-up reply — for the terminal `RELEASE PLAN: DONE`
  /// marker (§5.3). No-ops (does not touch the repository) if the marker
  /// isn't present, or if no `RELEASE:` line was found alongside it. On a
  /// match, creates a new `release` ticket titled from the `RELEASE:`
  /// line, then one [TicketLinkRepository.createLink] (as
  /// [TicketLinkType.relatesTo], the release as source) per `LINK:` id —
  /// skipping any id that doesn't resolve to a real ticket (defensive,
  /// not surfaced as an error, since the model may hallucinate an id typo
  /// mid-conversation). Callers outside this cubit (the chat UI, after
  /// every `ChatCubit.sendMessage` persists a reply in a
  /// release-planning chat) should call this directly rather than
  /// re-deriving the marker check themselves.
  Future<void> handleReleasePlanningReply(
    String chatTicketId,
    String aiCommentText,
  ) async {
    if (!aiCommentText.contains('RELEASE PLAN: DONE')) return;
    final releaseName = _parseReleaseName(aiCommentText);
    if (releaseName == null) return;

    final now = DateTime.now();
    final release = Ticket(
      id: _uuid.v4(),
      ticketId: '',
      type: TicketType.release,
      title: releaseName,
      // InboxCubit has no WorkflowStatusRepository of its own (out of
      // scope for `AIO-549`) — the
      // literal mirrors `defaultWorkflowStatuses`' lowest-sortOrder base
      // status name, same as every unconfigured project's real default.
      status: 'backlog',
      createdAt: now,
      updatedAt: now,
    );
    await _ticketRepository.createTicket(release);

    for (final linkedId in _parseReleaseLinkIds(aiCommentText)) {
      final target = await _ticketRepository.getTicketById(linkedId);
      if (target == null) continue;
      await _linkRepository.createLink(
        sourceTicketId: release.id,
        targetTicketId: target.id,
        linkType: TicketLinkType.relatesTo,
      );
    }
  }

  /// General read-only Q&A over tickets, docs, and source code. Creates
  /// the chat (`inboxPurpose: qa`), then runs a one-shot,
  /// worktree-isolated opening turn per §3 — mirrors
  /// `TicketsCubit._runFullSummarization`'s exact worktree-create/run/
  /// remove-in-`finally` shape: a fresh, throwaway
  /// [GitRepositoryClient.createWorktree] (never [_projectRootPath]
  /// itself), `toolsEnabled: true`, [ModelPhase.capable]. Every later
  /// reply in this chat goes through the ordinary `ChatCubit.sendMessage`
  /// path, not this method. Emits [InboxError] immediately, creating no
  /// chat, if constructed without a [GitRepositoryClient]/
  /// [_projectRootPath] (mobile/web, which has no user-chosen project
  /// directory). Returns the created chat ticket's id, or `null` on
  /// failure (see [startBrainDump]).
  Future<String?> startQa(String initialQuestion) async {
    emit(const InboxLaunching(InboxPurpose.qa));
    final gitClient = _gitClient;
    final rootPath = _projectRootPath;
    if (gitClient == null || rootPath == null) {
      emit(
        const InboxError(
          'Ask a question requires an open, git-tracked project directory.',
        ),
      );
      return null;
    }

    final worktreePath = Directory.systemTemp
        .createTempSync('aion_inbox_qa_')
        .path;
    final branchName = 'aion/inbox-qa-${_uuid.v4()}';
    try {
      final chat = await _createInboxChat(
        InboxPurpose.qa,
        _titleForExcerpt('Q&A', initialQuestion),
      );
      final prompt = _qaPrompt(initialQuestion);
      await _postSystemPrompt(chat.id, prompt);
      final (model, provider) = await _resolveModelAndProvider(
        ModelPhase.capable,
      );
      try {
        await gitClient.createWorktree(rootPath, worktreePath, branchName);
        await ChatCubit.runChatTurn(
          client: provider.client,
          provider: provider,
          commentRepo: _commentRepository,
          ticketRepository: _ticketRepository,
          chatTicketId: chat.id,
          prompt: prompt,
          model: model,
          toolsEnabled: true,
          workingDirectory: worktreePath,
        );
      } finally {
        try {
          await gitClient.removeWorktree(rootPath, worktreePath);
        } catch (_) {
          // Best-effort cleanup only, mirrors _runFullSummarization's own
          // finally block — createWorktree may itself have failed, in
          // which case there's nothing to remove.
        }
      }
      await load();
      return chat.id;
    } catch (e) {
      emit(InboxError(e.toString()));
      return null;
    }
  }

  /// Creates a parentless `chat` ticket tagged with [purpose] and titled
  /// [title], then re-fetches it so the returned [Ticket] carries its
  /// generated `ticketId`. Throws [StateError] if the created ticket
  /// can't be re-fetched — mirrors `TicketsCubit._runFullSummarization`'s
  /// own post-create fetch-and-check.
  Future<Ticket> _createInboxChat(InboxPurpose purpose, String title) async {
    final now = DateTime.now();
    final chat = Ticket(
      id: _uuid.v4(),
      ticketId: '',
      type: TicketType.chat,
      title: title,
      // InboxCubit has no WorkflowStatusRepository of its own (out of
      // scope for `AIO-549`) — the
      // literal mirrors `defaultWorkflowStatuses`' lowest-sortOrder base
      // status name, same as every unconfigured project's real default.
      status: 'backlog',
      inboxPurpose: purpose,
      createdAt: now,
      updatedAt: now,
    );
    await _ticketRepository.createTicket(chat);
    final persisted = await _ticketRepository.getTicketById(chat.id);
    if (persisted == null) {
      throw StateError('Could not create the Inbox chat.');
    }
    return persisted;
  }

  /// Posts [content] as a [CommentAuthorType.system] comment on
  /// [chatTicketId] — the same "post the assembled prompt so the
  /// transcript shows what was asked" step
  /// `TicketsCubit._runFullSummarization` uses before calling
  /// [ChatCubit.runChatTurn] with the identical text.
  Future<void> _postSystemPrompt(String chatTicketId, String content) {
    return _commentRepository.addComment(
      TicketComment(
        id: '',
        ticketId: chatTicketId,
        content: content,
        authorType: CommentAuthorType.system,
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Returns [chatTicketId]'s most recent comment's content, or `null` if
  /// it has none. Mirrors `TicketsCubit._lastCommentContent` exactly (that
  /// helper is private to `tickets_cubit.dart` and not reusable here).
  Future<String?> _lastCommentContent(String chatTicketId) async {
    final comments = await _commentRepository.getCommentsForTicket(
      chatTicketId,
    );
    if (comments.isEmpty) return null;
    final mostRecent = comments.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    return mostRecent.content;
  }

  /// A short chat title: [label] plus a truncated first-line excerpt of
  /// [text] (max 60 chars, ellipsized), or just [label] if [text] has no
  /// non-whitespace content.
  String _titleForExcerpt(String label, String text) {
    final firstLine = text.trim().split('\n').first.trim();
    if (firstLine.isEmpty) return label;
    final excerpt = firstLine.length > 60
        ? '${firstLine.substring(0, 60)}…'
        : firstLine;
    return '$label — $excerpt';
  }

  /// §5.1's brain-dump prompt: instructs the model to classify [rawText]
  /// into one or more `IDEA:`/`TYPE:` blocks, terminated by a
  /// `BRAINDUMP: DONE` line.
  String _brainDumpPrompt(String rawText) {
    return 'Read the following raw notes and identify one or more '
        'distinct ideas or issues worth turning into tickets. For each, '
        'reply in exactly this format:\n\n'
        'IDEA: <short title>\n'
        '<one to three sentence description>\n'
        'TYPE: epic|bug\n\n'
        'End your reply with exactly one line: "BRAINDUMP: DONE".\n\n'
        'Raw notes:\n$rawText';
  }

  /// Parses a brain-dump reply (mirrors
  /// `TicketsCubit._parseSummaryFindings`'s block-splitting shape): each
  /// `IDEA:` line starts a new block; a `TYPE:` line (case-insensitive,
  /// `epic` or `bug`, anything else treated as absent) sets that block's
  /// suggested type; everything else until the next `IDEA:`/terminal
  /// line is the description. A block with an empty title is dropped.
  List<({String title, String description, TicketType? suggestedType})>
  _parseBrainDumpBlocks(String reply) {
    final blocks =
        <({String title, String description, TicketType? suggestedType})>[];
    String? currentTitle;
    TicketType? currentSuggestedType;
    final currentBody = StringBuffer();

    void flush() {
      final title = currentTitle?.trim();
      if (title != null && title.isNotEmpty) {
        blocks.add((
          title: title,
          description: currentBody.toString().trim(),
          suggestedType: currentSuggestedType,
        ));
      }
      currentBody.clear();
      currentSuggestedType = null;
    }

    for (final line in reply.split('\n')) {
      final trimmed = line.trim();
      final ideaMatch = RegExp(r'^IDEA:\s*(.*)$').firstMatch(trimmed);
      if (ideaMatch != null) {
        flush();
        currentTitle = ideaMatch.group(1);
        continue;
      }
      if (trimmed == 'BRAINDUMP: DONE') {
        flush();
        currentTitle = null;
        return blocks;
      }
      final typeMatch = RegExp(
        r'^TYPE:\s*(.*)$',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (typeMatch != null && currentTitle != null) {
        final raw = typeMatch.group(1)?.trim().toLowerCase();
        currentSuggestedType = switch (raw) {
          'epic' => TicketType.epic,
          'bug' => TicketType.bug,
          _ => null,
        };
        continue;
      }
      if (currentTitle != null) {
        currentBody.writeln(line);
      }
    }
    flush();
    return blocks;
  }

  /// Creates one `idea` ticket per [_parseBrainDumpBlocks] block found
  /// in [reply], each carrying its parsed `suggestedType` (`null` if the
  /// model omitted or malformed its `TYPE:` line — a parse failure on one
  /// block shouldn't crash the rest of the reply). Renamed from
  /// `_materializeBrainDumpSignals` for
  /// `AIO-934`.
  Future<void> _materializeBrainDumpIdeas(String reply) async {
    final now = DateTime.now();
    for (final block in _parseBrainDumpBlocks(reply)) {
      await _ticketRepository.createTicket(
        Ticket(
          id: _uuid.v4(),
          ticketId: '',
          type: TicketType.idea,
          title: block.title,
          description: block.description.isEmpty ? null : block.description,
          // InboxCubit has no WorkflowStatusRepository of its own (out of
      // scope for `AIO-549`) — the
      // literal mirrors `defaultWorkflowStatuses`' lowest-sortOrder base
      // status name, same as every unconfigured project's real default.
      status: 'backlog',
          suggestedType: block.suggestedType,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  }

  /// §5.2's context assembly: in-flight SDD-stage tickets, open
  /// `knownGap`/`openQuestion` tickets (each resolved against its own
  /// `relatesTo` target for context), and open (not yet promoted) `idea`
  /// tickets — assembled as one plain-text prompt (no tool access,
  /// matching `designSync`'s existing shape). The model's reply is
  /// advisory prose, never parsed or acted on programmatically. The prior
  /// markdown "## Known gaps" page-scanning path
  /// (`_extractKnownGapsSection`) is retired as of
  /// `AIO-934` — superseded by
  /// first-class `knownGap`/`openQuestion` tickets.
  Future<String> _assembleWhatNextContext() async {
    final all = await _ticketRepository.getAllTickets();

    final inFlight = all
        .where((t) => t.sddStage != null && t.sddStage != SddStage.archived)
        .toList();

    final gapsAndQuestions = all
        .where(
          (t) =>
              t.type == TicketType.knownGap ||
              t.type == TicketType.openQuestion,
        )
        .toList();
    final gapsAndQuestionsWithTarget = <(Ticket, Ticket?)>[];
    for (final gap in gapsAndQuestions) {
      final links = await _linkRepository.getLinksForTicket(gap.id);
      String? targetId;
      for (final l in links) {
        if (l.sourceTicketId == gap.id &&
            l.linkType == TicketLinkType.relatesTo.name) {
          targetId = l.targetTicketId;
          break;
        }
      }
      final target = targetId == null
          ? null
          : await _ticketRepository.getTicketById(targetId);
      gapsAndQuestionsWithTarget.add((gap, target));
    }

    final openIdeas = <Ticket>[];
    for (final idea in all.where((t) => t.type == TicketType.idea)) {
      final links = await _linkRepository.getLinksForTicket(idea.id);
      final promoted = links.any(
        (l) =>
            l.sourceTicketId == idea.id &&
            l.linkType == TicketLinkType.relatesTo.name,
      );
      if (!promoted) openIdeas.add(idea);
    }

    final buffer = StringBuffer()
      ..writeln(
        'Recommend the single most valuable next action for this '
        'project, in this priority order: (1) any in-flight SDD-stage '
        'work already underway, (2) open known gaps/open questions '
        'raised against existing tickets, (3) open, not-yet-promoted '
        'ideas.',
      )
      ..writeln();

    if (inFlight.isNotEmpty) {
      buffer.writeln('In-flight SDD-stage tickets:');
      for (final t in inFlight) {
        buffer.writeln('- ${t.title} (${t.type.name}, stage: '
            '${t.sddStage?.name})');
      }
      buffer.writeln();
    }
    if (gapsAndQuestionsWithTarget.isNotEmpty) {
      buffer.writeln('Open known gaps / open questions:');
      for (final (gap, target) in gapsAndQuestionsWithTarget) {
        final label = gap.type == TicketType.knownGap
            ? 'Known gap'
            : 'Open question';
        final onTarget = target == null ? '' : ' (on "${target.title}")';
        buffer.writeln('- $label: ${gap.title}$onTarget');
      }
      buffer.writeln();
    }
    if (openIdeas.isNotEmpty) {
      buffer.writeln('Open, not-yet-promoted ideas:');
      for (final t in openIdeas) {
        final description = t.description;
        buffer.writeln(
          description == null || description.isEmpty
              ? '- ${t.title}'
              : '- ${t.title}: $description',
        );
      }
      buffer.writeln();
    }
    buffer.writeln(
      'Give one concise, advisory recommendation with your reasoning. '
      'Do not create or modify any ticket.',
    );
    return buffer.toString().trim();
  }

  /// §5.3's context assembly: every current Epic/Story/Task/Bug ticket's
  /// id, title, and status (read-only `TicketRepository` query, not agent
  /// tool access), followed by instructions for the model to converse
  /// about release scope and, once settled, reply with the terminal
  /// `RELEASE:`/`LINK:`/`RELEASE PLAN: DONE` format
  /// [handleReleasePlanningReply] parses.
  Future<String> _assembleReleasePlanningContext() async {
    final tickets = await _ticketRepository.getAllTicketsByType(const [
      TicketType.epic,
      TicketType.story,
      TicketType.task,
      TicketType.bug,
    ]);

    final buffer = StringBuffer()
      ..writeln(
        'Help the user plan a release. Below is every current Epic/'
        'Story/Task/Bug ticket (id, title, type, status).',
      )
      ..writeln();
    for (final t in tickets) {
      buffer.writeln('- ${t.id} | ${t.title} | ${t.type.name} | '
          '${t.status}');
    }
    buffer
      ..writeln()
      ..writeln(
        'Converse with the user about which tickets belong in this '
        'release. Once settled, reply with exactly this format:',
      )
      ..writeln('RELEASE: <release name>')
      ..writeln('LINK: <ticket id>')
      ..writeln('LINK: <ticket id>')
      ..writeln('...')
      ..writeln('RELEASE PLAN: DONE');
    return buffer.toString().trim();
  }

  /// Parses the terminal `RELEASE:` line's release name out of a
  /// release-planning reply, or `null` if no such line is present or its
  /// name is empty.
  String? _parseReleaseName(String reply) {
    for (final line in reply.split('\n')) {
      final match = RegExp(r'^RELEASE:\s*(.*)$').firstMatch(line.trim());
      if (match == null) continue;
      final name = match.group(1)?.trim();
      if (name != null && name.isNotEmpty) return name;
    }
    return null;
  }

  /// Parses every `LINK:` line's ticket id out of a release-planning
  /// reply, in order, skipping any with an empty id.
  List<String> _parseReleaseLinkIds(String reply) {
    final ids = <String>[];
    for (final line in reply.split('\n')) {
      final match = RegExp(r'^LINK:\s*(.*)$').firstMatch(line.trim());
      if (match == null) continue;
      final id = match.group(1)?.trim();
      if (id != null && id.isNotEmpty) ids.add(id);
    }
    return ids;
  }

  /// §3's Q&A prompt: an explicitly read-only exploration instruction
  /// (never edit/commit/push) plus [initialQuestion].
  String _qaPrompt(String initialQuestion) {
    return "You are answering a question about this project's tickets, "
        'documentation, and source code. Read whatever files you need '
        'using the available tools — do not edit, commit, or otherwise '
        'modify anything; this is a read-only exploration.\n\n'
        'Question: $initialQuestion';
  }
}
