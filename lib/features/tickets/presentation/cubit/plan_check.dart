// presentation/cubit/plan_check.dart — Frontier plan-check prompt, reply parser and lead report for the escalation ladder (presentation layer).

import 'package:aion/features/tickets/presentation/cubit/escalation_ladder.dart';

/// What a Frontier plan check concluded about a repeatedly-failing Task
/// (`AIO-3057`).
enum PlanCheckVerdict {
  /// The plan is sound, or the check could not prove otherwise. Also the
  /// fail-closed result for any malformed reply.
  ok,

  /// The Task description itself is wrong; [PlanCheckResult.revisedDescription]
  /// replaces it.
  taskRewrite,

  /// The parent plan (Story description or approved Proposed-stage plan) is
  /// wrong. Aion never edits it: [PlanCheckResult.storyChangeRequest] goes to
  /// a human.
  storyChange,
}

/// The parsed reply of a Frontier plan check turn. See [PlanCheckResult.parse].
class PlanCheckResult {
  /// Creates a [PlanCheckResult].
  const PlanCheckResult({
    required this.verdict,
    required this.rawReply,
    this.revisedDescription,
    this.storyChangeRequest,
    this.suspectedCauses,
  });

  /// The conclusion; [PlanCheckVerdict.ok] unless the reply proved otherwise.
  final PlanCheckVerdict verdict;

  /// The reply exactly as received (empty when there was none).
  final String rawReply;

  /// The complete replacement Task description. Non-null only for
  /// [PlanCheckVerdict.taskRewrite].
  final String? revisedDescription;

  /// The requested Story-plan edits ("was -> now, because (evidence)").
  /// Non-null only for [PlanCheckVerdict.storyChange].
  final String? storyChangeRequest;

  /// The reviewer's `## Suspected Causes` section, if any — what a human
  /// should look at first.
  final String? suspectedCauses;

  static final _verdictLine = RegExp(
    r'^PLAN CHECK: (OK|TASK REWRITE|STORY CHANGE)$',
  );
  static final _decoration = RegExp(r'^[\s*`"]+|[\s*`"]+$');

  /// Parses [reply] (see [PlanCheckPrompt.build] for the protocol). Fails
  /// closed to [PlanCheckVerdict.ok]: a missing reply, a missing or unknown
  /// final `PLAN CHECK:` line, or a `TASK REWRITE`/`STORY CHANGE` without a
  /// non-empty `## Revised Task Description`/`## Story Change Request`
  /// section all mean "no proven plan problem".
  factory PlanCheckResult.parse(String? reply) {
    final raw = reply ?? '';
    final lines = raw.trimRight().split('\n');
    final lastIndex = lines.isEmpty ? -1 : lines.length - 1;
    final cleanedLast = lastIndex < 0
        ? ''
        : lines[lastIndex].replaceAll(_decoration, '');
    final match = _verdictLine.firstMatch(cleanedLast);
    final causes = _suspectedCauses(lines, lastIndex);
    PlanCheckResult ok() => PlanCheckResult(
      verdict: PlanCheckVerdict.ok,
      rawReply: raw,
      suspectedCauses: causes,
    );
    if (match == null) return ok();
    switch (match.group(1)) {
      case 'TASK REWRITE':
        final body = _sectionBody(lines, lastIndex, 'Revised Task Description');
        if (body == null) return ok();
        return PlanCheckResult(
          verdict: PlanCheckVerdict.taskRewrite,
          rawReply: raw,
          revisedDescription: body,
          suspectedCauses: causes,
        );
      case 'STORY CHANGE':
        final body = _sectionBody(lines, lastIndex, 'Story Change Request');
        if (body == null) return ok();
        return PlanCheckResult(
          verdict: PlanCheckVerdict.storyChange,
          rawReply: raw,
          storyChangeRequest: body,
          suspectedCauses: causes,
        );
      default:
        return ok();
    }
  }

  /// The text between the `## <heading>` line and the verdict line at
  /// [verdictIndex], trimmed — `null` when the heading is absent or the body
  /// empty. Runs to the verdict line (not the next heading) because a revised
  /// description may legitimately contain its own `##` headings.
  static String? _sectionBody(
    List<String> lines,
    int verdictIndex,
    String heading,
  ) {
    final start = lines.indexWhere(
      (l) => l.replaceAll(_decoration, '') == '## $heading',
    );
    if (start < 0 || start >= verdictIndex) return null;
    final body = lines.sublist(start + 1, verdictIndex).join('\n').trim();
    return body.isEmpty ? null : body;
  }

  /// The `## Suspected Causes` body: up to the next `## ` heading or the
  /// verdict line.
  static String? _suspectedCauses(List<String> lines, int verdictIndex) {
    final start = lines.indexWhere(
      (l) => l.replaceAll(_decoration, '') == '## Suspected Causes',
    );
    if (start < 0) return null;
    var end = verdictIndex < 0 ? lines.length : verdictIndex;
    for (var i = start + 1; i < end; i++) {
      if (lines[i].startsWith('## ')) {
        end = i;
        break;
      }
    }
    final body = lines.sublist(start + 1, end).join('\n').trim();
    return body.isEmpty ? null : body;
  }

