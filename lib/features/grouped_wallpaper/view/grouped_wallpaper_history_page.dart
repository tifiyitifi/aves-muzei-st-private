import 'dart:async';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/grouped_wallpaper/db/grouped_wallpaper_history_store.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_history_entry.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_history_limit.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_labels.dart';
import 'package:aves/features/grouped_wallpaper/view/widgets/grouped_wallpaper_history_group_dialog.dart';
import 'package:aves/features/grouped_wallpaper/view/widgets/grouped_wallpaper_history_limit_dialog.dart';
import 'package:aves/features/visible_range/db/visible_range_store.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/theme/format.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/thumbnail/image.dart';
import 'package:aves/widgets/viewer/entry_viewer_page.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';

/// The photos the grouped wallpaper has shown, newest first.
///
/// It reads the history table directly instead of going through the engine: the
/// rows outlive a stopped wallpaper, and the page must work while the service is
/// not running. Rows whose photo left the library are skipped, so a deleted photo
/// does not leave an empty tile behind.
class GroupedWallpaperHistoryPage extends StatefulWidget {
  static const routeName = '/grouped_wallpaper/history';

  /// The group whose records are shown, or null to resolve it at load time.
  ///
  /// A group page passes its selected group and the viewer passes the playing
  /// one. The notification's button and a cold start have no group at all, so a
  /// null value falls back to the group playing in `state.json`.
  final String? groupId;

  const new({super.key, this.groupId});

  @override
  State<GroupedWallpaperHistoryPage> createState() => _GroupedWallpaperHistoryPageState();
}

enum _HistoryAction {
  switchGroup,
  limit,
  clear,
  toggleClearConfirm,
}

typedef _HistoryItem = ({GroupedWallpaperHistoryEntry row, AvesEntry entry});

class _GroupedWallpaperHistoryPageState extends State<GroupedWallpaperHistoryPage> {
  AppDatabase? _db;
  List<_HistoryItem> _items = const [];
  List<WallpaperGroup> _groups = const [];
  WallpaperGroup? _group;
  String? _groupId;
  int _rowCount = 0;
  int _limit = GroupedWallpaperHistoryLimit.defaultLimit;
  bool _loaded = false;
  bool _scopeResolved = false;
  bool _locked = false;
  bool _skipClearConfirm = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<AppDatabase> _openDb() async => _db ??= await getIt<AppDatabaseProvider>().open();

  Future<void> _load() async {
    try {
      final db = await _openDb();
      final groupStore = WallpaperGroupStore(db);
      final groups = await groupStore.loadGroups();
      await _resolveScope(groups);
      final rows = await GroupedWallpaperHistoryStore(db).load(groupId: _groupId);
      // The browsing source never materializes entries in this fork (the paged
      // engine loads rows on demand), so the photos are read straight from the
      // database by id; looking them up in `CollectionSource` returned nothing
      // and left the page permanently empty.
      final entries = await localMediaDb.loadEntriesById({for (final row in rows) row.entryId});
      final byId = {for (final entry in entries) entry.id: entry};
      final limit = await groupStore.readHistoryLimit();
      final skipClearConfirm = await groupStore.readHistoryClearSkipConfirm();
      final group = _groupId == null ? null : groups.firstWhereOrNull((group) => group.id == _groupId);
      final locked = group == null ? false : (await VisibleRangeStore(db).loadRange(scope: VisibleRangeScope.wallpaper, ownerId: group.id))?.locked ?? false;
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _group = group;
        _locked = locked;
        _items = [
          for (final row in rows)
            if (byId[row.entryId] case final entry?) (row: row, entry: entry),
        ];
        _rowCount = rows.length;
        _limit = limit;
        _skipClearConfirm = skipClearConfirm;
        _loaded = true;
      });
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to load the wallpaper history', error, stack);
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  /// Picks the group the page is scoped to, once.
  ///
  /// A group that no longer exists falls back to every group: its rows have no
  /// name or range to show, so the whole history is more useful than a scope the
  /// user cannot name.
  Future<void> _resolveScope(List<WallpaperGroup> groups) async {
    if (_scopeResolved) return;
    _scopeResolved = true;
    final candidate = widget.groupId ?? (await wallpaperEngineLink.readState())?.groupId;
    _groupId = groups.any((group) => group.id == candidate) ? candidate : null;
  }

  Future<void> _onAction(_HistoryAction action) async {
    switch (action) {
      case _HistoryAction.switchGroup:
        await _switchGroup();
      case _HistoryAction.limit:
        await _editLimit();
      case _HistoryAction.clear:
        await _clear();
      case _HistoryAction.toggleClearConfirm:
        await _toggleClearConfirm();
    }
  }

