import 'dart:async';

import 'package:aves/features/batch_ops/model/batch_action.dart';
import 'package:aves/features/batch_ops/model/batch_job.dart';
import 'package:aves/features/batch_ops/services/batch_result_recorder.dart';
import 'package:aves/features/batch_ops/services/batch_run_controller.dart';
import 'package:aves/features/batch_ops/services/batch_service.dart';
import 'package:aves/features/batch_ops/view/batch_progress_dialog.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../common.dart';

/// A progress dialog that lets the system back gesture pop it while the native
/// job is still writing leaves the caller with no listener for `itemDone`: the
/// files exist but no result row can offer to replace or move them back.
void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  tearDownAll(() async {
    await tearDownAllServices();
  });

  late _FakeBatchService service;
  late BatchRunController controller;

  setUp(() async {
    service = _FakeBatchService();
    controller = BatchRunController(service: service, recorder: _FakeRecorder());
    await controller.run(entries: {_entry()}, actions: [BatchActions.rotate()]);
  });

  tearDown(() async {
    controller.dispose();
    await service.close();
  });

  Widget wrap() => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: BatchProgressDialog(controller: controller)),
  );

  testWidgets('blocks system back until the job is done', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);

    service.emit(const BatchEvent(type: BatchEventType.jobDone, done: 1));
    await tester.pumpAndSettle();

    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);
  });
}

AvesEntry _entry() => AvesEntry(
  id: 1,
  uri: 'content://media/1',
  path: '/storage/emulated/0/DCIM/Camera/1.jpg',
  contentId: 1,
  pageId: null,
  sourceMimeType: 'image/jpeg',
  width: 10,
  height: 20,
  sourceRotationDegrees: 0,
  sizeBytes: 5,
  sourceTitle: '1',
  dateAddedSecs: 1,
  dateModifiedMillis: 2,
  sourceDateTakenMillis: 3,
  durationMillis: 0,
  trashed: false,
  origin: EntryOrigins.mediaStoreContent,
);

class _FakeBatchService extends Fake implements BatchService {
  final StreamController<BatchEvent> _events = StreamController<BatchEvent>(sync: true);

  @override
  Stream<BatchEvent> run(BatchJob job) => _events.stream;

  void emit(BatchEvent event) => _events.add(event);

  Future<void> close() => _events.close();
}

class _FakeRecorder extends Fake implements BatchResultRecorder {
  @override
  Future<void> record(BatchRecordedItem item) async {}
}
