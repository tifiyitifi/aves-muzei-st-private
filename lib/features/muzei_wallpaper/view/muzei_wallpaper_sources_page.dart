import 'dart:async';

import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_kind.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_resolution.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_scope.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_controller.dart';
import 'package:aves/features/muzei_wallpaper/view/muzei_wallpaper_filter_pick_page.dart';
import 'package:aves/features/muzei_wallpaper/view/wallpaper_overflow_button.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/collection/filter_bar.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/pick_dialogs/item_pick_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Edits the wallpaper source.
///
/// Mirrors Muzei's Sources screen: a local source is either the user's photos
/// (a collection filter) or a single artwork. A change is applied immediately,
/// exactly like Muzei, because the wallpaper is the user's only preview.
///
/// The page edits the live [WallpaperController] instead of creating a second
/// one: `state.json` has a single Dart writer.
class MuzeiWallpaperSourcesPage extends StatefulWidget {
  static const routeName = '/muzei_wallpaper/sources';

  final WallpaperController controller;

  const new({
    super.key,
    required this.controller,
  });

  @override
  State<MuzeiWallpaperSourcesPage> createState() => _MuzeiWallpaperSourcesPageState();
}

class _MuzeiWallpaperSourcesPageState extends State<MuzeiWallpaperSourcesPage> {
  late WallpaperSourceScope _scope;
  AvesEntry? _singleEntry;
  bool _applying = false;

  WallpaperController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _scope = _controller.prefs.scope;
    unawaited(_loadSingleEntry());
  }

  Future<void> _loadSingleEntry() async {
    final id = _scope.singleEntryId;
    if (id == null) return;
    final entry = await _controller.loadEntry(id);
    if (!mounted || _scope.singleEntryId != id) return;
    setState(() => _singleEntry = entry);
  }

  Future<void> _selectKind(WallpaperSourceKind? kind) async {
    if (kind == null || kind == _scope.kind) return;
    if (_applying || _controller.busy) return;
    if (kind == WallpaperSourceKind.single && _scope.singleEntryId == null) {
      // Choosing the single source means choosing an artwork; do not leave the
      // wallpaper pointing at an unconfigured source.
      await _pickSingle();
      return;
    }
    await _apply(_scope.copyWith(kind: kind));
  }

  Future<void> _pickFilters() async {
    final selection = await Navigator.of(context).push<Set<CollectionFilter>>(
      MaterialPageRoute(
        settings: const RouteSettings(name: MuzeiWallpaperFilterPickPage.routeName),
        fullscreenDialog: true,
        builder: (_) => MuzeiWallpaperFilterPickPage(initialFilters: _scope.filters),
      ),
    );
    if (selection == null || !mounted) return;
    // The image restriction is implicit for wallpapers, so it is not a user
    // filter and must not show up as a removable chip.
    final filters = selection.where((filter) => filter != MimeFilter.image).toSet();
    await _apply(
      _scope.copyWith(
        kind: WallpaperSourceKind.myPhotos,
        filters: filters,
      ),
    );
  }

  Future<void> _pickSingle() async {
    final source = context.read<CollectionSource>();
    final entry = await Navigator.of(context).push<AvesEntry>(
      MaterialPageRoute(
        settings: const RouteSettings(name: ItemPickPage.routeName),
        fullscreenDialog: true,
        builder: (_) => ItemPickPage(
          collection: PagedCollectionLens(
            source: source,
            filters: {MimeFilter.image},
          ),
          canRemoveFilters: false,
        ),
      ),
    );
    if (entry == null || !mounted) return;
    setState(() => _singleEntry = entry);
    await _apply(
      _scope.copyWith(
        kind: WallpaperSourceKind.single,
        singleEntryId: entry.id,
      ),
    );
  }

  Future<void> _apply(WallpaperSourceScope scope) async {
    if (!scope.isConfigured) return;
    setState(() {
      _scope = scope;
      _applying = true;
    });
    try {
      await _controller.setScope(scope);
    } finally {
      if (mounted) {
        setState(() {
          _applying = false;
          _scope = _controller.prefs.scope;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final working = _applying || _controller.busy;
        return AvesScaffold(
          appBar: AppBar(
            title: Text(l10n.muzeiWallpaperSources),
          ),
          body: SafeArea(
            child: ListView(
              children: [
                if (working) const LinearProgressIndicator(),
                RadioGroup<WallpaperSourceKind>(
                  groupValue: _scope.kind,
                  onChanged: (kind) => unawaited(_selectKind(kind)),
                  child: Column(
                    children: [
                      RadioListTile<WallpaperSourceKind>(
                        value: WallpaperSourceKind.myPhotos,
                        title: Text(l10n.muzeiWallpaperSourcesMyPhotos),
                        subtitle: _scope.filters.isEmpty ? Text(l10n.muzeiWallpaperSourcesAllPhotos) : null,
                        secondary: IconButton(
                          tooltip: l10n.muzeiWallpaperSourcesEditFilters,
                          icon: const Icon(AIcons.edit),
                          onPressed: working ? null : _pickFilters,
                        ),
                      ),
                      if (_scope.filters.isNotEmpty)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(bottom: 8),
                          child: FilterBar(
                            filters: _scope.filters,
                            interactive: false,
                          ),
                        ),
                      RadioListTile<WallpaperSourceKind>(
                        value: WallpaperSourceKind.single,
                        title: Text(l10n.muzeiWallpaperSourcesSingle),
                        subtitle: Text(_singleEntry?.bestTitle ?? l10n.muzeiWallpaperSourcesChooseArtwork),
                        secondary: IconButton(
                          tooltip: l10n.muzeiWallpaperSourcesChooseArtwork,
                          icon: const Icon(AIcons.image),
                          onPressed: working ? null : _pickSingle,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    _statusText(context, _controller.resolution),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: WallpaperOverflowFab(
            controller: _controller,
            section: WallpaperSection.sources,
          ),
        );
      },
    );
  }

  String _statusText(BuildContext context, WallpaperSourceResolution? resolution) {
    final l10n = context.l10n;
    return switch (resolution?.status) {
      WallpaperSourceStatus.ready => l10n.muzeiWallpaperSourcesCount(resolution!.total),
      WallpaperSourceStatus.empty => l10n.muzeiWallpaperEmpty,
      WallpaperSourceStatus.unsupported => l10n.muzeiWallpaperUnsupported,
      WallpaperSourceStatus.missing => l10n.muzeiWallpaperMissing,
      null => '',
    };
  }
}
