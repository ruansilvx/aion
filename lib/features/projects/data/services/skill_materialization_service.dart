// data/services/skill_materialization_service.dart — SkillMaterializationService (data layer).

import 'dart:convert';
import 'dart:io';

import 'package:aion/features/projects/domain/entities/baseline_asset.dart';
import 'package:aion/features/projects/domain/entities/baseline_manifest.dart';
import 'package:aion/features/projects/domain/repositories/baseline_repository.dart';

/// Writes a project's [BaselineAssetKind.skill] assets onto its own disk as
/// `<rootPath>/.claude/skills/<name>/SKILL.md` files, so a
/// `SkillAttachmentKind.delegatedSkill` attachment — which sends the bare
/// prompt `/<skillName>` and relies entirely on the underlying coding
/// agent's own filesystem skill discovery — actually finds something to run.
///
/// Nothing else in the app materializes these files: the baseline/override
/// model ([BaselineRepository]) only ever stored a skill's *content*
/// (bundled default, optionally shadowed by an override under
/// `<rootPath>/.aion/overrides/`), never a discoverable skill file. This
/// service closes that gap and is called from every point where the
/// resolved content of a skill asset can change:
///
/// - project creation (`CreateProjectCubit.submit`),
/// - a baseline version upgrade (`ActiveProjectCubit.acceptBaselineUpgrade`),
/// - saving a local override for a skill asset (`OverrideEditorCubit.save`).
///
/// Desktop only, by construction: every entry point takes a non-null
/// `rootPath`, which only desktop projects have (see `BaselineRepository`'s
/// platform note). Mobile/web callers simply never reach it.
///
/// **Never deletes and never overwrites a file it does not own.** A
/// hand-authored `.claude/skills/<name>/SKILL.md` that predates Aion (or
/// belongs to the user's own tooling) is left exactly as it is, and an
/// asset dropped from a newer manifest leaves its previously-generated file
/// behind rather than being purged — `.claude/skills/` is a directory Aion
/// shares with the user's coding agent, not one it owns outright. Ownership
/// is recognized by [managedMarker], written into every generated file.
class SkillMaterializationService {
  /// Creates a [SkillMaterializationService] backed by
  /// [_baselineRepository], which resolves each skill asset's effective
  /// content (a project override if one exists, otherwise the bundled
  /// default).
  SkillMaterializationService(this._baselineRepository);

  final BaselineRepository _baselineRepository;

  /// Marker line written directly below the YAML frontmatter of every file
  /// this service generates. Its presence in an existing file is what
  /// authorizes overwriting that file; its absence means the file is
  /// hand-authored (or foreign) and must be left untouched.
  ///
  /// An HTML comment rather than a frontmatter field, deliberately: coding
  /// agents parse the frontmatter for known keys (`name`, `description`,
  /// …) and an unrecognized one risks a validation warning, whereas a
  /// Markdown comment is inert everywhere.
  static const managedMarker = '<!-- aion:managed-skill -->';

  /// Longest [description] frontmatter value this service will emit, in
  /// characters. A skill body's opening paragraph is usually well under
  /// this; anything longer is truncated on a word boundary by
  /// [buildSkillDocument].
  static const maxDescriptionLength = 400;

  /// Materializes every [BaselineAssetKind.skill] asset in [manifest] for
  /// the project identified by [projectId] and rooted at [rootPath],
  /// resolving each asset's content through its local override when
  /// [BaselineRepository.readOverrides] reports one and through the bundled
  /// default otherwise.
  ///
  /// Called with the version's own manifest at project creation and with
  /// the *new* manifest on a baseline upgrade, so an upgraded project picks
  /// up both newly-introduced skills and revised bodies of existing ones.
  /// Skips — without failing the whole run — any individual asset whose
  /// content cannot be read or whose file cannot be written, since a
  /// half-materialized skill set is strictly better than a project creation
  /// aborted by one unreadable asset.
  Future<void> materializeAll({
    required String projectId,
    required String rootPath,
    required BaselineManifest manifest,
  }) async {
    final overrides = await _baselineRepository.readOverrides(projectId);
    final overridePathByKey = <String, String>{
      for (final override in overrides)
        override.assetKey: override.overridePath,
    };

    for (final asset in manifest.assets) {
      if (asset.kind != BaselineAssetKind.skill) continue;
      try {
        final overridePath = overridePathByKey[asset.key];
        final content = overridePath != null
            ? await _baselineRepository.readOverrideContent(overridePath)
            : await _baselineRepository.readBundledContent(asset);
        materializeSkill(rootPath: rootPath, asset: asset, content: content);
      } catch (_) {
        // One unreadable asset must not abort the rest — see the dartdoc.
        continue;
      }
    }
  }

