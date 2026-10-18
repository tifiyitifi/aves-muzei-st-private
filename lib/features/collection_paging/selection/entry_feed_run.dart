import 'dart:async';

import 'package:aves/features/collection_paging/selection/entry_feed.dart';
import 'package:aves/features/collection_paging/selection/selection_mark.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/widgets/common/action_mixins/feedback.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// One entry-set action run over a feed.
///
/// The legacy action code is written for one materialized set: one dialog, one
/// report overlay, one summary. A whole-view feed cannot be one set, so the run
/// drives that *same* code once per batch and hoists everything the user sees:
/// the overlay is shown once for the whole run, a dialog is answered once, and
/// the per-batch feedback is folded into one summary.
///
/// It is installed in a [Zone] around the run, so the legacy code reaches it
/// without a parameter and cannot leak outside.
class EntryFeedRun {
  static const _zoneKey = #avesEntryFeedRun;

  /// The run the current zone belongs to, if any.
  static EntryFeedRun? get current => Zone.current[_zoneKey] as EntryFeedRun?;

  /// Installs [run] for the duration of [body], so the legacy action code reaches
  /// it without a parameter and it cannot leak outside.
  static Future<T> install<T>(EntryFeedRun run, Future<T> Function() body) => runZoned(body, zoneValues: {_zoneKey: run});

  final EntryFeed feed;

  final _opController = StreamController<Object?>.broadcast();
  final _decisions = <String, Object?>{};
  final _feedbacks = <FeedbackType, ({String message, SnackBarAction? action})>{};

  /// The entries the legacy code is working on right now.
  List<AvesEntry> batch = const [];

  bool aborted = false;

  /// Whether a batch changed the source in a way the view must reload for.
  ///
  /// A run updates the source batch by batch; reloading the view (counts,
  /// headers, summaries) per batch would repeat a heavy re-resolve thousands of
  /// times, so the run coalesces them into one reload when it ends.
  bool needsViewRefresh = false;

  int _successCount = 0;
  int _appliedCount = 0;
  VoidCallback? _cancelCurrentOp;

  new(this.feed);

  Stream<Object?> get opStream => _opController.stream;

  /// Whether the run's overlay has subscribed yet.
  ///
  /// A broadcast stream drops what it emits with no listener, so the first batch
  /// must not report before the overlay has mounted.
  bool get hasReportListener => _opController.hasListener;

  /// The count a message must show: the whole run, not one batch.
  ///
  /// The legacy code reports per batch, so its last summary would name the last
  /// batch's size; scaling the count makes it name the run's own.
  static int displayCount(int batchCount) => current?.feed.count ?? batchCount;

  /// The successes the run has accumulated.
  ///
  /// The last batch's summary must count every batch, not just its own, so each
  /// batch reports the running total.
  static int displaySuccessCount(int batchSuccessCount) {
    final run = current;
    if (run == null) return batchSuccessCount;
    return run._successCount += batchSuccessCount;
  }

  /// The ops that actually changed something, accumulated over the run.
  ///
  /// Distinct from [displaySuccessCount] because the legacy summaries name the
  /// moved/edited count in one branch and the total successes in the other.
  static int displayAppliedCount(int batchAppliedCount) {
    final run = current;
    if (run == null) return batchAppliedCount;
    return run._appliedCount += batchAppliedCount;
  }

  /// The answer of a dialog that must be asked once per run: its first answer is
  /// replayed for every later batch.
  ///
  /// A null answer (the user cancelled) stops the whole run.
  static Future<T?> decide<T>(String key, Future<T?> Function() ask) async {
    final run = current;
    if (run == null) return ask();
    if (run._decisions.containsKey(key)) return run._decisions[key] as T?;
    final answer = await ask();
    run._decisions[key] = answer;
    if (answer == null) run.aborted = true;
    return answer;
  }

  /// The answer of a confirmation that must be asked once per run; a declined one
  /// stops the whole run.
  static Future<bool> confirm(String key, Future<bool> Function() ask) async {
    final run = current;
    if (run == null) return ask();
    final decided = run._decisions[key];
    if (decided != null) return decided as bool;
    final answer = await ask();
    run._decisions[key] = answer;
    if (!answer) run.aborted = true;
    return answer;
  }

