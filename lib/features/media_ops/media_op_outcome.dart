import 'package:aves/features/media_ops/engine/media_op_prefs.dart';
import 'package:aves/services/common/image_op_events.dart';

/// Permission outcomes the native pipeline reports on a move event.
abstract final class MediaOpPermission {
  /// The system write request was approved; later operations can update the
  /// Media Store directly.
  static const String granted = 'granted';

  /// The user refused the system write request. Retrying on the next operation
  /// would ask again for something already answered, so this is remembered.
  static const String denied = 'denied';

  /// No request could be made (prompts disabled, no Activity, API too old for a
  /// bulk request, or too many items). Nothing to remember.
  static const String unavailable = 'unavailable';
}

/// Records what a finished move/rename operation learned about permissions.
///
/// Called from every action that consumes [MoveOpEvent]s, so the decision lives
/// here instead of being duplicated at the call sites. It only reacts to a
/// denial: granting access is already reflected by the operation succeeding,
/// and the OS can revoke it on its own.
Future<void> recordMediaOpOutcome(Iterable<MoveOpEvent> processed, {MediaOpPrefs? prefs}) async {
  final denied = processed.any((event) => event.permission == MediaOpPermission.denied);
  if (denied) {
    await (prefs ?? mediaOpPrefs).denyPermissionPrompt();
  }
}
