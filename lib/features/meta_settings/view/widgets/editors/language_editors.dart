import 'dart:ui' as ui;

import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/theme/durations.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/settings/language/locale_selection_page.dart';
import 'package:aves/widgets/settings/language/locales.dart';
import 'package:collection/collection.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Custom editor for the app language.
///
/// Delegates the picker to the existing `LocaleSelectionPage` and applies the
/// result through the typed setter (which also resets the resolved locale).
class LocaleEditor extends StatelessWidget {
  static const _systemLocaleOption = ui.Locale('system');

  final SettingDef def;

  const new({super.key, required this.def});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      // key is expected by test driver
      key: const Key('tile-language'),
      title: Text(def.title(context)),
      subtitle: Selector<Settings, ui.Locale?>(
        selector: (context, settings) => settings.basicLocale,
        builder: (context, locale, child) => Text(locale == null ? context.l10n.settingsSystemDefault : _localeName(locale)),
      ),
      onTap: () async {
        final value = await Navigator.maybeOf(context)?.push<ui.Locale>(
          MaterialPageRoute(
            settings: const RouteSettings(name: LocaleSelectionPage.routeName),
            builder: (context) => const LocaleSelectionPage(),
          ),
        );
        // wait for the page to hide
        await Future.delayed(ADurations.pageTransitionLoose * timeDilation);
        if (value != null) {
          settings.basicLocale = value == _systemLocaleOption ? null : value;
        }
      },
    );
  }

  static String _localeName(ui.Locale locale) {
    final bcp47 = locale.toLanguageTag();
    return KnownLocale.all.firstWhereOrNull((v) => v.bcp47 == bcp47)?.endonym ?? bcp47;
  }
}
