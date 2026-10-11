import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/features/meta_settings/view/widgets/meta_switch_list_tile.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/theme/durations.dart';
import 'package:aves/view/view.dart';
import 'package:aves/widgets/common/identity/aves_list_subtitle.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:aves/widgets/dialogs/selection_dialogs/reorderable_list.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Custom editor for showing/hiding the video filter.
///
/// It flips a hidden filter rather than a single settings key, so it cannot use
/// the generic store write.
class VideoShowVideosEditor extends StatelessWidget {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  Widget build(BuildContext context) => MetaSwitchListTile(
        selector: (context, settings) => !settings.hiddenFilters.contains(MimeFilter.video),
        onChanged: (value) => settings.changeFilterVisibility({MimeFilter.video}, value),
        title: def.title,
      );
}

/// Custom editor for the video thumbnail method priority list.
class VideoThumbnailMethodsEditor extends StatelessWidget {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  Widget build(BuildContext context) => Selector<Settings, List<VideoThumbnailMethod>>(
        selector: (context, settings) => settings.videoThumbnailMethods,
        builder: (context, current, child) => ListTile(
          title: Text(def.title(context)),
          subtitle: AvesListSubtitle(current.map((v) => v.getName(context)).join(', ')),
          onTap: () async {
            final value = await showAvesDialog<List<VideoThumbnailMethod>>(
              context: context,
              builder: (context) => AvesReorderableListDialog<VideoThumbnailMethod>(
                initialValue: current,
                options: Map.fromEntries(VideoThumbnailMethod.values.map((v) => MapEntry(v, v.getName(context)))),
              ),
              routeSettings: const RouteSettings(name: AvesReorderableListDialog.routeName),
            );
            // wait for the dialog to hide
            await Future.delayed(ADurations.dialogTransitionLoose * timeDilation);
            if (value != null) {
              settings.videoThumbnailMethods = value;
            }
          },
        ),
      );
}