  /// Shows a one-shot notice once per run: later batches stay silent.
  static Future<void> once(String key, Future<void> Function() show) async {
    final run = current;
    if (run == null) return show();
    if (run._decisions.containsKey(key)) return;
    run._decisions[key] = true;
    await show();
  }

  /// Starts a batch: the legacy code's target lookup now resolves to it.
  void beginBatch(List<AvesEntry> entries) => batch = entries;

  /// Pumps one batch's op stream into the run's single overlay.
  ///
  /// The batch's own `onDone` still runs, so the source is updated per batch,
  /// exactly as the legacy code did for the whole set.
  Future<void> forward<T>({
    required Stream<T> opStream,
    VoidCallback? onCancel,
    Future<void> Function(Set<T> processed)? onDone,
  }) async {
    _cancelCurrentOp = onCancel;
    final processed = <T>{};
    await for (final event in opStream) {
      if (aborted) break;
      processed.add(event);
      _opController.add(event);
    }
    await onDone?.call(processed);
  }

  /// Folds one batch's feedback into the run's single summary.
  ///
  /// The action rides along: after a huge move the user must still be able to
  /// jump to what moved.
  void recordFeedback(FeedbackType type, String message, [SnackBarAction? action]) => _feedbacks[type] = (message: message, action: action);

  /// The one summary the run shows, a failure winning over a success.
  ({FeedbackType type, String message, SnackBarAction? action})? get summary {
    final warn = _feedbacks[FeedbackType.warn];
    if (warn != null) return (type: FeedbackType.warn, message: warn.message, action: warn.action);
    final info = _feedbacks[FeedbackType.info];
    if (info != null) return (type: FeedbackType.info, message: info.message, action: info.action);
    return null;
  }

  void cancel() {
    aborted = true;
    _cancelCurrentOp?.call();
  }
}

/// Runs an entry-set action over the feed the current selection resolves to.
///
/// A materialized feed (the legacy selection, a small view) runs [body] once, so
/// the legacy path keeps its exact behaviour. A declared feed runs it per batch
/// and hoists the interaction: one overlay, one answer per dialog, one summary,
/// which the caller shows.
///
/// Set [wholeView] for an action that covers the view itself rather than a
/// selection (emptying the bin).
Future<({FeedbackType type, String message, SnackBarAction? action})?> runOverFeed(
  BuildContext context,
  Future<void> Function() body, {
  bool wholeView = false,
}) async {
  final collection = context.read<CollectionLens>();
  final selection = context.read<Selection<AvesEntry>>();
  final feed = entryFeedFor(collection, selection, wholeView: wholeView);
  if (!feed.declared) {
    await body();
    return null;
  }

  final run = EntryFeedRun(feed);
  final source = context.read<CollectionSource>();
  ({FeedbackType type, String message, SnackBarAction? action})? summary;

  await EntryFeedRun.install(
    run,
    () async {
      final reportDone = Completer<void>();
      unawaited(
        showAvesDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => ReportOverlay<Object?>(
            opStream: run.opStream,
            itemCount: feed.count,
            onCancel: run.cancel,
            onDone: (_) {
              Navigator.maybeOf(context)?.pop();
              if (!reportDone.isCompleted) reportDone.complete();
            },
          ),
          routeSettings: const RouteSettings(name: ReportOverlay.routeName),
        ),
      );
      // Wait for the overlay to mount before the first batch reports, so its
      // progress is not silently dropped.
      for (var i = 0; i < 200 && !run.hasReportListener; i++) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
      try {
        await for (final batch in feed.batches()) {
          if (run.aborted) break;
          run.beginBatch(batch);
          await body();
          // The legacy code resumes monitoring at the end of every batch; hold it
          // paused for the whole run so the source cannot re-scan mid-action.
          if (!run.aborted) source.pauseMonitoring();
        }
      } finally {
        source.resumeMonitoring();
        summary = run.summary;
        await run._opController.close();
      }
      // The overlay pops itself when the stream closes; a route that never mounted
      // must not hang the run.
      await reportDone.future.timeout(const Duration(seconds: 30), onTimeout: () {});
    },
  );
  // Outside the run: the view reload must not be suppressed by it, and a mark
  // must follow the rows the action removed.
  if (run.needsViewRefresh) collection.refresh();
  final mark = selection.mark;
  if (mark is CollectionSelectionMark) await mark.recount();
  return summary;
}
