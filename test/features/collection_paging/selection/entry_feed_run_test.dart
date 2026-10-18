import 'package:aves/features/collection_paging/selection/entry_feed.dart';
import 'package:aves/features/collection_paging/selection/entry_feed_run.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/widgets/common/action_mixins/feedback.dart';
import 'package:flutter_test/flutter_test.dart';

/// One entry-set action run over a feed: the legacy code runs per batch, while
/// the dialogs, the report and the summary stay once-only.
void main() {
  AvesEntry entry(int id) => AvesEntry(
        id: id,
        uri: 'content://$id',
        path: '/album/$id.jpg',
        contentId: 100 + id,
        pageId: null,
        sourceMimeType: 'image/jpeg',
        width: 10,
        height: 20,
        sourceRotationDegrees: 0,
        sizeBytes: 5,
        sourceTitle: 'title$id',
        dateAddedSecs: 1,
        dateModifiedMillis: 2,
        sourceDateTakenMillis: 0,
        durationMillis: 0,
        trashed: false,
        origin: EntryOrigins.mediaStoreContent,
      );

  EntryFeed feed(int count) => MaterializedEntryFeed([for (var i = 1; i <= count; i++) entry(i)]);

  test('a dialog is answered once and its answer replayed', () async {
    final run = EntryFeedRun(feed(600));
    var asked = 0;

    await EntryFeedRun.install(run, () async {
      expect(await EntryFeedRun.decide('destination', () async => 'album${++asked}'), 'album1');
      expect(await EntryFeedRun.decide('destination', () async => 'album${++asked}'), 'album1');
      expect(await EntryFeedRun.confirm('danger', () async => true), isTrue);
      expect(await EntryFeedRun.confirm('danger', () async => false), isTrue);
    });

    expect(asked, 1);
    expect(run.aborted, isFalse);
  });

  test('a cancelled dialog stops the run', () async {
    final run = EntryFeedRun(feed(600));

    await EntryFeedRun.install(run, () async {
      expect(await EntryFeedRun.decide<String>('destination', () async => null), isNull);
      expect(await EntryFeedRun.confirm('danger', () async => false), isFalse);
    });

    expect(run.aborted, isTrue);
  });

  test('a one-shot notice is shown once per run', () async {
    final run = EntryFeedRun(feed(600));
    var shown = 0;

    await EntryFeedRun.install(run, () async {
      await EntryFeedRun.once('unsupported', () async => shown++);
      await EntryFeedRun.once('unsupported', () async => shown++);
    });

    expect(shown, 1);
  });

  test('a run scales the counts its messages show to the whole feed', () async {
    final run = EntryFeedRun(feed(600));

    await EntryFeedRun.install(run, () async {
      // The legacy code reports one batch; the summary must name the run.
      expect(EntryFeedRun.displayCount(256), 600);
      expect(EntryFeedRun.displaySuccessCount(250), 250);
      expect(EntryFeedRun.displaySuccessCount(250), 500);
      expect(EntryFeedRun.displayAppliedCount(200), 200);
      expect(EntryFeedRun.displayAppliedCount(150), 350);
    });
  });

  test('outside a run the counts stay the batch counts', () {
    expect(EntryFeedRun.displayCount(42), 42);
    expect(EntryFeedRun.displaySuccessCount(42), 42);
    expect(EntryFeedRun.displayAppliedCount(42), 42);
    expect(EntryFeedRun.current, isNull);
  });

  test('a run folds its batches into one summary, a failure winning', () async {
    final run = EntryFeedRun(feed(600));
    expect(run.summary, isNull);

    run.recordFeedback(FeedbackType.info, 'moved 256');
    expect(run.summary?.type, FeedbackType.info);
    expect(run.summary?.message, 'moved 256');

    run.recordFeedback(FeedbackType.warn, 'moved 600');
    expect(run.summary?.type, FeedbackType.warn);
    expect(run.summary?.message, 'moved 600');
  });

  test('forward pumps a batch into the run and still runs its own onDone', () async {
    final run = EntryFeedRun(feed(600));
    final reported = <int>[];
    var done = <int>{};

    await EntryFeedRun.install(run, () async {
      run.opStream.listen((event) => reported.add(event! as int));
      await run.forward<int>(
        opStream: Stream.fromIterable([1, 2, 3]),
        onDone: (processed) async => done = processed,
      );
      await pumpEventQueue();
    });

    // The batch's own `onDone` still runs, so the source is updated per batch.
    expect(done, {1, 2, 3});
    // And its events reach the run's single overlay.
    expect(reported, [1, 2, 3]);
  });
}
