// core/utils/platform_utils.dart — Platform detection helpers (core layer).

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

/// Whether the app is running on a desktop OS (macOS, Windows, or Linux).
/// Used to gate desktop-only navigation destinations (full agentic coding).
bool get isDesktop =>
    !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

/// Whether the app is running on a mobile OS (iOS or Android).
bool get isMobile => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

/// Whether the app is running as a web build.
bool get isWeb => kIsWeb;
