import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_labels.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/theme/icons.dart';
import 'package:material_ui/material_ui.dart';

/// Grid adapter for one wallpaper group on the wallpaper page.
///
/// The page's grid is typed on `CollectionFilter`, and a group is not a media
/// filter: it selects which range the page edits. This adapter lets the group
/// cards take part in the real section layout (and therefore follow the grid,
/// list and mosaic modes) without teaching the upstream grid about groups. It is
/// view-only and never persisted.
class WallpaperGroupFilter extends CollectionFilter {
  static const type = 'wallpaper_group';

  /// Group id, or null for group 0 (「no wallpaper group effect」).
  final String? groupId;
  final int number;

  /// Stored name: an ARB key while bundled, user text once renamed.
  final String name;

  /// Stored description, shown as the card subtitle.
  final String description;
  final bool enabled;

  /// The group the actual wallpaper uses.
  final bool current;

  /// The group whose range this page shows.
  final bool selected;

  /// Number of images the group's range resolves to, when known.
  final int? count;

  const new({
    required this.groupId,
    required this.number,
    required this.name,
    this.description = '',
    this.enabled = true,
    this.current = false,
    this.selected = false,
    this.count,
    super.reversed = false,
  });

  bool get isNone => groupId == null;

  @override
  EntryPredicate get positiveTest => (_) => false;

  @override
  bool get exclusiveProp => false;

  @override
  String get universalLabel => name;

  @override
  String getLabel(BuildContext context) => wallpaperGroupNameOf(context, name: name, number: number, isNone: isNone);

  @override
  Widget? iconBuilder(BuildContext context, double size, {bool allowGenericIcon = true}) => Icon(AIcons.wallpaper, size: size);

  @override
  String get category => type;

  @override
  String get key => '$type-${groupId ?? 'none'}-$selected-$current-$enabled';

  @override
  Map<String, Object?> toJsonMap() => {
        'type': type,
        'groupId': groupId,
        'number': number,
        if (reversed) 'reversed': reversed,
      };

  @override
  List<Object?> get props => [groupId, number, name, description, enabled, current, selected, count, reversed];
}
