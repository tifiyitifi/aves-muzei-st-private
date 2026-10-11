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

  group('MetaValueGuard', () {
    test('accepts a bool for a toggle and rejects other types', () {
      expect(MetaValueGuard.guard(toggle, true), isTrue);
      expect(MetaValueGuard.guard(toggle, false), isFalse);
      expect(() => MetaValueGuard.guard(toggle, 'true'), throwsA(isA<MetaSettingValueException>()));
    });

    test('accepts a known enum name and rejects unknown ones', () {
      final name = AvesThemeBrightness.dark.name;
      expect(MetaValueGuard.guard(enumPick, name), name);
      expect(() => MetaValueGuard.guard(enumPick, 'nope'), throwsA(isA<MetaSettingValueException>()));
    });

    test('passes custom values through untouched', () {
      expect(MetaValueGuard.guard(custom, 'anything'), 'anything');
    });
  });
}
