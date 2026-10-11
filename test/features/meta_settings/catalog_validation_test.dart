import 'package:aves/features/meta_settings/data/catalog_validation.dart';
import 'package:aves/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:aves/features/meta_settings/model/enum/settings_category.dart';
import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SettingDef def({
    required String key,
    required SettingWidgetKind widgetKind,
    Object? Function(Object?)? reader,
    String? editorKey,
    String? availabilityKey,
    String? routeName,
  }) =>
      SettingDef(
        key: key,
        category: SettingsCategory.display,
        widgetKind: widgetKind,
        title: (context) => key,
        reader: reader == null ? null : (settings) => reader(settings),
        enumValues: widgetKind == SettingWidgetKind.enumPick ? AvesThemeBrightness.values : null,
        enumName: widgetKind == SettingWidgetKind.enumPick ? (context, value) => value.name : null,
        editorKey: editorKey,
        availabilityKey: availabilityKey,
        routeName: routeName,
      );

  group('validateMetaSettingsCatalog', () {
    test('accepts a well-formed catalog', () {
      final problems = validateMetaSettingsCatalog(
        [
          def(key: 'a', widgetKind: SettingWidgetKind.toggle, reader: (_) => true),
          def(key: 'b', widgetKind: SettingWidgetKind.enumPick, reader: (_) => AvesThemeBrightness.system),
          def(key: 'c', widgetKind: SettingWidgetKind.custom, editorKey: 'editor'),
        ],
        registeredEditorKeys: {'editor'},
        registeredAvailabilityKeys: {},
        registeredPageRouteNames: const {},
      );
      expect(problems, isEmpty);
    });

    test('flags duplicates and missing per-kind fields', () {
      final problems = validateMetaSettingsCatalog(
        [
          def(key: 'dup', widgetKind: SettingWidgetKind.toggle, reader: (_) => true),
          def(key: 'dup', widgetKind: SettingWidgetKind.toggle, reader: (_) => true),
          def(key: 'no_reader', widgetKind: SettingWidgetKind.toggle),
          def(key: 'no_editor', widgetKind: SettingWidgetKind.custom),
          def(key: 'bad_editor', widgetKind: SettingWidgetKind.custom, editorKey: 'missing'),
          def(key: 'bad_availability', widgetKind: SettingWidgetKind.toggle, reader: (_) => true, availabilityKey: 'missing'),
          def(key: 'bad_page', widgetKind: SettingWidgetKind.subPage, routeName: 'missing'),
        ],
        registeredEditorKeys: const {},
        registeredAvailabilityKeys: const {},
        registeredPageRouteNames: const {},
      );

      expect(problems, contains('duplicate key "dup"'));
      expect(problems.any((p) => p.startsWith('no_reader')), isTrue);
      expect(problems.any((p) => p.startsWith('no_editor')), isTrue);
      expect(problems.any((p) => p.contains('unregistered editorKey "missing"')), isTrue);
      expect(problems.any((p) => p.contains('unregistered availabilityKey "missing"')), isTrue);
      expect(problems.any((p) => p.contains('unregistered sub-page "missing"')), isTrue);
    });
  });
}
