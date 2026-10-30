import 'dart:async';
import 'dart:isolate';

import 'package:aves/app_flavor.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_engine.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/live_wallpaper_refill/log.dart';
import 'package:aves/features/live_wallpaper_refill/refill_entry.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/features/muzei_wallpaper/log.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/wallpaper_lock/log.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/widgets/aves_app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:leak_tracker/leak_tracker.dart';
import 'package:material_ui/material_ui.dart';

void mainCommon(AppFlavor flavor, {Map<String, Object?>? debugIntentData}) {
  debugProfilePlatformChannels = false;

  Log.init(
    debugChannels: [
      ...collectionPagingDebugLogKeys,
      ...muzeiWallpaperDebugLogKeys,
      ...visibleRangeDebugLogKeys,
      ...groupedWallpaperDebugLogKeys,
      ...liveWallpaperRefillDebugLogKeys,
      ...wallpaperLockDebugLogKeys,
    ],
  );
  const appLog = AreaKeyLog(LogKeys.app);
  appLog.i('app start flavor=${flavor.name}');

  //  HttpClient.enableTimelineLogging = true; // enable network traffic logging
  //  debugPrintGestureArenaDiagnostics = true;

  initPlatformServices();

  Isolate.current.addErrorListener(
    RawReceivePort((pair) {
      final errorAndStacktrace = pair as List;
      final error = errorAndStacktrace[0] as String;
      final stackTraceString = errorAndStacktrace[1] as String?;
      final stackTrace = stackTraceString != null ? StackTrace.fromString(stackTraceString) : null;
      reportService.recordError(error, stackTrace);
    }).sendPort,
  );

  // Errors during the widget build phase will show by default:
  // - in debug mode: error on red background
  // - in profile/release mode: plain grey background
  // This can be modified via `ErrorWidget.builder`
  // ErrorWidget.builder = (details) => ErrorWidget(details.exception);
  // cf https://docs.flutter.dev/testing/errors

  LeakTracking.start();
  FlutterMemoryAllocations.instance.addListener(
    (event) => LeakTracking.dispatchObjectEvent(event.toMap()),
  );
  runApp(AvesApp(flavor: flavor, debugIntentData: debugIntentData));
  // The callback handle is part of the AOT snapshot, so it changes with every
  // build: refresh it on each launch, not just when the wallpaper page is
  // opened, or a background refill after an update would fail.
  unawaited(registerLiveWallpaperRefillCallback());
  // The grouped wallpaper service asks for a frame when it starts, so the engine
  // has to be listening even if the wallpaper page is never opened. The request
  // is what refreshes a stale frame after a reboot or a process restart, and it
  // runs without the `isActive` guard because the picker may not have committed
  // the switch yet.
  unawaited(groupedWallpaperEngine.attach());
}
