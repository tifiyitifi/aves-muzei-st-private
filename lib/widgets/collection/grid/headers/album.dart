import 'package:aves/features/collection_paging/view/album_catalog_badge.dart';
import 'package:aves/model/covers.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/source/section_keys.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/utils/android_file_utils.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/grid/header.dart';
import 'package:aves/widgets/common/identity/aves_icons.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';

class const AlbumSectionHeader({
  super.key,
  required final String? directory,
  required final String? albumName,
  required final bool selectable,
  final Widget? trailing,
}) extends StatelessWidget {
  static const _storageIconWidth = 16.0;
  static const _trailingGap = 4.0;
  static const _storageIcon = Icon(
    AIcons.storageCard,
    size: _storageIconWidth,
    color: Color(0xFF757575),
  );

  @override
  Widget build(BuildContext context) {
    Widget? albumIcon;
    final _directory = directory;
    if (_directory != null) {
      albumIcon = IconUtils.getAlbumIcon(context: context, albumPath: _directory);
      if (albumIcon != null) {
        albumIcon = RepaintBoundary(
          child: albumIcon,
        );
      }
    }
    return SectionHeader<AvesEntry>(
      sectionKey: EntryAlbumSectionKey(_directory),
      leading: albumIcon,
      title: albumName ?? context.l10n.sectionUnknown,
      trailing: _buildTrailing(),
      selectable: selectable,
    );
  }

  /// The catalog badge plus the removable-storage marker, side by side. Both
  /// are optional and independent: an album on a card can still be uncatalogued.
  Widget? _buildTrailing() {
    final badge = trailing;
    final dir = directory;
    final removable = dir != null && androidFileUtils.isOnRemovableStorage(dir);
    if (badge == null && !removable) return null;
    if (badge == null) return _storageIcon;
    if (!removable) return badge;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        const SizedBox(width: _trailingGap),
        _storageIcon,
      ],
    );
  }

  static double getPreferredHeight(BuildContext context, double maxWidth, CollectionSource source, EntryAlbumSectionKey sectionKey) {
    final directory = sectionKey.directory ?? context.l10n.sectionUnknown;
    return SectionHeader.getPreferredHeight(
      context: context,
      maxWidth: maxWidth,
      title: source.getStoredAlbumDisplayName(context, directory),
      hasLeading: covers.effectiveAlbumType(directory) != AlbumType.regular,
      trailingWidth: _trailingWidth(source, sectionKey.directory),
    );
  }

  /// The width [build] will occupy in the trailing slot, so the header is
  /// measured with the widgets it actually lays out.
  static double _trailingWidth(CollectionSource source, String? directory) {
    if (directory == null) return 0;
    var width = androidFileUtils.isOnRemovableStorage(directory) ? _storageIconWidth : 0.0;
    // An entry-free (paged) source carries the catalog badge, which the header
    // shows as soon as the album has pending rows.
    if (source.summaries != null) {
      if (width > 0) width += _trailingGap;
      width += AlbumCatalogBadge.width;
    }
    return width;
  }
}
