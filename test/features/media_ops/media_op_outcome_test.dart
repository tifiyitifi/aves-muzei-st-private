import 'package:aves/features/media_ops/engine/media_op_keys.dart';
import 'package:aves/features/media_ops/engine/media_op_prefs.dart';
import 'package:aves/features/media_ops/media_op_outcome.dart';
import 'package:aves/services/common/image_op_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  setUp(() async {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    // the plugin caches its instance, so the store swap alone does not isolate tests
    await (await SharedPreferences.getInstance()).remove(MediaOpKeys.allowPermissionPrompt);
  });

  MoveOpEvent event({String? permission, String? strategy, bool success = true}) => MoveOpEvent(
        success: success,
        skipped: false,
        uri: 'content://media/external/images/media/1',
        newFields: const {},
        deleted: false,
        permission: permission,
        strategy: strategy,
      );

  group('MoveOpEvent', () {
    test('reads the optional outcome fields', () {
      final parsed = MoveOpEvent.fromMap(const {
        'uri': 'content://media/external/images/media/1',
        'success': true,
        'newFields': <String, Object?>{},
        'permission': 'denied',
        'strategy': 'file',
      });
      expect(parsed.permission, 'denied');
      expect(parsed.strategy, 'file');
    });

    test('leaves the outcome fields null for the legacy pipeline', () {
      final parsed = MoveOpEvent.fromMap(const {
        'uri': 'content://media/external/images/media/1',
        'success': true,
        'newFields': <String, Object?>{},
      });
      expect(parsed.permission, isNull);
      expect(parsed.strategy, isNull);
    });
  });

  group('recordMediaOpOutcome', () {
    test('remembers a denial', () async {
      final prefs = MediaOpPrefs();
      await prefs.init();
      await recordMediaOpOutcome([event(success: false, permission: MediaOpPermission.denied)], prefs: prefs);
      expect(prefs.allowPermissionPrompt, isFalse);

      final reloaded = MediaOpPrefs();
      await reloaded.init();
      expect(reloaded.allowPermissionPrompt, isFalse);
      prefs.dispose();
      reloaded.dispose();
    });

    test('ignores grants and unavailable requests', () async {
      final prefs = MediaOpPrefs();
      await prefs.init();
      await recordMediaOpOutcome([
        event(permission: MediaOpPermission.granted),
        event(permission: MediaOpPermission.unavailable),
        event(),
      ], prefs: prefs);
      expect(prefs.allowPermissionPrompt, isTrue);
      prefs.dispose();
    });

    test('a denial anywhere in the batch wins', () async {
      final prefs = MediaOpPrefs();
      await prefs.init();
      await recordMediaOpOutcome([
        event(),
        event(success: false, permission: MediaOpPermission.denied),
      ], prefs: prefs);
      expect(prefs.allowPermissionPrompt, isFalse);
      prefs.dispose();
    });
  });
}
