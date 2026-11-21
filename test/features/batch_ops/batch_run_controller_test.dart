import 'dart:async';

import 'package:aves/features/batch_ops/model/batch_action.dart';
import 'package:aves/features/batch_ops/model/batch_job.dart';
import 'package:aves/features/batch_ops/services/batch_result_recorder.dart';
import 'package:aves/features/batch_ops/services/batch_run_controller.dart';
import 'package:aves/features/batch_ops/services/batch_service.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';

/// The controller is the only place that decides what becomes a result row and
/// what reaches the native job. Both decisions are cheap to get wrong: a video
/// or RAW source would fail every item, and a row for a failed item would offer
/// actions on a file that does not exist.
void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  tearDownAll(() async {
    await tearDownAllServices();
  });

  late _FakeBatchService service;
  late _FakeRecorder recorder;
  late BatchRunController controller;

  setUp(() {
    service = _FakeBatchService();
    recorder = _FakeRecorder();
    controller = BatchRunController(service: service, recorder: recorder);
  });

  tearDown(() async {
    controller.dispose();
    await service.close();
  });

  test('records only items the native side finished', () async {
    await controller.run(entries: {_entry(1, 'IMG_0001.jpg')}, actions: [BatchActions.rotate()]);

    service
      ..emit(const BatchEvent(type: BatchEventType.itemStarted, index: 0, entryId: 1))
      ..emit(const BatchEvent(type: BatchEventType.itemFailed, index: 0, entryId: 1, message: 'boom'))
      ..emit(const BatchEvent(type: BatchEventType.itemDone, index: 0, entryId: 1, uri: 'content://media/10', name: 'IMG_0001.jpg'))
      ..emit(const BatchEvent(type: BatchEventType.jobDone, done: 1, failed: 1));

    await controller.recordsSettled;

    expect(recorder.recorded, hasLength(1));
    expect(recorder.recorded.single.resultUri, 'content://media/10');
    expect(recorder.recorded.single.item.uri, 'content://media/1');
    expect(controller.done, 1);
    expect(controller.failed, 1);
  });

  test('runs only on standard images, skipping videos and RAW', () async {
    final entries = {
      _entry(1, 'IMG_0001.jpg'),
      _entry(2, 'clip.mp4', mimeType: 'video/mp4'),
      _entry(3, 'IMG_0002.dng', mimeType: 'image/dng'),
    };

    await controller.run(entries: entries, actions: [BatchActions.rotate()]);

    expect(service.job, isNotNull);
    expect(service.job!.items, hasLength(1));
    expect(service.job!.items.single.uri, 'content://media/1');
    expect(controller.total, 1);
  });

  test('a failing recorder does not fail the run', () async {
    recorder.failures = 1;
    await controller.run(entries: {_entry(1, 'IMG_0001.jpg')}, actions: [BatchActions.rotate()]);

    service
      ..emit(const BatchEvent(type: BatchEventType.itemDone, index: 0, entryId: 1, uri: 'content://media/10', name: 'IMG_0001.jpg'))
      ..emit(const BatchEvent(type: BatchEventType.jobDone, done: 1));

    await controller.recordsSettled;

    // The file is on disk whatever the table says, so the run still finished.
    expect(recorder.attempts, 1);
    expect(recorder.recorded, isEmpty);
    expect(controller.state, BatchRunState.done);
    expect(controller.error, isNull);
    expect(controller.done, 1);
  });

  test('settled only completes on the terminal event', () async {
    await controller.run(entries: {_entry(1, 'IMG_0001.jpg')}, actions: [BatchActions.rotate()]);
    var settled = false;
    final waiting = controller.settled.then((_) => settled = true);

    // `run` returns before the job does, so anything short of the terminal event
    // must not release a caller that is about to dispose the controller.
    await pumpEventQueue();
    expect(settled, isFalse);

    service.emit(const BatchEvent(type: BatchEventType.jobDone, done: 1));
    await waiting;
    expect(settled, isTrue);
  });

  test('settled completes after a stream error', () async {
    await controller.run(entries: {_entry(1, 'IMG_0001.jpg')}, actions: [BatchActions.rotate()]);

    service.emitError(StateError('channel closed'));

    await controller.settled;
    expect(controller.state, BatchRunState.failed);
    expect(controller.error, contains('channel closed'));
  });

  test('settled completes when nothing can run', () async {
    // A video-only selection never subscribes, so the terminal state has to be
    // reported by the failure path itself.
    await controller.run(entries: {_entry(2, 'clip.mp4', mimeType: 'video/mp4')}, actions: [BatchActions.rotate()]);

    await controller.settled;
    expect(controller.state, BatchRunState.failed);
    expect(controller.error, 'no-image');
  });

  test('waiting for settled still delivers the last record', () async {
    final hold = Completer<void>();
    recorder.hold = hold;
    await controller.run(entries: {_entry(1, 'IMG_0001.jpg')}, actions: [BatchActions.rotate()]);

    service
      ..emit(const BatchEvent(type: BatchEventType.itemDone, index: 0, entryId: 1, uri: 'content://media/10', name: 'IMG_0001.jpg'))
      ..emit(const BatchEvent(type: BatchEventType.jobDone, done: 1));

    // The native side can report the terminal event before the recorder has
    // written the last row: the caller must keep waiting for the queue.
    await controller.settled;
    expect(recorder.recorded, isEmpty);
    hold.complete();
    await controller.recordsSettled;
    expect(recorder.recorded, hasLength(1));
  });
}

AvesEntry _entry(int id, String name, {String mimeType = 'image/jpeg'}) {
  return AvesEntry(
    id: id,
    uri: 'content://media/$id',
    path: '/storage/emulated/0/DCIM/Camera/$name',
    contentId: id,
    pageId: null,
    sourceMimeType: mimeType,
    width: 10,
    height: 20,
    sourceRotationDegrees: 0,
    sizeBytes: 5,
    sourceTitle: name,
    dateAddedSecs: 1,
    dateModifiedMillis: 2,
    sourceDateTakenMillis: 3,
    durationMillis: 0,
    trashed: false,
    origin: EntryOrigins.mediaStoreContent,
  );
}

class _FakeBatchService extends Fake implements BatchService {
  final StreamController<BatchEvent> _events = StreamController<BatchEvent>(sync: true);

  BatchJob? job;

  @override
  Stream<BatchEvent> run(BatchJob job) {
    this.job = job;
    return _events.stream;
  }

  void emit(BatchEvent event) => _events.add(event);

  void emitError(Object error) => _events.addError(error);

  Future<void> close() async {
    // A single-subscription controller only finishes once a listener consumes
    // the done event. A run that never subscribed (no usable image) would leave
    // this future pending forever.
    if (!_events.hasListener) {
      unawaited(_events.close());
      return;
    }
    await _events.close();
  }

  @override
  Future<void> cancel(String jobId) async {}
}

class _FakeRecorder extends Fake implements BatchResultRecorder {
  final List<BatchRecordedItem> recorded = [];

  /// How many of the first attempts must throw, to prove the run survives them.
  int failures = 0;
  int attempts = 0;

  /// Blocks the recorder so a test can observe the queue before it drains.
  Completer<void>? hold;

  @override
  Future<void> record(BatchRecordedItem item) async {
    attempts++;
    if (attempts <= failures) throw StateError('recorder unavailable');
    if (hold != null) await hold!.future;
    recorded.add(item);
  }
}
