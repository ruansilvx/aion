// presentation/screens/overrides_list_screen.dart — Overrides list screen (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/projects/domain/entities/baseline_asset.dart';
import 'package:aion/features/projects/presentation/cubit/overrides_cubit.dart';
import 'package:aion/features/projects/presentation/cubit/overrides_state.dart';

/// The `/workspace/settings/overrides` route: lists every baseline asset
/// in the active project's pinned manifest, marking which ones have a
/// local project override. Tapping a row opens `OverrideEditorScreen` for
/// that asset. Reached from `SettingsScreen`'s "Manage Overrides" button.
class OverridesListScreen extends StatelessWidget {
  /// Creates an [OverridesListScreen].
  const OverridesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    return ColoredBox(
      color: c.background,
      child: Column(
        children: [
          AppHeader(
            title: context.l10n.overridesListTitle,
            showBack: true,
            onBack: () => context.go('/workspace/settings'),
          ),
          Expanded(
            child: BlocBuilder<OverridesCubit, OverridesState>(
              builder: (context, state) {
                return switch (state) {
                  OverridesLoading() => const Center(child: AppSpinner()),
                  OverridesError(:final message) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message,
                          style: AionText.body.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AionSpacing.sp12),
                        AppButton(
                          label: context.l10n.commonRetry,
                          onPressed: () =>
                              context.read<OverridesCubit>().load(),
                        ),
                      ],
                    ),
                  ),
                  OverridesReady(:final manifest, :final overrides) =>
                    _OverridesList(
                      assets: manifest.assets,
                      overriddenKeys: overrides
                          .map((o) => o.assetKey)
                          .toSet(),
                    ),
                };
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OverridesList extends StatelessWidget {
  const _OverridesList({required this.assets, required this.overriddenKeys});

  final List<BaselineAsset> assets;
  final Set<String> overriddenKeys;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    if (assets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Text(
            context.l10n.overridesListEmptyState,
            textAlign: TextAlign.center,
            style: AionText.bodySm.copyWith(color: c.textMuted),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: assets.length,
      separatorBuilder: (context, _) =>
          DecoratedBox(
            decoration: BoxDecoration(color: c.border),
            child: const SizedBox(height: 1),
          ),
      itemBuilder: (context, index) {
        final asset = assets[index];
        return _OverrideListRow(
          asset: asset,
          isOverridden: overriddenKeys.contains(asset.key),
          onTap: () => context.go(
            '/workspace/settings/overrides/${Uri.encodeComponent(asset.key)}',
          ),
        );
      },
    );
  }
}

/// The two kinds a baseline asset renders as in this list — drives only
/// the kind glyph and its color (`_kindGlyphs`/[kindGlyphColor]). Distinct
/// from the wider [BaselineAssetKind] (which also has `modelConfig`, an
/// asset kind this list treats visually as a convention — see
/// [overrideKindOf]) — this narrower enum is the row's actual view model,
/// per AIO-1654 §5.
enum OverrideKind {
  /// A `skills/*` baseline asset — rendered with the sparkle glyph in
  /// [AionColors.primary].
  skill,

  /// Any non-skill baseline asset (`conventions/*`, `config/*`) —
  /// rendered with the ruler glyph in [AionColors.secondary].
  convention,
}

/// Maps a manifest asset's [BaselineAssetKind] to the row's narrower
/// [OverrideKind] — only [BaselineAssetKind.skill] is visually distinct;
/// every other kind (`modelConfig`, `architectureConvention`) reads as a
/// [OverrideKind.convention].
OverrideKind overrideKindOf(BaselineAssetKind kind) =>
    kind == BaselineAssetKind.skill
        ? OverrideKind.skill
        : OverrideKind.convention;

/// The kind icon well's glyph color for [kind] — [AionColors.primary] for
/// [OverrideKind.skill], [AionColors.secondary] for
/// [OverrideKind.convention]. The only place [OverrideKind] affects color;
/// everything else in a row is kind-agnostic (design.md §2.4).
Color kindGlyphColor(OverrideKind kind, AionColors colors) =>
    kind == OverrideKind.skill ? colors.primary : colors.secondary;

/// One baseline asset row — its key, a short human-readable descriptor
/// derived from the key, and an "Overridden" chip when a local override
/// is in effect for it.
class _OverrideListRow extends StatelessWidget {
  const _OverrideListRow({
    required this.asset,
    required this.isOverridden,
    required this.onTap,
  });

  final BaselineAsset asset;
  final bool isOverridden;
  final VoidCallback onTap;

  static const _kindGlyphs = {
    OverrideKind.skill: PhosphorIcons.sparkleLight,
    OverrideKind.convention: PhosphorIcons.rulerLight,
  };

  /// A short, readable label derived from [asset]'s key segment (e.g.
  /// `skills/design-sync` → `"design sync"`) — no per-asset copy is
  /// maintained separately, since the key itself is already the primary
  /// identifier shown in the row.
  String _descriptor() {
    final segment = asset.key.split('/').last;
    return segment.replaceAll('-', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: c.surfaceHover,
                border: Border.all(color: c.border, width: 1),
                borderRadius: BorderRadius.all(AionRadius.iconBtnSm),
              ),
              child: SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: PhosphorIcon(
                    _kindGlyphs[overrideKindOf(asset.kind)]!,
                    size: 18,
                    color: kindGlyphColor(overrideKindOf(asset.kind), c),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.key,
                    style: AionText.key.copyWith(
                      fontSize: 13,
                      color: c.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _descriptor(),
                    style: AionText.bodySm.copyWith(
                      fontSize: 12.5,
                      color: c.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isOverridden) ...[
              const SizedBox(width: 10),
              _OverriddenChip(colors: c),
            ],
            const SizedBox(width: 10),
            PhosphorIcon(
              PhosphorIcons.caretRightLight,
              size: 16,
              color: c.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _OverriddenChip extends StatelessWidget {
  const _OverriddenChip({required this.colors});

  final AionColors colors;

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeScope.of(context).isDark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primarySubtle,
        border: Border.all(color: colors.aiBubbleBorder(isDark), width: 1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
              child: const SizedBox(width: 5, height: 5),
            ),
            const SizedBox(width: 5),
            Text(
              context.l10n.overridesListOverriddenChip,
              style: AionText.chip.copyWith(color: colors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
