import 'dart:async';

import 'package:aves/features/collection_paging/stats/collection_stats.dart';
import 'package:aves/features/collection_paging/stats/paged_stats_source.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/covered/location.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/covered/tag.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/rating.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/theme/durations.dart';
import 'package:aves/theme/format.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/theme/styles.dart';
import 'package:aves/theme/themes.dart';
import 'package:aves/utils/file_utils.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/common/action_mixins/feedback.dart';
import 'package:aves/widgets/common/action_mixins/vault_aware.dart';
import 'package:aves/widgets/common/basic/insets.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/basic/tv_edge_focus.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/identity/empty.dart';
import 'package:aves/widgets/dialogs/export_collection_stats_page.dart';
import 'package:aves/widgets/stats/date/histogram.dart';
import 'package:aves/widgets/stats/filter_table.dart';
import 'package:aves/widgets/stats/mime_donut.dart';
import 'package:aves/widgets/stats/percent_text.dart';
import 'package:aves/widgets/stats/top_page.dart';
import 'package:aves/widgets/viewer/controls/notifications.dart';
import 'package:collection/collection.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:provider/provider.dart';

class const StatsPage({
  super.key,
  required final Set<AvesEntry> entries,
  required final CollectionSource source,
  final CollectionLens? parentCollection,
  final PagedStatsSource? pagedStats,
}) extends StatefulWidget {
  static const routeName = '/collection/stats';

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> with FeedbackMixin, VaultAwareMixin {
  final Map<String, int> _entryCountPerCountry = {}, _entryCountPerState = {}, _entryCountPerPlace = {};
  final Map<String, int> _entryCountPerTag = {}, _entryCountPerAlbum = {};
  final Map<int, int> _entryCountPerRating = Map.fromEntries(List.generate(7, (i) => MapEntry(5 - i, 0)));
  late final ValueNotifier<bool> _isPageAnimatingNotifier;
  final ValueNotifier<double?> _pagedProgress = ValueNotifier(null);
  int _totalSizeBytes = 0;
  int _totalDurationMillis = 0;

  /// The streamed aggregate of a windowed scope, null on the in-memory path and
  /// while it loads.
  CollectionStats? _stats;

  Set<AvesEntry> get entries => widget.entries;

  /// Rows the scope holds: the aggregate's total on the paged path, the size of
  /// the in-memory set otherwise.
  int get _entryCount => _stats?.entryCount ?? entries.length;

  @override
  void initState() {
    super.initState();

    _isPageAnimatingNotifier = ValueNotifier(true);
    Future.delayed(ADurations.pageTransitionLoose * timeDilation).then((_) {
      if (!mounted) return;
      _isPageAnimatingNotifier.value = false;
    });

    final pagedStats = widget.pagedStats;
    if (pagedStats != null) {
      // A windowed scope cannot be walked in memory: the numbers are folded from
      // bounded database chunks instead, and the page shows how far it is.
      unawaited(
        pagedStats.load(onProgress: (done, total) {
          _pagedProgress.value = total > 0 ? (done / total).clamp(0.0, 1.0) : null;
        }).then((stats) {
          if (!mounted) return;
          setState(() => _applyPagedStats(stats));
        }, onError: (error, stack) {
          if (!mounted) return;
          showFeedback(context, FeedbackType.warn, context.l10n.genericFailureFeedback);
          setState(() => _applyPagedStats(CollectionStats.empty));
        }),
      );
      return;
    }

    entries.forEach((entry) {
      _totalSizeBytes += entry.sizeBytes ?? 0;
      _totalDurationMillis += entry.durationMillis ?? 0;

      if (entry.hasAddress) {
        final address = entry.addressDetails!;
        var country = address.countryName;
        if (country != null && country.isNotEmpty) {
          country += '${LocationFilter.locationSeparator}${address.countryCode}';
          _entryCountPerCountry[country] = (_entryCountPerCountry[country] ?? 0) + 1;
        }
        var state = address.stateName;
        if (state != null && state.isNotEmpty) {
          state += '${LocationFilter.locationSeparator}${address.stateCode}';
          _entryCountPerState[state] = (_entryCountPerState[state] ?? 0) + 1;
        }
        final place = address.place;
        if (place != null && place.isNotEmpty) {
          _entryCountPerPlace[place] = (_entryCountPerPlace[place] ?? 0) + 1;
        }
      }

      entry.tags.forEach((tag) {
        _entryCountPerTag[tag] = (_entryCountPerTag[tag] ?? 0) + 1;
      });

      final album = entry.directory;
      if (album != null) {
        _entryCountPerAlbum[album] = (_entryCountPerAlbum[album] ?? 0) + 1;
      }

      final rating = entry.rating;
      _entryCountPerRating[rating] = (_entryCountPerRating[rating] ?? 0) + 1;
    });
  }

  /// Copies a streamed aggregate into the fields the page renders, so both paths
  /// feed the same widgets.
  void _applyPagedStats(CollectionStats stats) {
    _stats = stats;
    _totalSizeBytes = stats.totalSizeBytes;
    _totalDurationMillis = stats.totalDurationMillis;
    _entryCountPerCountry.addAll(stats.entryCountPerCountry);
    _entryCountPerState.addAll(stats.entryCountPerState);
    _entryCountPerPlace.addAll(stats.entryCountPerPlace);
    _entryCountPerTag.addAll(stats.entryCountPerTag);
    _entryCountPerAlbum.addAll(stats.entryCountPerAlbum);
    _entryCountPerRating.addAll(stats.entryCountPerRating);
  }

  @override
  void dispose() {
    _isPageAnimatingNotifier.dispose();
    _pagedProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final useTvLayout = settings.useTvLayout;
    return ValueListenableBuilder<bool>(
      valueListenable: _isPageAnimatingNotifier,
      builder: (context, animating, child) {
        final l10n = context.l10n;

        Widget child = const SizedBox();

        if (!animating) {
          final durations = context.watch<DurationsData>();

          if (widget.pagedStats != null && _stats == null) {
            child = _buildPagedProgress(context);
          } else if (_entryCount == 0) {
            child = EmptyContent(
              icon: AIcons.image,
              text: l10n.collectionEmptyImages,
            );
          } else {
            final chartAnimationDuration = context.read<DurationsData>().chartTransition;

            final byMimeTypes = _stats?.entryCountPerMimeType ?? groupBy<AvesEntry, String>(entries, (entry) => entry.mimeType).map<String, int>((k, v) => MapEntry(k, v.length));
            final imagesByMimeTypes = Map.fromEntries(byMimeTypes.entries.where((kv) => kv.key.startsWith('image')));
            final videoByMimeTypes = Map.fromEntries(byMimeTypes.entries.where((kv) => kv.key.startsWith('video')));
            final mimeDonuts = Wrap(
              alignment: .center,
              crossAxisAlignment: .center,
              children: [
                MimeDonut(
                  icon: AIcons.image,
                  byMimeTypes: imagesByMimeTypes,
                  animationDuration: chartAnimationDuration,
                  onFilterSelection: (filter) => _onFilterSelection(context, filter),
                ),
                MimeDonut(
                  icon: AIcons.video,
                  byMimeTypes: videoByMimeTypes,
                  animationDuration: chartAnimationDuration,
                  onFilterSelection: (filter) => _onFilterSelection(context, filter),
                ),
              ],
            );

            final showRatings = _entryCountPerRating.entries.any((kv) => kv.key != 0 && kv.value > 0);
            final source = widget.source;
            child = NotificationListener<SelectFilterNotification>(
              onNotification: (notification) {
                _onFilterSelection(context, notification.filter);
                return true;
              },
              child: AnimationLimiter(
                child: ListView(
                  children: AnimationConfiguration.toStaggeredList(
                    duration: durations.staggeredAnimation,
                    delay: durations.staggeredAnimationDelay * timeDilation,
                    childAnimationBuilder: (child) => SlideAnimation(
                      verticalOffset: 50.0,
                      child: FadeInAnimation(
                        child: child,
                      ),
                    ),
                    children: [
                      const TvEdgeFocus(),
                      mimeDonuts,
                      Histogram(
                        entries: entries,
                        summary: _stats?.histogram,
                        animationDuration: chartAnimationDuration,
                        onFilterSelection: (filter) => _onFilterSelection(context, filter),
                      ),
                      const SizedBox(height: 16),
                      _buildTotalSizeIndicator(context),
                      if (_totalDurationMillis > 0) ...[
                        const SizedBox(height: 16),
                        _buildTotalDurationIndicator(),
                      ],
                      const SizedBox(height: 16),
                      _LocationIndicator(entries: entries, stats: _stats),
                      ..._buildFilterSection<String>(context, l10n.statsTopCountriesSectionTitle, _entryCountPerCountry, (v) => LocationFilter(LocationLevel.country, v)),
                      ..._buildFilterSection<String>(context, l10n.statsTopStatesSectionTitle, _entryCountPerState, (v) => LocationFilter(LocationLevel.state, v)),
                      ..._buildFilterSection<String>(context, l10n.statsTopPlacesSectionTitle, _entryCountPerPlace, (v) => LocationFilter(LocationLevel.place, v)),
                      ..._buildFilterSection<String>(context, l10n.statsTopTagsSectionTitle, _entryCountPerTag, TagFilter.new),
                      ..._buildFilterSection<String>(context, l10n.statsTopAlbumsSectionTitle, _entryCountPerAlbum, (v) => StoredAlbumFilter(v, source.getStoredAlbumDisplayName(context, v))),
                      if (showRatings) ..._buildFilterSection<int>(context, l10n.searchRatingSectionTitle, _entryCountPerRating, RatingFilter.new, sortByCount: false, maxRowCount: null),
                    ],
                  ),
                ),
              ),
            );
          }
        }

        return AvesScaffold(
          appBar: AppBar(
            automaticallyImplyLeading: !useTvLayout,
            title: Text(l10n.statsPageTitle),
            actions: [
              if (!settings.isReadOnly)
                IconButton(
                  icon: const Icon(AIcons.fileExport),
                  onPressed: () => _export(context),
                  tooltip: context.l10n.settingsActionExport,
                ),
            ],
          ),
          body: GestureAreaProtectorStack(
            child: SafeArea(
              bottom: false,
              child: TooltipTheme(
                data: TooltipTheme.of(context).copyWith(
                  preferBelow: false,
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTotalSizeIndicator(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: .min,
        children: [
          const Icon(AIcons.size),
          const SizedBox(width: 16),
          Expanded(
            child: Text(formatFileSize(settings.avesLocale, _totalSizeBytes)),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalDurationIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: .min,
        children: [
          const Icon(AIcons.videoPlay),
          const SizedBox(width: 16),
          Expanded(
            child: Text(formatFriendlyDuration(Duration(milliseconds: _totalDurationMillis))),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFilterSection<T extends Comparable>(
    BuildContext context,
    String title,
    Map<T, int> entryCountMap,
    CollectionFilter Function(T key) filterBuilder, {
    bool sortByCount = true,
    int? maxRowCount = 3,
  }) {
    if (entryCountMap.isEmpty) return [];

    final totalEntryCount = _entryCount;
    final hasMore = maxRowCount != null && entryCountMap.length > maxRowCount;
    final onHeaderPressed = hasMore
        ? () => Navigator.maybeOf(context)?.push(
            MaterialPageRoute(
              settings: const RouteSettings(name: StatsTopPage.routeName),
              builder: (context) => StatsTopPage(
                title: title,
                totalEntryCount: totalEntryCount,
                entryCountMap: entryCountMap,
                filterBuilder: filterBuilder,
                sortByCount: sortByCount,
                onFilterSelection: (filter) => _onFilterSelection(context, filter),
              ),
            ),
          )
        : null;
    Widget header = Text(
      title,
      style: AStyles.sectionTitleStyle(context.knownLocale),
    );
    if (settings.useTvLayout) {
      header = Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisSize: .min,
          children: [
            header,
            const SizedBox(width: 16),
            Icon(AIcons.next, color: hasMore ? null : Theme.of(context).disabledColor),
          ],
        ),
      );
      header = Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: .centerStart,
        // prevent ink response when tapping the header does nothing,
        // because otherwise Play Store reviewers think it is broken navigation
        child: onHeaderPressed != null
            ? InkWell(
                onTap: onHeaderPressed,
                borderRadius: const BorderRadius.all(Radius.circular(123)),
                child: header,
              )
            : Focus(child: header),
      );
    } else {
      header = Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            header,
            const Spacer(),
            IconButton(
              icon: const Icon(AIcons.next),
              onPressed: onHeaderPressed,
              tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
            ),
          ],
        ),
      );
    }

    return [
      header,
      FilterTable(
        totalEntryCount: totalEntryCount,
        entryCountMap: entryCountMap,
        filterBuilder: filterBuilder,
        sortByCount: sortByCount,
        maxRowCount: maxRowCount,
        onFilterSelection: (filter) => _onFilterSelection(context, filter),
      ),
    ];
  }

  Future<void> _onFilterSelection(BuildContext context, CollectionFilter filter) async {
    if (!await unlockFilter(context, filter)) return;

    if (widget.parentCollection != null) {
      _applyToParentCollectionPage(context, filter);
    } else {
      _jumpToCollectionPage(context, filter);
    }
  }

  void _applyToParentCollectionPage(BuildContext context, CollectionFilter filter) {
    widget.parentCollection!.addFilters({filter});
    // We delay closing the current page after applying the filter selection
    // so that hero animation target is ready in the `FilterBar`,
    // even when the target is a child of an `AnimatedList`.
    // Do not use `WidgetsBinding.instance.addPostFrameCallback`,
    // as it may not trigger if there is no subsequent build.
    Future.delayed(const Duration(milliseconds: 100), () => Navigator.maybeOf(context)?.popUntil((route) => route.settings.name == CollectionPage.routeName));
  }

  void _jumpToCollectionPage(BuildContext context, CollectionFilter filter) {
    Navigator.maybeOf(context)?.pushAndRemoveUntil(
      MaterialPageRoute(
        settings: const RouteSettings(name: CollectionPage.routeName),
        builder: (context) => CollectionPage(
          source: widget.source,
          filters: {filter},
        ),
      ),
      (route) => false,
    );
  }

  void _export(BuildContext context) {
    Navigator.maybeOf(context)?.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: ExportCollectionStatsPage.routeName),
        builder: (context) => ExportCollectionStatsPage(entries: entries, pagedSource: widget.pagedStats),
      ),
    );
  }

  /// Progress of a windowed scope's walk: the rows folded so far, so a library
  /// of millions shows how much is left instead of an idle spinner.
  Widget _buildPagedProgress(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: ValueListenableBuilder<double?>(
          valueListenable: _pagedProgress,
          builder: (context, progress, child) {
            if (progress == null) return const CircularProgressIndicator();
            return Column(
              mainAxisSize: .min,
              children: [
                LinearPercentIndicator(
                  percent: progress,
                  lineHeight: 8,
                  animation: false,
                  backgroundColor: Themes.secondLayerColor(context),
                  progressColor: Theme.of(context).colorScheme.primary,
                  barRadius: const Radius.circular(4),
                ),
                const SizedBox(height: 8),
                LinearPercentIndicatorText(percent: progress),
              ],
            );
          },
        ),
      ),
    );
  }
}

class const _LocationIndicator({
  required final Set<AvesEntry> entries,
  final CollectionStats? stats,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Fork: a windowed collection's counts come from its streamed aggregate.
    final entryCount = stats?.entryCount ?? entries.length;
    final withGpsCount = stats?.withGpsCount ?? entries.where((entry) => entry.isCatalogued && entry.hasGps).length;
    final withGpsPercent = entryCount == 0 ? 0.0 : withGpsCount / entryCount;
    final textScaler = MediaQuery.textScalerOf(context);
    final lineHeight = textScaler.scale(16);
    final barRadius = Radius.circular(lineHeight / 2);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            mainAxisSize: .min,
            children: [
              const Icon(AIcons.location),
              Expanded(
                child: Stack(
                  // use a stack instead of `center` field, so that the widgets
                  // are centered even when the center child has larger height
                  alignment: .center,
                  children: [
                    LinearPercentIndicator(
                      percent: withGpsPercent,
                      lineHeight: lineHeight,
                      backgroundColor: Themes.secondLayerColor(context),
                      progressColor: theme.colorScheme.primary,
                      animation: context.select<Settings, bool>((v) => v.animate),
                      isRTL: context.isRtl,
                      barRadius: barRadius,
                      padding: EdgeInsets.symmetric(horizontal: lineHeight),
                    ),
                    LinearPercentIndicatorText(percent: withGpsPercent),
                  ],
                ),
              ),
              // end padding to match leading, so that inside label is aligned with outside label below
              const SizedBox(width: 24),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.statsWithGps(withGpsCount),
            textAlign: .center,
          ),
        ],
      ),
    );
  }
}