  /// This result with its verdict reduced to [PlanCheckVerdict.ok], keeping
  /// the reply and suspected causes — for a verdict whose action turned out to
  /// be a no-op (a `TASK REWRITE` that changes nothing).
  PlanCheckResult asOk() => PlanCheckResult(
    verdict: PlanCheckVerdict.ok,
    rawReply: rawReply,
    suspectedCauses: suspectedCauses,
  );

  /// A short human-readable account of what the check found: the suspected
  /// causes when given, else the reply itself (truncated).
  String get summary {
    final causes = suspectedCauses;
    if (causes != null) return causes;
    final text = rawReply.trim();
    if (text.isEmpty) return 'The plan check produced no reply.';
    return text.length > 1000 ? '${text.substring(0, 1000)}...' : text;
  }
}

/// Builds the Frontier plan-check prompt and the human-facing lead report.
abstract final class PlanCheckPrompt {
  /// The prompt for the read-only Frontier plan check: [title], [description]
  /// and [planSection] (the parent plan, or `null` for an orphan Task) are the
  /// plan under test; [failures] the self-verify failures that led here.
  ///
  /// Reply protocol (parsed by [PlanCheckResult.parse]): an optional
  /// `## Suspected Causes` section, then at most one of `## Revised Task
  /// Description` / `## Story Change Request`, then a final
  /// `PLAN CHECK: OK | TASK REWRITE | STORY CHANGE` line.
  static String build({
    required String title,
    required String? description,
    required String? planSection,
    required List<LadderFailure> failures,
  }) {
    final b = StringBuffer()
      ..writeln(
        'You are the planning reviewer for a coding Task that implementer '
        'models have repeatedly failed to complete: their own self-verification '
        'failed ${failures.length} times, including on a stronger model. '
        'Before anyone retries, decide whether the PLAN is the problem. You '
        'may read files in the worktree but must not modify anything; the '
        'worktree may contain an earlier failed attempt, so judge the plan '
        'against the codebase, not against that attempt.',
      )
      ..writeln()
      ..writeln('# $title');
    if (description != null && description.isNotEmpty) {
      b
        ..writeln()
        ..writeln(description);
    }
    if (planSection != null) {
      b
        ..writeln()
        ..writeln(planSection);
    }
    b
      ..writeln()
      ..writeln('## Failures so far')
      ..writeln();
    for (var i = 0; i < failures.length; i++) {
      b.writeln(
        '${i + 1}. [${failures[i].rung.name} model] ${failures[i].reason}',
      );
    }
    b
      ..writeln()
      ..writeln('## What to decide')
      ..writeln()
      ..writeln(
        '1. The Task description above is wrong, ambiguous or contradicts the '
        'codebase (e.g. it names a file, call site or behavior that does not '
        'exist): rewrite it so an implementer could succeed.',
      )
      ..writeln(
        '2. The parent plan above (the Story description or approved plan) '
        'contradicts the codebase: you must NOT edit it. Describe each change '
        'a human should approve.',
      )
      ..writeln(
        '3. The plan is sound, or you cannot prove a defect: answer OK. Only '
        'claim a defect you can prove — quote the plan\'s claim and the code '
        'fact (with its path) that contradicts it. When unsure, answer OK.',
      )
      ..writeln()
      ..writeln('## Reply format')
      ..writeln()
      ..writeln(
        'In this order: an optional "## Suspected Causes" section (what a '
        'human should look at first, each with its evidence); then, only if '
        'applicable, exactly one of "## Revised Task Description" (the '
        'complete replacement description, nothing else) or "## Story Change '
        'Request" (one bullet per change: "was -> now, because (evidence)"); '
        'then, as your final line, exactly one of "PLAN CHECK: OK", "PLAN '
        'CHECK: TASK REWRITE" or "PLAN CHECK: STORY CHANGE".',
      );
    return b.toString().trim();
  }

  /// The lead report a human reads when the ladder is exhausted: [trail] (the
  /// failures this run counted), [check] (the plan check, or `null` when it
  /// could not run) and whether a Task rewrite was applied
  /// ([rewriteApplied]).
  static String leadReport({
    required List<LadderFailure> trail,
    required PlanCheckResult? check,
    required bool rewriteApplied,
  }) {
    final b = StringBuffer()
      ..writeln(
        'The escalation ladder ran out without a passing self-verify. Here is '
        'what was tried and where to look first.',
      )
      ..writeln()
      ..writeln('What was tried:');
    if (trail.isEmpty) {
      b.writeln('- (no self-verify failures recorded in this run)');
    }
    for (final f in trail) {
      b.writeln('- ${f.rung.name} model failed self-verify: ${f.reason}');
    }
    if (rewriteApplied) {
      b.writeln(
        '- The Frontier plan check rewrote the Task description and one '
        'final Execution attempt was made on it.',
      );
    }
    b
      ..writeln()
      ..writeln('Frontier plan check:');
    if (check == null) {
      b.writeln('- It could not run.');
    } else {
      b.writeln(switch (check.verdict) {
        PlanCheckVerdict.ok => '- Verdict: no provable plan defect.',
        PlanCheckVerdict.taskRewrite =>
          '- Verdict: Task description rewritten.',
        PlanCheckVerdict.storyChange =>
          '- Verdict: the Story plan needs a change (see the change request '
              'comment above).',
      });
      b
        ..writeln()
        ..writeln('Suspected causes:')
        ..writeln(check.summary);
    }
    return b.toString().trim();
  }
}
