import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

bool get isDesktop =>
    !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

bool get isMobile => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

bool get isWeb => kIsWeb;
