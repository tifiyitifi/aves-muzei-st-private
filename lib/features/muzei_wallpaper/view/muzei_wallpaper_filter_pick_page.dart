import 'dart:async';

import 'package:aves/app_mode.dart';
import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/services/intent_service.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/collection/collection_grid.dart';
import 'package:aves/widgets/collection/filter_bar.dart';
import 'package:aves/widgets/common/basic/insets.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/providers/query_provider.dart';
import 'package:aves/widgets/common/providers/selection_provider.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Picks the collection filters that become the wallpaper source.
///
/// This is the gallery the user already knows: the same grid, the same filter
/// chips, the same filter picker. The only addition is the confirm button, and
/// nothing is applied until it is pressed, so experimenting with filters cannot
/// change the wallpaper behind the user's back.
class MuzeiWallpaperFilterPickPage extends StatefulWidget {
  static const routeName = '/muzei_wallpaper/filters';

  final Set<CollectionFilter> initialFilters;

  const new({
    super.key,
    required this.initialFilters,
  });

  @override
  State<MuzeiWallpaperFilterPickPage> createState() => _MuzeiWallpaperFilterPickPageState();
}

class _MuzeiWallpaperFilterPickPageState extends State<MuzeiWallpaperFilterPickPage> {
  /// Filter picking is a first-class mode: it enables the filter chips and keeps
  /// the view from turning into a media picker.
  final ValueNotifier<AppMode> _appMode = ValueNotifier(.pickFilterInternal);

  late Set<CollectionFilter> _filters;
  PagedCollectionLens? _collection;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _filters = {...widget.initialFilters};
    _collection = _createLens();
  }

  @override
  void dispose() {
    _appMode.dispose();
    _collection?.dispose();
    super.dispose();
  }

  PagedCollectionLens _createLens() {
    return PagedCollectionLens(
      source: context.read<CollectionSource>(),
      // Wallpapers are stills, so the image restriction is implicit and cannot
      // be removed from the chip bar.
      filters: {..._filters, MimeFilter.image},
    );
  }

  void _applyFilters(Set<CollectionFilter> filters) {
    final previous = _collection;
    setState(() {
      _filters = filters;
      _collection = _createLens();
    });
    // Let the grid finish building with the new lens before the old one is
    // disposed, otherwise its listeners are removed mid-build.
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  Future<void> _editFilters() async {
    final selection = await IntentService.pickCollectionFilters(_filters);
    if (!mounted || selection == null) return;
    _applyFilters(selection.where((filter) => filter != MimeFilter.image).toSet());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final collection = _collection;
    return ListenableProvider<ValueNotifier<AppMode>>.value(
      value: _appMode,
      child: AvesScaffold(
        appBar: AppBar(
          title: Text(l10n.muzeiWallpaperFilterPickTitle),
          actions: [
            IconButton(
              tooltip: l10n.muzeiWallpaperSourcesEditFilters,
              icon: const Icon(AIcons.edit),
              onPressed: () => unawaited(_editFilters()),
            ),
          ],
        ),
        body: SelectionProvider<AvesEntry>(
          toSelectableItems: (entry) => entry.toSelectableItems(),
          keyOf: (entry) => entry.id,
          child: QueryProvider(
            startEnabled: false,
            child: GestureAreaProtectorStack(
              child: SafeArea(
                top: false,
                bottom: false,
                child: Column(
                  children: [
                    if (_filters.isNotEmpty)
                      FilterBar(
                        filters: _filters,
                        interactive: false,
                      ),
                    Expanded(
                      child: collection == null
                          ? const SizedBox()
                          : ChangeNotifierProvider<CollectionLens>.value(
                              key: ObjectKey(collection),
                              value: collection,
                              child: const CollectionGrid(
                                settingsRouteKey: MuzeiWallpaperFilterPickPage.routeName,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.of(context).pop(_filters),
          icon: const Icon(AIcons.checked),
          label: Text(l10n.muzeiWallpaperFilterPickConfirm),
        ),
      ),
    );
  }
}
