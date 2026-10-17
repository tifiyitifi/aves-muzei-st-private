import 'dart:async';

import 'package:aves/app_flavor.dart';
import 'package:aves/features/collection_paging/engine/collection_engine_router.dart';
import 'package:aves/features/collection_paging/view/paged_widget_candidates.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/sort.dart';
import 'package:aves/model/settings/enums/widget_outline.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/media_store_source.dart';
import 'package:aves/services/common/channel.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/utils/android_file_utils.dart';
import 'package:aves/widgets/home_widget.dart';
import 'package:aves_model/aves_model.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

const _widgetDrawChannel = AvesMethodChannel('deckers.thibault/aves/widget_draw');

void widgetMainCommon(AppFlavor flavor) async {
  debugPrint('Widget main start');
  WidgetsFlutterBinding.ensureInitialized();
  initPlatformServices();
  await settings.init(monitorPlatformSettings: false, shouldSanitize: false);
  await reportService.init();

  debugPrint('Widget channel method handling setup');
  _widgetDrawChannel.setMethodCallHandler((call) async {
    // widget settings may be modified in a different process after channel setup
    await settings.reload();

    switch (call.method) {
      case 'drawWidget':
        return _drawWidget(call.arguments);
      default:
        throw PlatformException(code: 'not-implemented', message: 'failed to handle method=${call.method}');
    }
  });
}

Future<Map<String, Object>> _drawWidget(Object? args) async {
  if (args is! Map) return {};

  final argMap = args.cast<String, Object?>();
  final widgetId = argMap['widgetId'] as int;
  final sizesDip = (argMap['sizesDip'] as List).cast<Map>().map((kv) {
    return Size(kv['widthDip'] as double, kv['heightDip'] as double);
  }).toList();
  final cornerRadiusPx = argMap['cornerRadiusPx'] as double?;
  final devicePixelRatio = argMap['devicePixelRatio'] as double;
  final drawEntryImage = argMap['drawEntryImage'] as bool;
  final reuseEntry = argMap['reuseEntry'] as bool;
  final isSystemThemeDark = argMap['isSystemThemeDark'] as bool;

  await reportService.log('Draw widget with widgetId=$widgetId');

  final brightness = isSystemThemeDark ? Brightness.dark : Brightness.light;
  final outline = await settings.getWidgetOutline(widgetId).color(brightness);

  final entry = drawEntryImage ? await _getWidgetEntry(widgetId, reuseEntry) : null;
  final painter = HomeWidgetPainter(
    entry: entry,
    devicePixelRatio: devicePixelRatio,
  );
  final bytesBySizeDip = <Map<String, Object>>[];
  await Future.forEach(sizesDip, (sizeDip) async {
    final bytes = await painter.drawWidget(
      sizeDip: sizeDip,
      cornerRadiusPx: cornerRadiusPx,
      outline: outline,
      shape: settings.getWidgetShape(widgetId),
    );
    bytesBySizeDip.add({
      'widthDip': sizeDip.width,
      'heightDip': sizeDip.height,
      'bytes': bytes,
    });
  });
  return {
    'bytesBySizeDip': bytesBySizeDip,
    'updateOnTap': settings.getWidgetOpenPage(widgetId) == WidgetOpenPage.updateWidget,
  };
}

Future<AvesEntry?> _getWidgetEntry(int widgetId, bool reuseEntry) async {
  final uri = reuseEntry ? settings.getWidgetUri(widgetId) : null;
  if (uri != null) {
    final entry = await mediaFetchService.getEntry(uri, null);
    if (entry != null) return entry;
  }

  await androidFileUtils.init();

  final filters = settings.getWidgetCollectionFilters(widgetId);

  // A huge collection must not be fully loaded just to pick one entry: when the
  // filters route paged, the entry is read straight from the database mirror.
  final resolution = await PagedWidgetCandidates.resolve(
    filters: filters,
    mostRecent: settings.getWidgetDisplayedItem(widgetId) == .mostRecent,
  );
  if (resolution.handled) {
    final entry = resolution.entry;
    if (entry != null) {
      settings.setWidgetUri(widgetId, entry.uri);
    }
    return entry;
  }

  if (!await const CollectionEngineRouter().allowFullLoad()) {
    // The scope cannot be paged and the library must not be materialized to pick
    // one picture: leave the widget on its placeholder until it can be served.
    return null;
  }

  final source = MediaStoreSource();
  final readyCompleter = Completer();
  source.stateNotifier.addListener(() {
    if (source.isReady) {
      readyCompleter.complete();
    }
  });
  source.canAnalyze = false;
  await source.init(scope: filters);
  await readyCompleter.future;

  final entry = _pickWidgetEntry(widgetId, List.of(CollectionLens(source: source, filters: filters).sortedEntries));
  source.dispose();
  return entry;
}

/// Applies the widget's random / most-recent choice to [entries], remembering
/// the pick so the next refresh can reuse the same file.
AvesEntry? _pickWidgetEntry(int widgetId, List<AvesEntry> entries) {
  switch (settings.getWidgetDisplayedItem(widgetId)) {
    case .random:
      entries.shuffle();
    case .mostRecent:
      entries.sort(AvesEntrySort.compareByDate);
  }
  final entry = entries.firstOrNull;
  if (entry != null) {
    settings.setWidgetUri(widgetId, entry.uri);
  }
  return entry;
}
