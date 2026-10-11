import 'package:aves/features/meta_settings/model/editor_keys.dart';
import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/features/meta_settings/view/widgets/editors/display_editors.dart';
import 'package:aves/features/meta_settings/view/widgets/editors/settings_engine_editor.dart';
import 'package:flutter/widgets.dart';

typedef MetaEditorBuilder = Widget Function(BuildContext context, SettingDef def);

/// Maps `SettingDef.editorKey` to a fork-owned editor widget.
final Map<String, MetaEditorBuilder> metaEditorRegistry = {
  MetaEditorKeys.settingsEngine: (context, def) => const SettingsEngineEditor(),
  MetaEditorKeys.themeColorMode: (context, def) => ThemeColorModeEditor(def: def),
  MetaEditorKeys.forceTvLayout: (context, def) => ForceTvLayoutEditor(def: def),
};