  /// Materializes exactly one skill asset, using the already-resolved
  /// [content] the caller holds rather than re-reading it. Used by
  /// `OverrideEditorCubit.save`, which has just written that content as the
  /// project's override and needs the discoverable file to reflect it
  /// immediately instead of staying pinned to the stale bundled body.
  ///
  /// No-ops when [asset] is not a [BaselineAssetKind.skill] (a saved
  /// `modelConfig`/`architectureConvention` override has no
  /// `.claude/skills/` representation), and when the target file already
  /// exists without [managedMarker] — see the class dartdoc's ownership
  /// rule.
  ///
  /// Synchronous file I/O internally, matching
  /// [ProjectManifestWriter](../../../../core/build/project_manifest_writer.dart):
  /// real asynchronous file I/O does not reliably complete inside
  /// `flutter_test`'s fake-async zone, which every Cubit call site here
  /// runs under.
  void materializeSkill({
    required String rootPath,
    required BaselineAsset asset,
    required String content,
  }) {
    if (asset.kind != BaselineAssetKind.skill) return;

    final skillName = skillNameOf(asset);
    if (skillName.isEmpty) return;

    final sep = Platform.pathSeparator;
    final file = File(
      '$rootPath$sep.claude${sep}skills$sep$skillName${sep}SKILL.md',
    );
    if (file.existsSync() && !file.readAsStringSync().contains(managedMarker)) {
      return;
    }

    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      buildSkillDocument(skillName: skillName, body: content),
    );
  }

  /// The bare skill name a [BaselineAsset] materializes under — its key's
  /// last path segment (`"skills/clean-up"` → `"clean-up"`). Deliberately
  /// the same segment [BaselineRepository.writeOverride] names override
  /// files by, and the same text a user types into a `delegatedSkill`
  /// attachment's skill-name field, so the three stay addressable by one
  /// identifier.
  static String skillNameOf(BaselineAsset asset) => asset.key.split('/').last;

  /// Composes the full text of a `SKILL.md` file: YAML frontmatter
  /// carrying [skillName] and a description derived from [body], the
  /// [managedMarker] ownership comment, then [body] verbatim.
  ///
  /// The description is [body]'s first real paragraph — everything before
  /// the first blank line, skipping any leading Markdown heading — with
  /// its internal line breaks collapsed to single spaces and, if still
  /// longer than [maxDescriptionLength], truncated at the last word
  /// boundary that fits and suffixed with an ellipsis. It is emitted as a
  /// double-quoted YAML scalar (with `\` and `"` escaped) because [body]
  /// may be arbitrary user-authored override text containing `:`, `#`, or
  /// quotes, none of which are safe in a plain scalar.
  ///
  /// Falls back to a generic one-liner when [body] has no prose at all
  /// (an empty or heading-only override), since a coding agent's skill
  /// loader treats a missing `description` as a malformed skill.
  static String buildSkillDocument({
    required String skillName,
    required String body,
  }) {
    final description = _describe(body, skillName);
    return '---\n'
        'name: $skillName\n'
        'description: "${_escapeYamlDoubleQuoted(description)}"\n'
        '---\n'
        '\n'
        '$managedMarker\n'
        '\n'
        '$body';
  }

  /// Derives the frontmatter description from [body] — see
  /// [buildSkillDocument] for the rules — falling back to a generic
  /// sentence naming [skillName] when [body] carries no prose paragraph.
  static String _describe(String body, String skillName) {
    final paragraph = <String>[];
    for (final rawLine in const LineSplitter().convert(body)) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        if (paragraph.isNotEmpty) break;
        continue;
      }
      // Skip a leading `# name` title (and any further heading lines
      // above the first paragraph) — it repeats `name:` rather than
      // describing the skill.
      if (paragraph.isEmpty && line.startsWith('#')) continue;
      paragraph.add(line);
    }

    final collapsed = paragraph
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (collapsed.isEmpty) {
      return 'The $skillName skill, provided by this project\'s Aion '
          'baseline.';
    }
    if (collapsed.length <= maxDescriptionLength) return collapsed;

    final clipped = collapsed.substring(0, maxDescriptionLength);
    final lastSpace = clipped.lastIndexOf(' ');
    final trimmed = (lastSpace > 0 ? clipped.substring(0, lastSpace) : clipped)
        .trimRight();
    return '$trimmed…';
  }

  /// Escapes [value] for use inside a double-quoted YAML scalar:
  /// backslashes and double quotes only, since [_describe] has already
  /// collapsed every line break out of it.
  static String _escapeYamlDoubleQuoted(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
