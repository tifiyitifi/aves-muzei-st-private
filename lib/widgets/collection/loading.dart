import 'dart:async';

import 'package:aves/features/collection_paging/catalog/catalog_progress.dart';
import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/features/collection_paging/lens/paged_import_status.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/source/events.dart';
import 'package:aves/widgets/common/action_mixins/feedback.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/extensions/theme.dart';
import 'package:aves/widgets/common/identity/buttons/outlined_button.dart';
import 'package:aves/widgets/common/identity/empty.dart';
import 'package:material_ui/material_ui.dart';

/// How long a wait may run before it stops reading as ordinary work.
const _longLoadingThreshold = Duration(seconds: 10);

class const LoadingEmptyContent({
  super.key,
  required final CollectionSource source,

  /// The view being resolved, when the caller has one. It reports the step it is
  /// on and the count it has read, which is what turns a bare spinner into
  /// something the user can actually read.
  final CollectionLens? collection,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final itemCountFormatter = settings.avesLocale.decimalNumberFormat();
    final progressTextStyle = TextStyle(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .5),
      fontSize: 18,
    );

    return EmptyContent(
      text: context.l10n.sourceStateLoading,
      bottom: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          mainAxisSize: .min,
          children: [
            Stack(
              alignment: .center,
              children: [
                const ReportProgressIndicator(),
                ValueListenableBuilder<ProgressEvent>(
                  valueListenable: source.progressNotifier,
                  builder: (context, progress, snapshot) {
                    final done = progress.done;
                    return done > 0
                        ? Text(
                            itemCountFormatter.format(done),
                            style: progressTextStyle,
                          )
                        : const SizedBox();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            _LoadingStatus(
              source: source,
              collection: collection,
            ),
          ],
        ),
      ),
    );
  }
}

/// What a waiting view is doing, and for how long.
///
/// The spinner cannot say either: this line is the difference between "the app
/// is working" and "the app is frozen", which is what a bare progress indicator
/// earns. The elapsed time is always there, the resolve's own step and count are
/// added when the view knows them.
class _LoadingStatus extends StatefulWidget {
  final CollectionSource source;
  final CollectionLens? collection;

  const new({
    required this.source,
    this.collection,
  });

  @override
  State<_LoadingStatus> createState() => _LoadingStatusState();
}

class _LoadingStatusState extends State<_LoadingStatus> {
  /// Seconds this body has been showing.
  ///
  /// Counted by the ticker rather than read off the clock: it measures the wait
  /// the user is looking at, and it is what the body reports.
  int _elapsedSeconds = 0;

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // One tick a second: the elapsed time must move, or it reads as frozen too.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final collection = widget.collection;
    final lens = collection is PagedCollectionLens ? collection : null;
    final elapsed = Duration(seconds: _elapsedSeconds);
    // A long wait with nothing countable behind it is the case worth escalating:
    // an import or a catalog sweep reports its own figures and needs no button.
    final measurable = pagedImportStatus.active || catalogProgressNotifier.value != null;
    final stuck = elapsed >= _longLoadingThreshold && !measurable;

    final phase = lens?.resolvePhase;
    final headline = stuck
        ? l10n.collectionLoadingLong
        : phase == null
        ? null
        : _phaseLabel(l10n, phase);
    final knownTotal = widget.source.progressNotifier.value.total > 0 ? widget.source.progressNotifier.value.total : lens?.resolvingTotal ?? 0;

    final subtle = TextStyle(color: theme.isDark ? Colors.white30 : Colors.black26);
    return Column(
      mainAxisSize: .min,
      children: [
        if (headline != null || (knownTotal > 0 && !stuck)) ...[
          Text.rich(
            TextSpan(
              children: [
                if (headline != null) TextSpan(text: headline),
                if (knownTotal > 0 && !stuck) ...[
                  if (headline != null) const TextSpan(text: ' · '),
                  TextSpan(text: l10n.itemCount(knownTotal), style: subtle),
                ],
              ],
            ),
            style: theme.textTheme.bodySmall!.copyWith(fontFeatures: const [FontFeature.disable('smcp')]),
            softWrap: false,
            overflow: .fade,
            maxLines: 1,
            textAlign: .center,
          ),
          const SizedBox(height: 4),
        ],
        // The clock has a line of its own: it is the one figure that is always
        // there, and a bare `00:00` needs no label to be understood.
        Text(
          _formatElapsed(elapsed),
          style: theme.textTheme.bodySmall!.copyWith(color: subtle.color, fontFeatures: const [FontFeature.tabularFigures()]),
          textAlign: .center,
        ),
        // The escape hatch: a wait this long with nothing moving is not going to
        // end by itself, and the view can always be asked to resolve again.
        if (stuck && lens != null) ...[
          const SizedBox(height: 12),
          AvesOutlinedButton(
            label: l10n.collectionLoadingRetry,
            onPressed: lens.refresh,
          ),
        ],
      ],
    );
  }

  /// `00:00`, and `1:02:03` past an hour.
  ///
  /// A clock rather than a sentence: it needs no translation, and its figures stay
  /// tabular so the line does not jitter as the seconds change.
  String _formatElapsed(Duration elapsed) {
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final minutes = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final hours = elapsed.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  String _phaseLabel(AppLocalizations l10n, PagedResolvePhase phase) {
    switch (phase) {
      case PagedResolvePhase.syncing:
        return l10n.collectionLoadingPhaseSyncing;
      case PagedResolvePhase.counting:
        return l10n.collectionLoadingPhaseCounting;
      case PagedResolvePhase.headers:
        return l10n.collectionLoadingPhaseHeaders;
      case PagedResolvePhase.firstWindow:
        return l10n.collectionLoadingPhaseFirstWindow;
    }
  }
}
