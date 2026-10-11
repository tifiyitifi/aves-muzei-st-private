import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/features/meta_settings/view/widgets/meta_selection_list_tile.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/services/accessibility_service.dart';
import 'package:aves/view/view.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';

/// Custom editor for the time-to-take-action timeout.
///
/// The candidate values depend on an async system capability check
/// (`AccessibilityService.hasRecommendedTimeouts`), so they cannot be a static
/// catalog field.
class TimeToTakeActionEditor extends StatefulWidget {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  State<TimeToTakeActionEditor> createState() => _TimeToTakeActionEditorState();
}

class _TimeToTakeActionEditorState extends State<TimeToTakeActionEditor> {
  late final Future<bool> _hasSystemOptionLoader = AccessibilityService.hasRecommendedTimeouts();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasSystemOptionLoader,
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData) return const SizedBox();
        const values = AccessibilityTimeout.values;
        final optionValues = snapshot.data! ? values : values.where((v) => v != AccessibilityTimeout.system).toList();

        return MetaSelectionListTile<AccessibilityTimeout>(
          values: optionValues,
          getName: (context, value) => value.getName(context),
          selector: (context, settings) => settings.timeToTakeAction,
          onSelection: (value) => settings.timeToTakeAction = value,
          tileTitle: widget.def.title,
        );
      },
    );
  }
}
