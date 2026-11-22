import 'dart:async';

/// Coalesces rapid draft edits into one count request and drops stale answers.
///
/// Counting goes through SQL and can outlast the user's next edit: without the
/// token, a slow reply would overwrite the number of the newer draft. The token
/// moves on every [schedule], so a reply for an older draft is discarded even
/// before the next request starts.
class CountDebouncer {
  final Duration delay;
  final Future<int?> Function() count;
  final void Function(int?) onResult;
  final bool Function() isAlive;

  Timer? _timer;
  int _token = 0;
  bool _disposed = false;

  new({
    required this.delay,
    required this.count,
    required this.onResult,
    required this.isAlive,
  });

  /// Requests one count after the edits settle for [delay].
  void schedule() {
    if (_disposed) return;
    _timer?.cancel();
    final token = ++_token;
    _timer = Timer(delay, () => _run(token));
  }

  Future<void> _run(int token) async {
    final value = await count();
    if (_disposed || token != _token || !isAlive()) return;
    onResult(value);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
