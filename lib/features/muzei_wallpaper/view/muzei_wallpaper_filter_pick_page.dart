import 'package:aves/app_mode.dart';
import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/collection/collection_grid.dart';
import 'package:aves/widgets/common/basic/insets.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/providers/query_provider.dart';
import 'package:aves/widgets/common/providers/selection_provider.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Previews the album (or album union) a wallpaper source would use.
///
/// It is the normal media set grid: tapping a photo does nothing, because a
/// wallpaper is not an item pick. The confirm button is the only way out with a
/// result, so browsing cannot change the wallpaper behind the user's back.
///
/// The lens adds the image MIME restriction locally; the user's "show videos"
/// setting and every other page are untouched.
class MuzeiWallpaperFilterPickPage extends StatefulWidget {
  static const routeName = '/muzei_wallpaper/filters';

  final CollectionSource source;
  final CollectionFilter filter;

  /// Whether [filter] is the union of several albums, which only changes the
  /// confirm label.
  final bool multiple;

  const new({
    super.key,
    required this.source,
    required this.filter,
    required this.multiple,
  });

  @override
  State<MuzeiWallpaperFilterPickPage> createState() => _MuzeiWallpaperFilterPickPageState();
}

class _MuzeiWallpaperFilterPickPageState extends State<MuzeiWallpaperFilterPickPage> {
  /// A picker mode keeps the bottom navigation and the drawer out of the way,
  /// while still letting the grid's own app bar show the source chips.
  final ValueNotifier<AppMode> _appMode = ValueNotifier(.pickFilterInternal);

  late final PagedCollectionLens _collection;

  @override
  void initState() {
    super.initState();
    _collection = PagedCollectionLens(
      source: widget.source,
      filters: {widget.filter, MimeFilter.image},
    );
  }

  @override
  void dispose() {
    _appMode.dispose();
    _collection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableProvider<ValueNotifier<AppMode>>.value(
      value: _appMode,
      child: AvesScaffold(
        body: SelectionProvider<AvesEntry>(
          toSelectableItems: (entry) => entry.toSelectableItems(),
          keyOf: (entry) => entry.id,
          child: QueryProvider(
            startEnabled: settings.getShowTitleQuery(context.currentRouteName!),
            child: GestureAreaProtectorStack(
              child: SafeArea(
                top: false,
                bottom: false,
                child: ChangeNotifierProvider<CollectionLens>.value(
                  value: _collection,
                  child: const CollectionGrid(
                    settingsRouteKey: MuzeiWallpaperFilterPickPage.routeName,
                  ),
                ),
              ),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.of(context).pop(widget.filter),
          icon: const Icon(AIcons.apply),
          label: Text(widget.multiple ? l10n.muzeiWallpaperSourcesUseSelectedAlbums : l10n.muzeiWallpaperSourcesUseAlbum),
        ),
      ),
    );
  }
}
