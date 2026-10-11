import 'package:aves/features/meta_settings/model/enum/settings_engine_version.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/widgets.dart';

/// Localized name of a settings engine, shared by the v1 list and the v2 surface.
String settingsEngineName(BuildContext context, SettingsEngineVersion version) => switch (version) {
      SettingsEngineVersion.v1 => context.l10n.settingsEngineV1,
      SettingsEngineVersion.v2 => context.l10n.settingsEngineV2,
    };