  Future<void> _clear() async {
    try {
      final db = await _openDb();
      if (!_skipClearConfirm) {
        final result = await showDialog<({bool confirmed, bool skipNext})>(
          context: context,
          builder: (_) => _ClearHistoryDialog(skipConfirm: _skipClearConfirm),
        );
        if (result == null || !result.confirmed || !mounted) return;
        await WallpaperGroupStore(db).writeHistoryClearSkipConfirm(result.skipNext);
      }
      // Clearing is all-or-nothing: the page is scoped to one group, but a
      // "clear" that left the other groups' records behind would surprise the
      // user, and the confirmation says so.
      await GroupedWallpaperHistoryStore(db).clear();
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to clear the wallpaper history', error, stack);
    }
    if (!mounted) return;
    await _load();
  }

  /// Turns the confirmation before clearing back on or off.
  ///
  /// Once the confirmation is skipped the dialog cannot offer the checkbox any
  /// more, so this menu entry is the only way to turn it back on.
  Future<void> _toggleClearConfirm() async {
    final value = !_skipClearConfirm;
    try {
      await WallpaperGroupStore(await _openDb()).writeHistoryClearSkipConfirm(value);
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to write the wallpaper history confirmation', error, stack);
      return;
    }
    if (!mounted) return;
    setState(() => _skipClearConfirm = value);
  }

  Future<void> _switchGroup() async {
    final store = GroupedWallpaperHistoryStore(await _openDb());
    final counts = <String, int>{};
    for (final group in _groups) {
      counts[group.id] = await store.count(groupId: group.id);
    }
    if (!mounted) return;
    final id = await showGroupedWallpaperHistoryGroupDialog(context, groups: _groups, counts: counts, selectedGroupId: _groupId);
    if (id == null || !mounted) return;
    setState(() => _groupId = id);
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

  /// A locked range refuses everything about its group, including reading
  /// another group's history from here.
  bool get _canSwitchGroup => _groups.length > 1 && !_locked;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final group = _group;
    return AvesScaffold(
      appBar: AppBar(
        title: group == null
            ? Text(l10n.wallpaperGroupHistoryTitle)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.wallpaperGroupHistoryTitle),
                  Text(
                    wallpaperGroupName(context, group),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
        actions: [
          PopupMenuButton<_HistoryAction>(
            icon: const Icon(AIcons.more),
            tooltip: MaterialLocalizations.of(context).showMenuTooltip,
            onSelected: (action) => unawaited(_onAction(action)),
            itemBuilder: (context) => [
              if (_canSwitchGroup)
                PopupMenuItem(
                  value: _HistoryAction.switchGroup,
                  child: _menuRow(AIcons.group, l10n.wallpaperGroupHistorySwitchGroup, subtitle: group == null ? null : wallpaperGroupName(context, group)),
                ),
              PopupMenuItem(
                value: _HistoryAction.limit,
                child: _menuRow(AIcons.edit, '${l10n.wallpaperGroupHistoryLimit} ($_limit)'),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _HistoryAction.clear,
                enabled: _rowCount > 0,
                child: _menuRow(AIcons.delete, l10n.wallpaperGroupHistoryClear),
              ),
              CheckedPopupMenuItem(
                value: _HistoryAction.toggleClearConfirm,
                checked: !_skipClearConfirm,
                child: _menuRow(null, l10n.wallpaperGroupHistoryClearConfirmToggle),
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
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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

  Widget _menuRow(IconData? icon, String text, {String? subtitle}) => Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(text, overflow: TextOverflow.ellipsis),
                if (subtitle != null) Text(subtitle, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      );
}

/// Confirms clearing every group's history, with a "do not ask again" box.
///
/// The checkbox starts at the stored value, so a user who turned it off can turn
/// it back on here while the dialog still appears; the menu entry covers the
/// case where it no longer does.
class _ClearHistoryDialog extends StatefulWidget {
  final bool skipConfirm;

  const new({required this.skipConfirm});

  @override
  State<_ClearHistoryDialog> createState() => _ClearHistoryDialogState();
}

class _ClearHistoryDialogState extends State<_ClearHistoryDialog> {
  late bool _skip = widget.skipConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.wallpaperGroupHistoryClearConfirm),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _skip,
            onChanged: (value) => setState(() => _skip = value ?? false),
            title: Text(l10n.wallpaperGroupHistoryClearDontAsk),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
        TextButton(
          onPressed: () => Navigator.pop(context, (confirmed: true, skipNext: _skip)),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}
