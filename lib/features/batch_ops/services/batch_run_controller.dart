import 'dart:async';

import 'package:aves/features/batch_ops/log.dart';
import 'package:aves/features/batch_ops/model/batch_action.dart';
import 'package:aves/features/batch_ops/model/batch_job.dart';
import 'package:aves/features/batch_ops/services/batch_result_recorder.dart';
import 'package:aves/features/batch_ops/services/batch_service.dart';
import 'package:aves/features/batch_ops/services/batch_results_service.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter/foundation.dart';

enum BatchRunState { idle, running, done, cancelled, failed }

/// Drives one batch job and exposes its progress to the UI.
///
/// The native side already isolates items, so the controller only mirrors the
/// counts and the last output. Cancellation is forwarded to the native job; the
/// items already written stay written. Every finished item is handed to a
/// [BatchResultRecorder], which is what makes the result actionable later.
class BatchRunController extends ChangeNotifier {
  final BatchService service;
  final BatchResultRecorder recorder;

  new({this.service = const BatchService(), this.recorder = batchResultsService});

  BatchRunState _state = BatchRunState.idle;
  String? _jobId;
  StreamSubscription<BatchEvent>? _subscription;
  int _total = 0;
  int _done = 0;
  int _failed = 0;
  String? _lastOutputUri;
  String? _error;

  List<BatchItem> _items = const [];
  List<BatchAction> _actions = const [];
  BatchOutput _output = const BatchOutput();
  Future<void> _recordQueue = Future.value();

  BatchRunState get state => _state;
  int get total => _total;
  int get done => _done;
  int get failed => _failed;
  String? get lastOutputUri => _lastOutputUri;
  String? get error => _error;
  bool get isRunning => _state == BatchRunState.running;

  /// Completes when every finished item has been handed to the recorder.
  ///
  /// The native job can report `jobDone` before the last record is written, so a
  /// caller that navigates to the results page must await this first.
  Future<void> get recordsSettled => _recordQueue;

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
    _actions = actions;
    _output = output;
    _items = images.map((entry) {
      final path = entry.path;
      final displayName = path != null && path.isNotEmpty ? pContext.basename(path) : (entry.bestTitle ?? 'image');
      return BatchItem(entryId: entry.id, uri: entry.uri, displayName: displayName, mimeType: entry.mimeType);
    }).toList(growable: false);
    final job = BatchJob(jobId: _jobId!, items: _items, actions: actions, output: output);

    _total = _items.length;
    _done = 0;
    _failed = 0;
    _lastOutputUri = null;
    _error = null;
    _state = BatchRunState.running;
    notifyListeners();

    _subscription = service.run(job).listen(
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
      unawaited(service.cancel(jobId));
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
        _enqueueRecord(event);
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

  /// Queues one record, keeping the table in item order and off the event loop.
  void _enqueueRecord(BatchEvent event) {
    final jobId = _jobId;
    final index = event.index;
    final uri = event.uri;
    if (jobId == null || index == null || uri == null || index < 0 || index >= _items.length) return;

    final recorded = BatchRecordedItem(
      jobId: jobId,
      index: index,
      item: _items[index],
      actions: _actions,
      resultUri: uri,
      resultPath: event.path,
      resultName: event.name,
      resultSize: event.size,
      resultMimeType: event.mimeType,
      outputRelativePath: _output.relativePath,
    );
    _recordQueue = _recordQueue.then((_) => _record(recorded));
  }

  Future<void> _record(BatchRecordedItem recorded) async {
    try {
      await recorder.record(recorded);
    } catch (error, stack) {
      // A failed record must never fail the run: the file exists either way.
      batchLog.w('failed to record batch result ${recorded.resultUri}', error, stack);
    }
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
