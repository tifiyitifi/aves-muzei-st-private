import 'dart:ffi' show DynamicLibrary;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

/// Host-side sqlite3 loading for Drift / sqflite-ffi tests.
///
/// `flutter test` runs on the dev host WITHOUT the platform-plugin bundling
/// step, so `sqlite3_flutter_libs` never supplies its library here (it only
/// lands in the app build output, which is why the APP itself works).
///
/// Resolution order:
///  1. default dynamic-library resolution (PATH / working directory);
///  2. `AVES_SQLITE3_DLL` environment variable (explicit override);
///  3. auto-discovery inside `<projectRoot>/build/**` — any bundled sqlite3.
///
/// Fails loudly when nothing resolves, so DB-backed tests never silently skip.
void ensureSqlite3Loaded() {
  if (!Platform.isWindows) return;
  try {
    DynamicLibrary.open('sqlite3.dll');
    return;
  } catch (_) {
    // fall through to discovery
  }

  final configured = Platform.environment['AVES_SQLITE3_DLL'];
  if (configured != null && configured.isNotEmpty && File(configured).existsSync()) {
    open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(configured));
    return;
  }

  final discovered = _discoverInBuildOutput();
  if (discovered != null) {
    open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(discovered));
    return;
  }

  fail(
    'sqlite3.dll not resolvable on this host. Set AVES_SQLITE3_DLL to an '
    'absolute path of one, or run a desktop build so build/** contains it.',
  );
}

String? _discoverInBuildOutput() {
  final root = Directory('build');
  if (!root.existsSync()) return null;
  try {
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is File && entity.uri.pathSegments.last.toLowerCase() == 'sqlite3.dll') {
        return entity.path;
      }
    }
  } on FileSystemException {
    return null;
  }
  return null;
}
