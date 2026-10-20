import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/features/logging/log_level.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<({String key, LogLevel level, Object? message})> records;

  setUp(() {
    records = [];
    Log.reset();
    Log.setSink((key, level, message, error, stackTrace) => records.add((key: key, level: level, message: message)));
  });

  group('gating', () {
    test('emits nothing while a channel stays closed', () {
      Log.emit(LogKeys.db, LogLevel.error, 'boom');
      expect(records, isEmpty);
    });

    test('setEnabled(true) opens a channel for every level', () {
      Log.setEnabled(LogKeys.db, true);
      Log.emit(LogKeys.db, LogLevel.verbose, 'v');
      expect(records, hasLength(1));
      expect(records.single.key, LogKeys.db);
      expect(records.single.level, LogLevel.verbose);
    });

    test('setEnabled(false) closes a channel again', () {
      Log.setEnabled(LogKeys.db, true);
      Log.setEnabled(LogKeys.db, false);
      Log.emit(LogKeys.db, LogLevel.error, 'boom');
      expect(records, isEmpty);
    });

    test('setLevel raises the gate', () {
      Log.setLevel(LogKeys.media, LogLevel.warning);
      Log.emit(LogKeys.media, LogLevel.info, 'info');
      Log.emit(LogKeys.media, LogLevel.warning, 'warn');
      expect(records.map((r) => r.message), ['warn']);
    });

    test('a parent gate applies to child channels', () {
      Log.setLevel(LogKeys.db, LogLevel.verbose);
      Log.emit('${LogKeys.db}.catalog', LogLevel.verbose, 'child');
      expect(records, hasLength(1));
      expect(records.single.key, '${LogKeys.db}.catalog');
    });

    test('a child gate overrides its parent', () {
      Log.setLevel(LogKeys.db, LogLevel.warning);
      Log.setLevel('${LogKeys.db}.catalog', LogLevel.verbose);
      Log.emit('${LogKeys.db}.catalog', LogLevel.verbose, 'child');
      Log.emit('${LogKeys.db}.entries', LogLevel.verbose, 'sibling');
      expect(records.map((r) => r.message), ['child']);
    });

    test('only() closes every other channel', () {
      Log.setEnabled(LogKeys.app, true);
      Log.setEnabled(LogKeys.db, true);
      Log.only([LogKeys.db]);
      Log.emit(LogKeys.app, LogLevel.error, 'app');
      Log.emit(LogKeys.db, LogLevel.error, 'db');
      expect(records.map((r) => r.message), ['db']);
    });

    test('isEnabled reports the gate without emitting', () {
      expect(Log.isEnabled(LogKeys.db, LogLevel.error), isFalse);
      Log.setEnabled(LogKeys.db, true);
      expect(Log.isEnabled(LogKeys.db, LogLevel.error), isTrue);
      expect(records, isEmpty);
    });

    test('never reports the off sentinel as enabled, even on an open channel', () {
      Log.setEnabled(LogKeys.db, true);
      expect(Log.isEnabled(LogKeys.db, LogLevel.off), isFalse);
      Log.emit(LogKeys.db, LogLevel.off, 'sentinel must not pass');
      expect(records, isEmpty);
    });

    test('a closed channel does not leak the off sentinel to the sink', () {
      Log.setLevel(LogKeys.db, LogLevel.off);
      Log.emit(LogKeys.db, LogLevel.off, 'sentinel must not pass');
      expect(records, isEmpty);
    });
  });

  group('sink', () {
    test('forwards message, error and stack trace', () {
      final error = StateError('x');
      final stackTrace = StackTrace.current;
      Object? seenError;
      StackTrace? seenStackTrace;
      Log.setSink((key, level, message, err, st) {
        seenError = err;
        seenStackTrace = st;
      });
      Log.setEnabled(LogKeys.app, true);
      Log.emit(LogKeys.app, LogLevel.error, 'failed', error, stackTrace);
      expect(seenError, same(error));
      expect(seenStackTrace, same(stackTrace));
    });
  });

  group('AreaKeyLog', () {
    test('routes to its channel and level', () {
      const log = AreaKeyLog(LogKeys.app);
      Log.setEnabled(LogKeys.app, true);
      log.i('info');
      log.e('error');
      expect(records.map((r) => r.key), [LogKeys.app, LogKeys.app]);
      expect(records.map((r) => r.level), [LogLevel.info, LogLevel.error]);
    });
  });

  group('parseKeys', () {
    test('splits on commas, trimming blanks', () {
      expect(Log.parseKeys(' a , b ,, c '), ['a', 'b', 'c']);
    });

    test('returns empty for blank input', () {
      expect(Log.parseKeys(''), isEmpty);
      expect(Log.parseKeys(' , '), isEmpty);
    });
  });

  group('applyDefaults', () {
    test('opens every channel in debug', () {
      Log.applyDefaults(debug: true);
      expect(Log.isEnabled(LogKeys.app, LogLevel.verbose), isTrue);
      expect(Log.isEnabled(LogKeys.db, LogLevel.error), isTrue);
      expect(Log.isEnabled(LogKeys.settings, LogLevel.verbose), isTrue);
      expect(Log.isEnabled(LogKeys.media, LogLevel.verbose), isTrue);
    });

    test('opens nothing in release', () {
      Log.applyDefaults(debug: false);
      expect(Log.isEnabled(LogKeys.app, LogLevel.error), isFalse);
      expect(Log.isEnabled(LogKeys.db, LogLevel.error), isFalse);
    });

    test('a feature channel can be opened by the composition root', () {
      // Feature-owned channels are declared in their own slices and passed to
      // init, so adding one never means editing the shared registry.
      const featureKey = 'log.collection_paging';
      Log.init(debugChannels: const [featureKey]);
      expect(Log.isEnabled(featureKey, LogLevel.verbose), kDebugMode);

      // Release builds only surface warnings, exactly like the shared channels.
      if (!kDebugMode) expect(Log.isEnabled(featureKey, LogLevel.warning), isFalse);
    });
  });
}
