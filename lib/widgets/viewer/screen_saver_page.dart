import 'dart:async';

import 'package:aves/features/collection_paging/view/paged_slideshow.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/identity/empty.dart';
import 'package:aves/widgets/viewer/controls/controller.dart';
import 'package:aves/widgets/viewer/entry_viewer_stack.dart';
import 'package:aves/widgets/viewer/providers.dart';
import 'package:aves_magnifier/aves_magnifier.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class ScreenSaverPage extends StatefulWidget {
  static const routeName = '/screen_saver';

  final CollectionSource source;

  const new({
    super.key,
    required this.source,
  });

  @override
  State<ScreenSaverPage> createState() => _ScreenSaverPageState();
}

class _ScreenSaverPageState extends State<ScreenSaverPage> with WidgetsBindingObserver {
  late final ViewerController _viewerController;
  CollectionLens? _slideshowCollection;
  PagedSlideshowSession? _pagedSession;
  bool _opening = false;

  CollectionSource get source => widget.source;

  @override
  void initState() {
    super.initState();
    _viewerController = ViewerController(
      initialScale: ScaleLevel(ref: settings.screenSaverFillScreen ? ScaleReference.covered : ScaleReference.contained),
      transition: settings.screenSaverTransition,
      repeat: true,
      autopilot: true,
      autopilotInterval: Duration(seconds: settings.screenSaverInterval),
      autopilotAnimatedZoom: settings.screenSaverAnimatedZoomEffect,
    );
    source.stateNotifier.addListener(_onSourceStateChanged);
    unawaited(_initSlideshowCollection());
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    source.stateNotifier.removeListener(_onSourceStateChanged);
    _viewerController.dispose();
    _pagedSession?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == .resumed) {
      _viewerController.autopilot = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    final collection = _slideshowCollection;
    if (collection == null) {
      child = const SizedBox();
    } else {
      final entries = collection.sortedEntries;
      if (entries.isEmpty) {
        child = EmptyContent(
          icon: AIcons.image,
          text: context.l10n.collectionEmptyImages,
          alignment: .center,
        );
      } else {
        child = MultiProvider(
          providers: [
            ViewStateConductorProvider(),
            VideoConductorProvider(),
            MultiPageConductorProvider(),
          ],
          child: EntryViewerStack(
            collection: collection,
            initialEntry: entries.first,
            viewerController: _viewerController,
          ),
        );
      }
    }

    return AvesScaffold(
      body: child,
    );
  }

  void _onSourceStateChanged() {
    if (_slideshowCollection == null && !_opening) {
      unawaited(_initSlideshowCollection());
    }
  }

  Future<void> _initSlideshowCollection() async {
    if (!source.isReady || _slideshowCollection != null || _opening) return;
    _opening = true;
    try {
      // A paged scope plays a window-backed shuffled permutation instead of
      // materializing (and shuffling) every entry.
      final session = await PagedSlideshow.open(
        source: source,
        filters: settings.screenSaverCollectionFilters,
        skipVideos: settings.screenSaverVideoPlayback == SlideshowVideoPlayback.skip,
      );
      if (!mounted) {
        session?.dispose();
        return;
      }
      if (session != null) {
        _pagedSession = session;
        // Resolve the first playable row before the viewer opens.
        await session.ready();
        if (!mounted) {
          session.dispose();
          return;
        }
        _slideshowCollection = session.collection;
      } else {
        _slideshowCollection = _legacySlideshowCollection();
      }
      setState(() {});
    } finally {
      _opening = false;
    }
  }

  /// Legacy slideshow collection: a shuffled snapshot of the scope's entries.
  CollectionLens _legacySlideshowCollection() {
    final originalCollection = CollectionLens(
      source: source,
      filters: settings.screenSaverCollectionFilters,
    );
    var entries = List.of(originalCollection.sortedEntries);
    if (settings.screenSaverVideoPlayback == SlideshowVideoPlayback.skip) {
      entries = entries.where((entry) => !MimeFilter.video.test(entry)).toList();
    }
    entries.shuffle();
    return CollectionLens(
      source: originalCollection.source,
      listenToSource: false,
      fixedSort: true,
      fixedSelection: entries,
    );
  }
}
