import 'dart:async';

import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/logging/log.dart';

const _log = AreaKeyLog(collectionPagingLogKey);

/// How long a media store step may take before a resolve gives up on it.
///
/// A platform call has no deadline of its own. Right after an engine restart its
/// reply can be lost — the native side then logs `FlutterJNI was detached ...
/// Could not send` — and the await would never complete: the view would sit on
/// its loading body forever with nothing running. Bounding the call turns that
/// into a missed step, which the next refresh retries.
const platformStepTimeout = Duration(seconds: 5);

/// Runs a media store step under [timeout], reporting a failure instead of
/// throwing it.
///
/// These steps are best-effort: the database can still answer for the rows it
/// holds, so a MediaStore hiccup must not refuse the whole view.
Future<T?> withPlatformTimeout<T>(
  Future<T> Function() call, {
  required String label,
  Duration timeout = platformStepTimeout,
}) async {
  try {
    return await call().timeout(timeout);
  } on TimeoutException catch (error, stack) {
    _log.w('$label did not answer within ${timeout.inMilliseconds}ms', error, stack);
    return null;
  } catch (error, stack) {
    _log.w('$label failed', error, stack);
    return null;
  }
}
