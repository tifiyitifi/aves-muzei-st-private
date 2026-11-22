import 'package:aves/features/meta_settings/engine/meta_settings_engine.dart';
import 'package:aves/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:aves/features/meta_settings/model/enum/settings_category.dart';
import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';

/// The catalog's generic write path.
///
/// A def declares how to read its value and which widget edits it; the engine
/// validates the submitted value and writes it through the active store. These
/// tests pin the step between the guard and the store, which every generic
/// toggle and enum row relies on.
void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  tearDownAll(() async {
    await tearDownAllServices();
  });

  setUp(() async {
    await setUpServices();
  });

  const engine = MetaSettingsEngine();

  SettingDef toggleDef() => SettingDef(
    key: SettingKeys.enableBlurEffectKey,
    category: SettingsCategory.display,
    widgetKind: SettingWidgetKind.toggle,
    title: (_) => '',
    reader: (settings) => settings.enableBlurEffect,
  );

  test('a toggle def writes the value its reader reports', () {
    final def = toggleDef();
    final before = def.reader!(settings) as bool;

    engine.apply(def, !before);

    expect(def.reader!(settings), !before);
  });

  test('a rejected value never reaches the store', () {
    final def = toggleDef();
    final before = def.reader!(settings) as bool;

    engine.apply(def, 'yes');

    expect(def.reader!(settings), before);
  });

  test('an enum def persists the member name', () {
    final def = SettingDef(
      key: SettingKeys.displayRefreshRateModeKey,
      category: SettingsCategory.display,
      widgetKind: SettingWidgetKind.enumPick,
      title: (_) => '',
      reader: (settings) => settings.displayRefreshRateMode,
      enumValues: DisplayRefreshRateMode.values,
    );

    engine.apply(def, DisplayRefreshRateMode.lowest);

    expect(def.reader!(settings), DisplayRefreshRateMode.lowest);
    expect(settings.getString(SettingKeys.displayRefreshRateModeKey), 'lowest');
  });
}
