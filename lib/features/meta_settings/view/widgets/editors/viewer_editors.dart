import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/features/meta_settings/view/widgets/meta_entry_background_selector.dart';
import 'package:aves/features/meta_settings/view/widgets/meta_switch_list_tile.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Custom editor for the cutout toggle.
///
/// The setting is only relevant on cutout-aware devices, and that check is
/// async, so the row hides itself when unsupported.
class ViewerUseCutoutEditor extends StatefulWidget {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  State<ViewerUseCutoutEditor> createState() => _ViewerUseCutoutEditorState();
}

class _ViewerUseCutoutEditorState extends State<ViewerUseCutoutEditor> {
  late final Future<bool> _isCutoutAwareLoader = windowService.isCutoutAware();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isCutoutAwareLoader,
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        return MetaSwitchListTile(
          selector: (context, settings) => settings.viewerUseCutout,
          onChanged: (value) => settings.viewerUseCutout = value,
          title: widget.def.title,
        );
      },
    );
  }
}

/// Custom editor for the viewer image background (a color swatch dropdown).
class ViewerImageBackgroundEditor extends StatelessWidget {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  Widget build(BuildContext context) => Selector<Settings, EntryBackground>(
        selector: (context, settings) => settings.imageBackground,
        builder: (context, current, child) => ListTile(
          title: Text(def.title(context)),
          trailing: MetaEntryBackgroundSelector(
            getter: () => current,
            setter: (value) => settings.imageBackground = value,
          ),
        ),
      );
}
