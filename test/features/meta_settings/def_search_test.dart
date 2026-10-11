import 'package:aves/features/meta_settings/data/def_search.dart';
import 'package:aves/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:aves/features/meta_settings/model/enum/settings_category.dart';
import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SettingDef def(String key) => SettingDef(
    key: key,
    category: SettingsCategory.display,
    widgetKind: SettingWidgetKind.toggle,
    title: (context) => key,
  );

  int takeCount(List<String> recent, List<SettingDef> defs) => recentSettingKeyTakeCount(
    recentKeys: recent,
    defs: defs,
    keysOf: (def) => [def.key],
  );

  group('recentSettingKeyTakeCount', () {
    test('stops at the target when the newest keys already match enough defs', () {
      expect(takeCount(['a', 'b', 'c', 'd', 'e'], [def('a'), def('b'), def('c')]), 3);
    });

    test('grows the window until enough defs match', () {
      // window 3 = {a,b,c} matches only `a`, so it grows to the full history
      expect(takeCount(['a', 'b', 'c', 'd', 'e'], [def('a'), def('d'), def('e')]), 5);
    });

    test('returns the target for an empty history', () {
      expect(takeCount(const [], [def('a')]), 3);
    });

    test('treats a def as matched when any of its keys is recent', () {
      // subPage matches only through its second key; if multi-key resolution were
      // missing, the window would have to grow past the target to reach 3 defs.
      final subPage = def('/p');
      final count = recentSettingKeyTakeCount(
        recentKeys: const ['k1', 'k2', 'k3', 'k4'],
        defs: [subPage, def('k1'), def('k2')],
        keysOf: (def) => def.key == '/p' ? const ['z', 'k3'] : [def.key],
      );
      expect(count, 3);
    });
  });
}
