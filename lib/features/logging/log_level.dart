/// Severity of a log record, ordered from least to most severe.
///
/// The numeric [severity] mirrors the levels understood by `dart:developer` /
/// DevTools (`FINE`, `INFO`, `WARNING`, `SEVERE`), so a sink can forward
/// records without the rest of the app depending on any logging package.
/// [off] is the gate sentinel meaning "channel disabled"; it is never emitted.
enum LogLevel {
  verbose(300),
  debug(500),
  info(800),
  warning(900),
  error(1000),
  off(2000);

  new(this.severity);

  /// Numeric level forwarded to the sink (see `dart:developer` `log`).
  final int severity;
}
