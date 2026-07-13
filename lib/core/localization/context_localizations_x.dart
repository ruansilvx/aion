// core/localization/context_localizations_x.dart — BuildContext.l10n extension (core layer).

import 'package:flutter/widgets.dart';

import 'package:aion/l10n/generated/app_localizations.dart';

/// Terse access to the app's localized strings from any [BuildContext].
///
/// [AppLocalizations.delegate] is always registered on the root
/// `WidgetsApp.router` (see `main.dart`), and `l10n.yaml`'s
/// `nullable-getter: false` makes [AppLocalizations.of] itself
/// non-nullable — it asserts rather than returning null if no delegate
/// is found, so there's no null case for callers to handle.
extension AppLocalizationsX on BuildContext {
  /// The localized strings for this context, e.g. `context.l10n.commonSave`.
  AppLocalizations get l10n => AppLocalizations.of(this);
}
