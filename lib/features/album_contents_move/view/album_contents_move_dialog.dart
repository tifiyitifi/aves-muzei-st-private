import 'package:aves/features/album_contents_move/model/album_contents_move_plan.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/theme/themes.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:aves/widgets/dialogs/pick_dialogs/album_pick_page.dart';
import 'package:aves/widgets/filter_grids/common/enums.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';

typedef AlbumContentsMoveAnswer = ({String destination, bool deleteEmptyFolders});

Future<AlbumContentsMoveAnswer?> showAlbumContentsMoveDialog({
  required BuildContext context,
  required CollectionSource source,
  required Set<StoredAlbumFilter> albums,
  required Set<AvesEntry> entries,
  required Set<String> removableAlbumPaths,
}) {
  return showAvesDialog<AlbumContentsMoveAnswer>(
    context: context,
    builder: (context) => AlbumContentsMoveDialog(
      source: source,
      albums: albums,
      entries: entries,
      removableAlbumPaths: removableAlbumPaths,
    ),
    routeSettings: const RouteSettings(name: AlbumContentsMoveDialog.routeName),
  );
}

class AlbumContentsMoveDialog extends StatefulWidget {
  static const routeName = '/dialog/album_contents_move';

  final CollectionSource source;
  final Set<StoredAlbumFilter> albums;

  /// Visible entries of the selected albums. Invisible entries stay where they
  /// are, so a source folder with any of them is never considered empty.
  final Set<AvesEntry> entries;

  /// Source albums whose folder may be removed after the move, already limited
  /// to ordinary albums that are neither pinned, vault, nor a volume root.
  final Set<String> removableAlbumPaths;

  const new({
    super.key,
    required this.source,
    required this.albums,
    required this.entries,
    required this.removableAlbumPaths,
  });

  @override
  State<AlbumContentsMoveDialog> createState() => _AlbumContentsMoveDialogState();
}

class _AlbumContentsMoveDialogState extends State<AlbumContentsMoveDialog> {
  String? _destination;
  bool _deleteEmptyFolders = false;
  late final bool _hasRemovableAlbums;

  @override
  void initState() {
    super.initState();
    // Defaults to false every time the dialog opens: removing a folder is an
    // explicit opt-in, never a remembered preference.
    _hasRemovableAlbums = widget.removableAlbumPaths.any(
      (album) => widget.entries.any((entry) => entry.directory == album),
    );
  }

  AlbumContentsMovePlan get _plan => AlbumContentsMovePlan.resolve(
    sourceAlbums: widget.albums.map((filter) => filter.album).toSet(),
    removableSourceAlbums: widget.removableAlbumPaths,
    destination: _destination,
    entries: widget.entries,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final plan = _plan;
    final errorText = _errorText(context, plan);
    final bodySmall = Theme.of(context).textTheme.bodySmall;
    // Until a destination is picked the plan has no moving set, so the full
    // visible count is the honest preview; afterwards it reports what travels.
    final summaryCount = plan.isValid ? plan.entryCount : widget.entries.length;

    return AvesDialog(
      title: l10n.albumContentsMoveTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.albumContentsMoveSummary(summaryCount)),
          const SizedBox(height: 4),
          Text(l10n.albumContentsMoveSelectedAlbums(widget.albums.length), style: bodySmall),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(AIcons.folder),
            title: Text(l10n.albumContentsMoveDestination),
            subtitle: Text(
              _destination != null
                  ? widget.source.getStoredAlbumDisplayName(context, _destination!)
                  : l10n.albumContentsMoveDestinationNone,
            ),
            trailing: const Icon(AIcons.next),
            onTap: _pickDestination,
          ),
          if (errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              errorText,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _deleteEmptyFolders,
            onChanged: _hasRemovableAlbums
                ? (value) => setState(() {
                    _deleteEmptyFolders = value ?? false;
                  })
                : null,
            title: Text(l10n.albumContentsMoveDeleteEmptyFolders),
            subtitle: Text(l10n.albumContentsMoveDeleteEmptyFoldersHint),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          if (!_hasRemovableAlbums)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(l10n.albumContentsMoveDeleteEmptyFoldersUnavailable, style: bodySmall),
            ),
        ],
      ),
      actions: [
        const CancelButton(),
        TextButton(
          onPressed: plan.isValid ? _submit : null,
          child: Text(Themes.asButtonLabel(l10n.albumContentsMoveButtonLabel)),
        ),
      ],
    );
  }

  Future<void> _pickDestination() async {
    final filter = await pickAlbum(
      context: context,
      moveType: MoveType.move,
      chipTypes: {AlbumChipType.stored},
      initialGroup: null,
    );
    if (!mounted || filter is! StoredAlbumFilter) return;
    setState(() {
      _destination = filter.album;
    });
  }

  void _submit() {
    final destination = _destination;
    if (destination == null) return;
    Navigator.maybeOf(context)?.pop(
      (
        destination: destination,
        deleteEmptyFolders: _deleteEmptyFolders,
      ),
    );
  }

  String? _errorText(BuildContext context, AlbumContentsMovePlan plan) {
    final l10n = context.l10n;
    return switch (plan.error) {
      AlbumContentsMoveError.destinationInsideSource => l10n.albumContentsMoveDestinationInsideSource,
      AlbumContentsMoveError.destinationIsOnlySource => l10n.albumContentsMoveDestinationIsSource,
      AlbumContentsMoveError.noEntries => l10n.albumContentsMoveEmpty,
      _ => null,
    };
  }
}
