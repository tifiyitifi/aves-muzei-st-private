import 'dart:async';

import 'package:aves/app_mode.dart';
import 'package:aves/features/collection_paging/lens/paged_viewer_copy.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/identity/empty.dart';
import 'package:aves/widgets/settings/viewer/slideshow_page.dart';
import 'package:aves/widgets/viewer/controls/controller.dart';
import 'package:aves/widgets/viewer/entry_viewer_stack.dart';
import 'package:aves/widgets/viewer/providers.dart';
import 'package:aves_magnifier/aves_magnifier.dart';
import 'package:aves_model/aves_model.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class SlideshowPage extends StatefulWidget {
  static const routeName = '/collection/slideshow';

  final CollectionLens collection;

  const new({
    super.key,
    required this.collection,
  });

  @override
  State<SlideshowPage> createState() => _SlideshowPageState();
}

class _SlideshowPageState extends State<SlideshowPage> {
  final ValueNotifier<AppMode> _appModeNotifier = ValueNotifier(.slideshow);
  late ViewerController _viewerController;
  late CollectionLens _slideshowCollection;
  AvesEntry? _initialEntry;
  bool _opening = true;

  CollectionSource get source => widget.collection.source;

  @override
  void initState() {
    super.initState();
    _initViewerController(autopilot: true);
    unawaited(_openSlideshowCollection());
  }

  @override
  void dispose() {
    _appModeNotifier.dispose();
    _disposeViewerController();
    final collection = _slideshowCollection;
    if (collection is PagedViewerCopy) collection.dispose();
    super.dispose();
  }

  Future<void> _openSlideshowCollection() async {
    await _initSlideshowCollection();
    if (!mounted) return;
    setState(() {
      _opening = false;
      _initialEntry = _slideshowCollection.sortedEntries.firstOrNull;
    });
  }

  @override
  Widget build(BuildContext context) {
    final initialEntry = _initialEntry;
    return ListenableProvider<ValueNotifier<AppMode>>.value(
      value: _appModeNotifier,
      child: AvesScaffold(
        body: initialEntry == null
            ? (_opening
                ? const SizedBox()
                : EmptyContent(
                    icon: AIcons.image,
                    text: context.l10n.collectionEmptyImages,
                    alignment: .center,
                  ))
            : MultiProvider(
                providers: [
                  ViewStateConductorProvider(),
                  VideoConductorProvider(),
                  MultiPageConductorProvider(),
                ],
                child: NotificationListener<SlideshowActionNotification>(
                  onNotification: (notification) {
                    _onActionSelected(notification.action);
                    return true;
                  },
                  child: EntryViewerStack(
                    key: ValueKey(_viewerController),
                    collection: _slideshowCollection,
                    initialEntry: initialEntry,
                    viewerController: _viewerController,
                  ),
                ),
              ),
      ),
    );
  }

  void _initViewerController({required bool autopilot}) {
    _viewerController = ViewerController(
      initialScale: ScaleLevel(ref: settings.slideshowFillScreen ? ScaleReference.covered : ScaleReference.contained),
      transition: settings.slideshowTransition,
      repeat: settings.slideshowRepeat,
      autopilot: autopilot,
      autopilotInterval: Duration(seconds: settings.slideshowInterval),
      autopilotAnimatedZoom: settings.slideshowAnimatedZoomEffect,
    );
  }

  void _disposeViewerController() => _viewerController.dispose();

  Future<void> _initSlideshowCollection() async {
    final previous = _slideshowCollection;
    if (previous is PagedViewerCopy) previous.dispose();

    final base = widget.collection;
    final skipVideos = settings.slideshowVideoPlayback == SlideshowVideoPlayback.skip;
    if (base is PagedViewerCopy && !skipVideos) {
      // Paged: a seeded permutation over the whole collection, one window fetch
      // per position, instead of materializing (and shuffling) the loaded
      // neighbourhood. Skipping videos is left to the legacy pool below, which
      // is bounded and can filter on each entry's mime.
      final copy = PagedViewerCopy(
        parent: base.parent,
        shuffleSeed: settings.slideshowShuffle ? DateTime.now().millisecondsSinceEpoch : null,
      );
      // Resolve the first playable row so the viewer opens on a real entry.
      await copy.prefetchAround(0);
      _slideshowCollection = copy;
      return;
    }

    // a paged viewer copy cannot be materialized (every miss would kick a
    // window), so the slideshow loops the loaded neighbourhood instead
    final pool = base is PagedViewerCopy ? base.loadedEntries : base.sortedEntries;
    var entries = List.of(pool);
    if (skipVideos) {
      entries = entries.where((entry) => !MimeFilter.video.test(entry)).toList();
    }
    if (settings.slideshowShuffle) {
      entries.shuffle();
    }
    _slideshowCollection = CollectionLens(
      source: source,
      listenToSource: false,
      fixedSort: true,
      fixedSelection: entries,
    );
  }

  void _onActionSelected(SlideshowAction action) {
    switch (action) {
      case .resume:
        _viewerController.autopilot = true;
      case .showInCollection:
        _showInCollection();
      case .cast:
        // ignore, as it should be handled at the viewer level
        break;
      case .settings:
        _showSettings(context);
    }
  }

  void _showInCollection() {
    final currentEntry = _viewerController.entryNotifier.value;
    if (currentEntry == null) return;

    final album = currentEntry.directory;
    final uri = currentEntry.uri;

    Navigator.maybeOf(context)?.pushAndRemoveUntil(
      MaterialPageRoute(
        settings: const RouteSettings(name: CollectionPage.routeName),
        builder: (context) => CollectionPage(
          source: source,
          filters: album != null ? {StoredAlbumFilter(album, source.getStoredAlbumDisplayName(context, album))} : null,
          highlightTest: (entry) => entry.uri == uri,
        ),
      ),
      (route) => false,
    );
  }

  (bool, bool) get collectionSettings => (settings.slideshowShuffle, settings.slideshowVideoPlayback == SlideshowVideoPlayback.skip);

  Future<void> _showSettings(BuildContext context) async {
    final oldCollectionSettings = collectionSettings;
    final currentEntry = _viewerController.entryNotifier.value;

    await Navigator.maybeOf(context)?.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: ViewerSlideshowPage.routeName),
        builder: (context) => const ViewerSlideshowPage(),
      ),
    );

    _disposeViewerController();
    _initViewerController(autopilot: false);
    if (oldCollectionSettings != collectionSettings) {
      await _initSlideshowCollection();
    }
    final slideshowEntries = _slideshowCollection.sortedEntries;
    _initialEntry = slideshowEntries.contains(currentEntry) ? currentEntry : slideshowEntries.firstOrNull;
    setState(() {});
  }
}

class SlideshowActionNotification extends Notification {
  final SlideshowAction action;

  new(this.action);
}
