import 'dart:developer' as dev;

import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/features/logging/log_level.dart';
import 'package:flutter/foundation.dart';

/// Receives an emitted record.
///
/// [key] is the channel name (see [LogKeys]) and [level] is a real severity
/// (never [LogLevel.off]). The sink is the single seam between the app and the
/// backing log transport, so swapping `dart:developer` for another backend
/// never touches call sites.
typedef LogSink = void Function(String key, LogLevel level, Object? message, Object? error, StackTrace? stackTrace);

/// Fork logging facade.
///
/// ## Gating
/// A record is emitted only when its channel is open **and** the record's level
/// reaches the channel's gate. Channels are hierarchical keys
/// (`log.<domain>.<sub>`); a gate on a parent applies to every child that does
/// not define its own. In debug builds [LogKeys.app] is open by default;
/// `--dart-define=AVES_LOG_KEYS=a,b` opens more channels in any build mode.
/// Release builds open nothing by default, and an opened channel only surfaces
/// [LogLevel.warning]/[LogLevel.error].
///
/// ## Runtime control
/// ```dart
/// Log.setEnabled(LogKeys.db, true);            // open one channel
/// Log.setLevel(LogKeys.db, LogLevel.warning);  // raise one channel's gate
/// Log.only([LogKeys.db]);                      // close everything else
/// ```
///
/// Records are forwarded to `dart:developer`, so Logcat / DevTools keep working
/// and each line is tagged with its channel (e.g. `[log.db] message`).
abstract final class Log {
  static LogSink _sink = _devSink;

  /// Channel key -> gate. An absent key means [LogLevel.off].
  static final Map<String, LogLevel> _gates = <String, LogLevel>{};

  /// Attaches [sink] (defaults to `dart:developer`) and applies the build-mode
  /// defaults. Call once from the composition root.
  static void init({LogSink? sink}) {
    _sink = sink ?? _devSink;
    _gates.clear();
    applyDefaults(debug: kDebugMode);
  }

  /// Opens [key] ([LogLevel.verbose] in debug, [LogLevel.warning] otherwise) or
  /// closes it ([LogLevel.off]).
  static void setEnabled(String key, bool enabled) {
    _gates[key] = enabled ? (kDebugMode ? LogLevel.verbose : LogLevel.warning) : LogLevel.off;
  }

  /// Sets [key]'s gate directly.
  static void setLevel(String key, LogLevel level) {
    _gates[key] = level;
  }

  /// Closes every channel except [keys].
  static void only(Iterable<String> keys) {
    _gates.clear();
    for (final key in keys) {
      setEnabled(key, true);
    }
  }

  /// Whether a [level] record on [key] would be emitted. Use it to guard
  /// expensive message construction.
  static bool isEnabled(String key, LogLevel level) => level.severity >= _gateFor(key).severity;

  /// Emits a record if [key] / [level] pass the gate.
  static void emit(String key, LogLevel level, Object? message, [Object? error, StackTrace? stackTrace]) {
    if (!isEnabled(key, level)) return;
    _sink(key, level, message, error, stackTrace);
  }

  /// Effective gate: the longest configured prefix of [key], else [LogLevel.off].
  static LogLevel _gateFor(String key) {
    var gate = LogLevel.off;
    var matchLength = -1;
    for (final entry in _gates.entries) {
      final prefix = entry.key;
      final matches = key == prefix || key.startsWith('$prefix.');
      if (matches && prefix.length > matchLength) {
        gate = entry.value;
        matchLength = prefix.length;
      }
    }
    return gate;
  }

  /// Applies the default gates for a build mode; `--dart-define` channels are
  /// opened last so they win.
  @visibleForTesting
  static void applyDefaults({required bool debug}) {
    if (debug) {
      setLevel(LogKeys.app, LogLevel.verbose);
    }
    final opened = debug ? LogLevel.verbose : LogLevel.warning;
    for (final key in parseKeys(const String.fromEnvironment('AVES_LOG_KEYS'))) {
      _gates[key] = opened;
    }
  }

  /// Splits a comma-separated `--dart-define` value, trimming blanks.
  @visibleForTesting
  static List<String> parseKeys(String raw) => raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(growable: false);

  @visibleForTesting
  static void setSink(LogSink sink) => _sink = sink;

  @visibleForTesting
  static void reset() {
    _sink = _devSink;
    _gates.clear();
  }

  static void _devSink(String key, LogLevel level, Object? message, Object? error, StackTrace? stackTrace) {
    dev.log(
      message?.toString() ?? '',
      name: key,
      level: level.severity,
      error: error,
      stackTrace: stackTrace,
    );
  }
}

/// Per-area logger bound to one channel [key].
///
/// Declare one per file/module and call the leveled methods without repeating
/// the key:
/// ```dart
/// const log = AreaKeyLog(LogKeys.app);
/// log.i('viewer opened');
/// log.e('failed to open', error, stackTrace);
/// ```
class AreaKeyLog {
  const new(this.key);

  /// The channel this logger emits to (see [LogKeys]).
  final String key;

  void v(Object? message, [Object? error, StackTrace? stackTrace]) => Log.emit(key, LogLevel.verbose, message, error, stackTrace);

  void d(Object? message, [Object? error, StackTrace? stackTrace]) => Log.emit(key, LogLevel.debug, message, error, stackTrace);

  void i(Object? message, [Object? error, StackTrace? stackTrace]) => Log.emit(key, LogLevel.info, message, error, stackTrace);

  void w(Object? message, [Object? error, StackTrace? stackTrace]) => Log.emit(key, LogLevel.warning, message, error, stackTrace);

  void e(Object? message, [Object? error, StackTrace? stackTrace]) => Log.emit(key, LogLevel.error, message, error, stackTrace);

  /// Emits at an arbitrary [level].
  void log(LogLevel level, Object? message, [Object? error, StackTrace? stackTrace]) => Log.emit(key, level, message, error, stackTrace);
}
