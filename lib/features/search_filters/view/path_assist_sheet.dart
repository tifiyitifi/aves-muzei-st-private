import 'dart:io';

import 'package:aves/features/search_filters/model/search_assist.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/utils/android_file_utils.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/explorer/crumb_line.dart';
import 'package:aves/view/view.dart';
import 'package:aves_model/aves_model.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';

/// Opens the directory picker of the search assist.
///
/// Returns the updated assist (the path condition replaced), or null when the
/// sheet was dismissed without confirming.
Future<SearchAssist?> showPathAssistSheet(BuildContext context, {required SearchAssist initial}) {
  return showModalBottomSheet<SearchAssist>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _PathAssistSheet(initial: initial),
  );
}

class _PathAssistSheet extends StatefulWidget {
  final SearchAssist initial;

  const new({required this.initial});

  @override
  State<_PathAssistSheet> createState() => _PathAssistSheetState();
}

class _PathAssistSheetState extends State<_PathAssistSheet> {
  late VolumeRelativeDirectory? _directory;
  late PathAssistMode _mode;
  late Future<List<Directory>> _listing;

  Set<StorageVolume> get _volumes => androidFileUtils.storageVolumes;

  @override
  void initState() {
    super.initState();
    final path = widget.initial.path;
    _mode = path?.mode ?? PathAssistMode.include;
    _directory = path != null ? androidFileUtils.relativeDirectoryFromPath(path.path) : null;
    final startVolume = _volumes.firstWhereOrNull((volume) => volume.isPrimary) ?? _volumes.firstOrNull;
    _directory ??= startVolume != null ? VolumeRelativeDirectory.volume(startVolume) : null;
    _listing = _listDirectories();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final height = MediaQuery.sizeOf(context).height * .8;
    final directory = _directory;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 8, 8),
            child: Row(
              children: [
                Expanded(child: Text(l10n.searchAssistPathTitle, style: Theme.of(context).textTheme.titleMedium)),
                if (_volumes.length > 1) _buildVolumeButton(context),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // Two chips instead of a segmented button: the labels are long
            // enough that a narrow screen would overflow the segments.
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  avatar: const Icon(AIcons.show, size: 18),
                  label: Text(l10n.searchAssistPathInclude),
                  selected: _mode == PathAssistMode.include,
                  onSelected: (_) => setState(() => _mode = PathAssistMode.include),
                ),
                ChoiceChip(
                  avatar: const Icon(AIcons.filterOff, size: 18),
                  label: Text(l10n.searchAssistPathExclude),
                  selected: _mode == PathAssistMode.exclude,
                  onSelected: (_) => setState(() => _mode = PathAssistMode.exclude),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: ExplorerCrumbLine(
              directory: directory,
              onTap: _goToDirectory,
              lastCrumbBuilder: null,
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Directory>>(
              future: _listing,
              builder: (context, snapshot) {
                final directories = snapshot.data ?? const <Directory>[];
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (directories.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(l10n.searchAssistPathNoSubdirectories, textAlign: TextAlign.center),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: directories.length,
                  itemBuilder: (context, index) {
                    final dir = directories[index];
                    return ListTile(
                      leading: const Icon(AIcons.folder),
                      title: Text(pContext.basename(dir.path)),
                      onTap: () => _goToPath(dir.path),
                    );
                  },
                );
              },
            ),
          ),
          _buildActions(context),
        ],
      ),
    );
  }

  Widget _buildVolumeButton(BuildContext context) {
    return PopupMenuButton<StorageVolume>(
      icon: const Icon(AIcons.storageCard),
      tooltip: context.l10n.explorerActionSelectStorageVolume,
      onSelected: (volume) => _goToDirectory(VolumeRelativeDirectory.volume(volume)),
      itemBuilder: (context) => [
        for (final volume in _volumes)
          PopupMenuItem(
            value: volume,
            enabled: volume.path != _directory?.volumePath,
            child: Text(volume.getDescription(context)),
          ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    final l10n = context.l10n;
    final directory = _directory;
    final path = directory?.dirPath;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
        child: Row(
          children: [
            if (widget.initial.path != null)
              TextButton(
                onPressed: () => Navigator.pop(context, widget.initial.withPath(null)),
                child: Text(l10n.searchAssistClear),
              ),
            const Spacer(),
            FilledButton(
              onPressed: path == null ? null : () => Navigator.pop(context, widget.initial.withPath(PathAssist(path: path, mode: _mode))),
              child: Text(l10n.searchAssistPathUse),
            ),
          ],
        ),
      ),
    );
  }

  void _goToDirectory(VolumeRelativeDirectory? directory) {
    if (directory == null) return;
    setState(() {
      _directory = directory;
      _listing = _listDirectories();
    });
  }

  void _goToPath(String path) => _goToDirectory(androidFileUtils.relativeDirectoryFromPath(path));

  Future<List<Directory>> _listDirectories() async {
    final dirPath = _directory?.dirPath;
    if (dirPath == null) return const [];
    final result = <Directory>[];
    try {
      await for (final entity in Directory(dirPath).list(followLinks: false)) {
        if (entity is! Directory) continue;
        if (pContext.basename(entity.path).startsWith('.')) continue;
        result.add(entity);
      }
    } catch (_) {
      // An unreadable directory (a removed volume, a denied path) reads as
      // "nothing below here", which is exactly what the picker can offer.
      return const [];
    }
    result.sort((a, b) => pContext.basename(a.path).toLowerCase().compareTo(pContext.basename(b.path).toLowerCase()));
    return result;
  }
}
