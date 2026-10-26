import 'package:aves/model/source/section_keys.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/view/view.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/filter_grids/common/enums.dart';
import 'package:aves_model/aves_model.dart';
import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

class ChipSectionKey extends SectionKey with Equatable {
  final String title;

  /// Optional title style for a page whose headers deliberately differ from the
  /// app-wide small-caps section style. A null style keeps the default.
  final TextStyle? titleStyle;

  @override
  List<Object?> get props => [title, titleStyle];

  const new({
    this.title = '',
    this.titleStyle,
  });

  Widget? get leading => null;

  /// Whether the header itself can start a selection. A read-only summary
  /// section opts out so long-pressing it cannot select non-selectable items.
  bool get selectable => true;

  /// Optional right-aligned widget after the title, e.g. a state label.
  Widget? buildTrailing(BuildContext context) => null;
}

class ChipImportanceSectionKey extends ChipSectionKey {
  final ChipImportance importance;
  final IconData? icon;

  new _private(BuildContext context, this.importance, {this.icon}) : super(title: importance.getText(context));

  factory newAlbum(BuildContext context) => ChipImportanceSectionKey._private(context, ChipImportance.newAlbum);

  factory pinned(BuildContext context) => ChipImportanceSectionKey._private(context, ChipImportance.pinned);

  factory group(BuildContext context) => ChipImportanceSectionKey._private(context, ChipImportance.group);

  factory special(BuildContext context) => ChipImportanceSectionKey._private(context, ChipImportance.special);

  factory apps(BuildContext context) => ChipImportanceSectionKey._private(context, ChipImportance.apps);

  factory vault(BuildContext context) => ChipImportanceSectionKey._private(context, ChipImportance.vaults);

  factory dynamic(BuildContext context) => ChipImportanceSectionKey._private(context, ChipImportance.dynamic);

  factory regular(BuildContext context, IconData icon) => ChipImportanceSectionKey._private(context, ChipImportance.regular, icon: icon);

  @override
  Widget get leading => Icon(icon ?? importance.getIcon());
}

class MimeTypeSectionKey extends ChipSectionKey {
  final AlbumMimeType mimeType;

  new _private(BuildContext context, this.mimeType) : super(title: mimeType.getText(context));

  factory images(BuildContext context) => MimeTypeSectionKey._private(context, AlbumMimeType.images);

  factory videos(BuildContext context) => MimeTypeSectionKey._private(context, AlbumMimeType.videos);

  factory mixed(BuildContext context) => MimeTypeSectionKey._private(context, AlbumMimeType.mixed);

  @override
  Widget get leading => Icon(mimeType.getIcon());
}

class StorageVolumeSectionKey extends ChipSectionKey {
  final StorageVolume? volume;

  new(BuildContext context, this.volume) : super(title: volume?.getDescription(context) ?? context.l10n.sectionUnknown);

  @override
  Widget? get leading => (volume?.isRemovable ?? false) ? const Icon(AIcons.storageCard) : null;
}
