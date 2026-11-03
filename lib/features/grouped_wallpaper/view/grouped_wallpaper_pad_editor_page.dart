import 'dart:async';

import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_pad_config.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_pad_action_view.dart';
import 'package:aves/features/meta_settings/model/page_keys.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/theme/styles.dart';
import 'package:aves/widgets/common/basic/font_size_icon_theme.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Configures the 9 cells of the three-finger view page's control pad.
///
/// The editor always shows the fixed 9 slots, even when the live pad is set to
/// shrink: the positions are how the user places an action, and a compacted
/// preview would move a button under their finger as they edit. The shape switch
/// is described in words instead.
class GroupedWallpaperPadEditorPage extends StatefulWidget {
  static const routeName = MetaPageKeys.wallpaperViewPad;

  const new({super.key});

  @override
  State<GroupedWallpaperPadEditorPage> createState() => _GroupedWallpaperPadEditorPageState();
}

class _GroupedWallpaperPadEditorPageState extends State<GroupedWallpaperPadEditorPage> {
  GroupedWallpaperPadConfig? _config;
  WallpaperGroupStore? _store;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final store = WallpaperGroupStore(await getIt<AppDatabaseProvider>().open());
      final config = await store.readViewPadConfig();
      if (!mounted) return;
      setState(() {
        _store = store;
        _config = config;
      });
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to read the view pad config', error, stack);
      if (!mounted) return;
      setState(() => _config = GroupedWallpaperPadConfig.defaultConfig);
    }
  }

  Future<void> _save(GroupedWallpaperPadConfig config) async {
    setState(() => _config = config);
    final store = _store;
    if (store == null) return;
    try {
      await store.writeViewPadConfig(config);
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to write the view pad config', error, stack);
    }
  }

  Future<void> _onSlotTap(int index) async {
    final config = _config;
    if (config == null) return;
    final current = config.slots[index];
    if (current == GroupedWallpaperPadAction.more) {
      // The menu is the only way back to the full action list; the model would
      // restore it anyway, so refusing here is clearer than a silent no-op.
      _snack(context.l10n.groupedWallpaperPadEditorMoreRequired);
      return;
    }
    final result = await showModalBottomSheet<({bool clear, GroupedWallpaperPadAction? action})>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _ActionPicker(
        actions: GroupedWallpaperPadAction.values,
        slots: config.slots,
        slot: index,
      ),
    );
    if (result == null || !mounted) return;
    if (result.clear) {
      await _save(config.withSlot(index, null));
    } else if (result.action != null) {
      await _save(config.withSlot(index, result.action));
    }
  }

  Future<void> _addAction(GroupedWallpaperPadAction action) async {
    final config = _config;
    if (config == null) return;
    await _save(config.withActionAdded(action));
  }

  void _snack(String text) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return AvesScaffold(
      appBar: AppBar(title: Text(context.l10n.groupedWallpaperPadEditorTitle)),
      body: config == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FontSizeIconTheme(child: Icon(AIcons.info)),
                      const SizedBox(width: 16),
                      Expanded(child: Text(context.l10n.groupedWallpaperPadEditorBanner)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                _sectionTitle(context.l10n.groupedWallpaperPadEditorSlots),
                _SlotGrid(config: config, onTap: _onSlotTap),
                const SizedBox(height: 8),
                _sectionTitle(context.l10n.groupedWallpaperPadEditorAvailable),
                _AvailableActions(config: config, onAdd: _addAction),
                const Divider(height: 24),
                SwitchListTile(
                  value: config.fitToActions,
                  title: Text(context.l10n.groupedWallpaperPadEditorFit),
                  subtitle: Text(context.l10n.groupedWallpaperPadEditorFitSubtitle),
                  onChanged: (value) => unawaited(_save(config.copyWith(fitToActions: value))),
                ),
                SwitchListTile(
                  value: config.usesBottomBar,
                  title: Text(context.l10n.groupedWallpaperPadEditorBottomBar),
                  subtitle: Text(config.canUseBottomBar ? context.l10n.groupedWallpaperPadEditorBottomBarSubtitle : context.l10n.groupedWallpaperPadEditorBottomBarUnavailable),
                  onChanged: config.canUseBottomBar ? (value) => unawaited(_save(config.copyWith(bottomBar: value))) : null,
                ),
              ],
            ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(text, style: AStyles.sectionTitleStyle(context.knownLocale)),
  );
}

/// The 9 fixed cells, drawn as an editable 3x3 grid.
class _SlotGrid extends StatelessWidget {
  final GroupedWallpaperPadConfig config;
  final ValueChanged<int> onTap;

  const new({required this.config, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: GroupedWallpaperPadConfig.slotCount,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemBuilder: (context, index) => _EditorCell(
          action: config.slots[index],
          required: config.slots[index] == GroupedWallpaperPadAction.more,
          onTap: () => onTap(index),
        ),
      ),
    );
  }
}

class _EditorCell extends StatelessWidget {
  final GroupedWallpaperPadAction? action;
  final bool required;
  final VoidCallback onTap;

  const new({required this.action, required this.required, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = this.action;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: action == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(AIcons.add, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.groupedWallpaperPadEditorEmpty,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(groupedWallpaperPadActionIcon(action)),
                    const SizedBox(height: 4),
                    Text(
                      groupedWallpaperPadActionLabel(context, action),
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (required) Icon(AIcons.locked, size: 12, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The actions not assigned yet.
class _AvailableActions extends StatelessWidget {
  final GroupedWallpaperPadConfig config;
  final ValueChanged<GroupedWallpaperPadAction> onAdd;

  const new({required this.config, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final used = config.actions.toSet();
    final available = [
      for (final action in GroupedWallpaperPadAction.values)
        if (!used.contains(action)) action,
    ];
    if (available.isEmpty || config.firstEmptySlot < 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(context.l10n.groupedWallpaperPadEditorFull),
      );
    }
    return Column(
      children: [
        for (final action in available)
          ListTile(
            leading: Icon(groupedWallpaperPadActionIcon(action)),
            title: Text(groupedWallpaperPadActionLabel(context, action)),
            onTap: () => onAdd(action),
          ),
      ],
    );
  }
}

/// One action per row, with the actions already used elsewhere disabled.
class _ActionPicker extends StatelessWidget {
  final List<GroupedWallpaperPadAction> actions;
  final List<GroupedWallpaperPadAction?> slots;
  final int slot;

  const new({required this.actions, required this.slots, required this.slot});

  @override
  Widget build(BuildContext context) {
    final current = slots[slot];
    final usedElsewhere = {
      for (var i = 0; i < slots.length; i++)
        if (i != slot && slots[i] != null) slots[i]!,
    };
    return SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(context.l10n.groupedWallpaperPadEditorPickTitle, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (current != null)
            ListTile(
              leading: const Icon(AIcons.delete),
              title: Text(context.l10n.groupedWallpaperPadEditorClear),
              onTap: () => Navigator.pop(context, (clear: true, action: null)),
            ),
          for (final action in actions)
            if (action != GroupedWallpaperPadAction.more)
              ListTile(
                enabled: !usedElsewhere.contains(action),
                leading: Icon(groupedWallpaperPadActionIcon(action)),
                title: Text(groupedWallpaperPadActionLabel(context, action)),
                trailing: action == current
                    ? const Icon(AIcons.checked)
                    : usedElsewhere.contains(action)
                    ? const Icon(AIcons.locked)
                    : null,
                onTap: usedElsewhere.contains(action) ? null : () => Navigator.pop(context, (clear: false, action: action)),
              ),
        ],
      ),
    );
  }
}
