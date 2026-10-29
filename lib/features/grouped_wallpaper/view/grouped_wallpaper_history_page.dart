import 'dart:async';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/grouped_wallpaper/db/grouped_wallpaper_history_store.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_history_entry.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_history_limit.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_labels.dart';
import 'package:aves/features/grouped_wallpaper/view/widgets/grouped_wallpaper_history_limit_dialog.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/theme/format.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/thumbnail/image.dart';
import 'package:aves/widgets/viewer/entry_viewer_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// The photos the grouped wallpaper has shown, newest first.
///
/// It reads the history table directly instead of going through the engine: the
/// rows outlive a stopped wallpaper, and the page must work while the service is
/// not running. Rows whose photo left the library are skipped, so a deleted photo
/// does not leave an empty tile behind.
class GroupedWallpaperHistoryPage extends StatefulWidget {
  static const routeName = '/grouped_wallpaper/history';

  const new({super.key});

  @override
  State<GroupedWallpaperHistoryPage> createState() => _GroupedWallpaperHistoryPageState();
}

enum _HistoryAction {
  clear,
  limit,
}

typedef _HistoryItem = ({GroupedWallpaperHistoryEntry row, AvesEntry entry});

class _GroupedWallpaperHistoryPageState extends State<GroupedWallpaperHistoryPage> {
  AppDatabase? _db;
  List<_HistoryItem> _items = const [];
  int _rowCount = 0;
  int _limit = GroupedWallpaperHistoryLimit.defaultLimit;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<AppDatabase> _openDb() async => _db ??= await getIt<AppDatabaseProvider>().open();

  Future<void> _load() async {
    try {
      final db = await _openDb();
      final rows = await GroupedWallpaperHistoryStore(db).load();
      final limit = await WallpaperGroupStore(db).readHistoryLimit();
      if (!mounted) return;
      // The source owns the entries the library actually has, so a row pointing
      // at a photo that is gone simply disappears from the list.
      final source = context.read<CollectionSource>();
      final items = <_HistoryItem>[];
      for (final row in rows) {
        final entry = source.getEntryById(row.entryId);
        if (entry != null) items.add((row: row, entry: entry));
      }
      setState(() {
        _items = items;
        _rowCount = rows.length;
        _limit = limit;
        _loaded = true;
      });
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to load the wallpaper history', error, stack);
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  Future<void> _onAction(_HistoryAction action) async {
    switch (action) {
      case _HistoryAction.clear:
        await _clear();
      case _HistoryAction.limit:
        await _editLimit();
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(context.l10n.wallpaperGroupHistoryClearConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(MaterialLocalizations.of(context).okButtonLabel)),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await GroupedWallpaperHistoryStore(await _openDb()).clear();
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to clear the wallpaper history', error, stack);
    }
    if (!mounted) return;
    await _load();
  }

  Future<void> _editLimit() async {
    final value = await showGroupedWallpaperHistoryLimitDialog(context, limit: _limit);
    if (value == null || !mounted) return;
    try {
      // The store is the source of truth; the engine call only carries the new
      // value into `state.json` so the notification greys "previous" at once.
      await WallpaperGroupStore(await _openDb()).writeHistoryLimit(value);
      await wallpaperEngineLink.setHistoryLimit(value);
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to write the wallpaper history limit', error, stack);
    }
    if (!mounted) return;
    setState(() => _limit = value);
  }

  Future<void> _openEntry(AvesEntry entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: EntryViewerPage.routeName),
        builder: (_) => EntryViewerPage(initialEntry: entry),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AvesScaffold(
      appBar: AppBar(
        title: Text(l10n.wallpaperGroupHistoryTitle),
        actions: [
          PopupMenuButton<_HistoryAction>(
            icon: const Icon(AIcons.more),
            tooltip: MaterialLocalizations.of(context).showMenuTooltip,
            onSelected: (action) => unawaited(_onAction(action)),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _HistoryAction.clear,
                enabled: _rowCount > 0,
                child: _menuRow(AIcons.delete, l10n.wallpaperGroupHistoryClear),
              ),
              PopupMenuItem(
                value: _HistoryAction.limit,
                child: _menuRow(AIcons.edit, '${l10n.wallpaperGroupHistoryLimit} ($_limit)'),
              ),
            ],
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _limit <= 0 ? l10n.wallpaperGroupHistoryEmptyDisabled : l10n.wallpaperGroupHistoryEmpty,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, index) => _buildRow(context, _items[index]),
                ),
    );
  }

  Widget _buildRow(BuildContext context, _HistoryItem item) {
    final row = item.row;
    final entry = item.entry;
    const extent = 56.0;
    final borderRadius = BorderRadius.circular(6);
    final groupName = wallpaperGroupNameOf(context, name: row.groupName, number: row.groupNumber);
    final usedAt = formatDateTime(DateTime.fromMillisecondsSinceEpoch(row.usedAt), settings.avesLocale, MediaQuery.alwaysUse24HourFormatOf(context));
    return ListTile(
      leading: ClipRRect(
        borderRadius: borderRadius,
        child: SizedBox(
          width: extent,
          height: extent,
          child: ThumbnailImage(
            entry: entry,
            extent: extent,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          ),
        ),
      ),
      title: Text(entry.bestTitle ?? entry.uri, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('$groupName · $usedAt', maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => unawaited(_openEntry(entry)),
    );
  }

  Widget _menuRow(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
        ],
      );
}
