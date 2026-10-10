import 'package:flutter/foundation.dart';

/// Stage of the one-time legacy import, surfaced to the startup UI.
enum LegacyImportPhase { preparing, copying, verifying }

/// Immutable snapshot of the one-time legacy import progress.
///
/// [totalRows] is 0 while the row counts are still being computed, which the UI
/// renders as an indeterminate bar.
@immutable
class LegacyImportProgress {
  final LegacyImportPhase phase;
  final int copiedRows;
  final int totalRows;

  const new({
    required this.phase,
    required this.copiedRows,
    required this.totalRows,
  });
}

/// Process-wide progress channel between whichever isolate drives the import
/// and the main-isolate UI.
///
/// The import may be owned by any entrypoint (main, analysis, global search,
/// widget), so the UI cannot rely on holding a direct reference to the worker;
/// this notifier is updated from the DB-backed state row instead. `null` means
/// no import is in flight.
final ValueNotifier<LegacyImportProgress?> legacyImportProgress = ValueNotifier(null);
