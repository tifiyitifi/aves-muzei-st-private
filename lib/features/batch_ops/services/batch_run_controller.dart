import 'dart:async';

import 'package:aves/features/batch_ops/log.dart';
import 'package:aves/features/batch_ops/model/batch_action.dart';
import 'package:aves/features/batch_ops/model/batch_job.dart';
import 'package:aves/features/batch_ops/services/batch_service.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter/foundation.dart';

enum BatchRunState { idle, running, done, cancelled, failed }

/// Drives one batch job and exposes its progress to the UI.
///
/// The native side already isolates items, so the controller only mirrors the
/// counts and the last output. Cancellation is forwarded to the native job; the
/// items already written stay written.
class BatchRunController extends ChangeNotifier {
  final BatchService _service;

  new([this._service = const BatchService()]);

  BatchRunState _state = BatchRunState.idle;
  String? _jobId;
  StreamSubscription<BatchEvent>? _subscription;
  int _total = 0;
  int _done = 0;
  int _failed = 0;
  String? _lastOutputUri;
  String? _error;

  BatchRunState get state => _state;
  int get total => _total;
  int get done => _done;
  int get failed => _failed;
  String? get lastOutputUri => _lastOutputUri;
  String? get error => _error;
  bool get isRunning => _state == BatchRunState.running;

  Future<void> run({
    required Iterable<AvesEntry> entries,
    required List<BatchAction> actions,
    BatchOutput output = const BatchOutput(),
  }) async {
    if (isRunning) return;

    final images = entries.where((entry) => entry.isImage && !entry.isRaw).toList();
    if (images.isEmpty) {
      _state = BatchRunState.failed;
      _error = 'no-image';
      notifyListeners();
      return;
    }

    _jobId = DateTime.now().microsecondsSinceEpoch.toString();
    final items = images.map((entry) {
      final path = entry.path;
      final displayName = path != null && path.isNotEmpty ? pContext.basename(path) : (entry.bestTitle ?? 'image');
      return BatchItem(entryId: entry.id, uri: entry.uri, displayName: displayName, mimeType: entry.mimeType);
    }).toList();
    final job = BatchJob(jobId: _jobId!, items: items, actions: actions, output: output);

    _total = items.length;
    _done = 0;
    _failed = 0;
    _lastOutputUri = null;
    _error = null;
    _state = BatchRunState.running;
    notifyListeners();

    _subscription = _service.run(job).listen(
      _onEvent,
      onError: (Object error, StackTrace stack) {
        batchLog.e('batch job ${job.jobId} failed', error, stack);
        _error = error.toString();
        _finish(BatchRunState.failed);
      },
      onDone: () {
        if (_state == BatchRunState.running) _finish(BatchRunState.done);
      },
      cancelOnError: true,
    );
  }

  void cancel() {
    final jobId = _jobId;
    if (jobId != null && isRunning) {
      unawaited(_service.cancel(jobId));
    }
  }

  void _onEvent(BatchEvent event) {
    switch (event.type) {
      case BatchEventType.jobStarted:
        _total = event.itemCount ?? _total;
      case BatchEventType.itemStarted:
      case BatchEventType.itemProgress:
        break;
      case BatchEventType.itemDone:
        _done++;
        _lastOutputUri = event.uri ?? _lastOutputUri;
      case BatchEventType.itemFailed:
        _failed++;
        batchLog.w('batch item ${event.index} failed: ${event.message}');
      case BatchEventType.jobDone:
        _done = event.done ?? _done;
        _failed = event.failed ?? _failed;
        _finish(event.cancelled ? BatchRunState.cancelled : BatchRunState.done);
        return;
    }
    notifyListeners();
  }

  void _finish(BatchRunState state) {
    if (_state != BatchRunState.running) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
