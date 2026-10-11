import 'package:aves/features/meta_settings/engine/value_guard.dart';
import 'package:aves/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:aves/features/meta_settings/model/enum/settings_category.dart';
import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final toggle = SettingDef(
    key: 'k',
    category: SettingsCategory.display,
    widgetKind: SettingWidgetKind.toggle,
    title: (context) => 'k',
    reader: (settings) => true,
  );
  final enumPick = SettingDef(
    key: 'k',
    category: SettingsCategory.display,
    widgetKind: SettingWidgetKind.enumPick,
    title: (context) => 'k',
    reader: (settings) => AvesThemeBrightness.system,
    enumValues: AvesThemeBrightness.values,
    enumName: (context, value) => value.name,
  );
  final custom = SettingDef(
    key: 'k',
    category: SettingsCategory.display,
    widgetKind: SettingWidgetKind.custom,
    title: (context) => 'k',
    editorKey: 'editor',
  );
  final subPage = SettingDef(
    key: 'page',
    category: SettingsCategory.display,
    widgetKind: SettingWidgetKind.subPage,
    title: (context) => 'page',
    routeName: 'page',
  );

  group('MetaValueGuard', () {
    test('accepts a bool for a toggle and rejects other types', () {
      expect(MetaValueGuard.guard(toggle, true), isTrue);
      expect(MetaValueGuard.guard(toggle, false), isFalse);
      expect(() => MetaValueGuard.guard(toggle, 'true'), throwsA(isA<MetaSettingValueException>()));
    });

    test('accepts a known enum member and rejects others', () {
      expect(MetaValueGuard.guard(enumPick, AvesThemeBrightness.dark), AvesThemeBrightness.dark);
      expect(() => MetaValueGuard.guard(enumPick, 'dark'), throwsA(isA<MetaSettingValueException>()));
      expect(() => MetaValueGuard.guard(enumPick, CoordinateFormat.dms), throwsA(isA<MetaSettingValueException>()));
    });

    test('passes custom values through untouched', () {
      expect(MetaValueGuard.guard(custom, 'anything'), 'anything');
    });

    test('rejects any value for a sub-page (it is a route, not a setting)', () {
      expect(() => MetaValueGuard.guard(subPage, 'x'), throwsA(isA<MetaSettingValueException>()));
      expect(() => MetaValueGuard.guard(subPage, null), throwsA(isA<MetaSettingValueException>()));
    });
  });
}
