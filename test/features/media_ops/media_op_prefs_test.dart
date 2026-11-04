import 'package:aves/features/media_ops/engine/media_op_keys.dart';
import 'package:aves/features/media_ops/engine/media_op_prefs.dart';
import 'package:aves/features/media_ops/model/media_op_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
  });

  Future<void> clearKeys() async {
    final store = await SharedPreferences.getInstance();
    await store.remove(MediaOpKeys.engine);
    await store.remove(MediaOpKeys.allowPermissionPrompt);
  }

  group('MediaOpPrefs', () {
    test('starts on the fast pipeline and allows one prompt', () async {
      await clearKeys();
      final prefs = MediaOpPrefs();
      await prefs.init();
      expect(prefs.engine, MediaOpEngine.defaultEngine);
      expect(prefs.engine, MediaOpEngine.v2);
      expect(prefs.allowPermissionPrompt, isTrue);
      expect(prefs.isLoaded, isTrue);
      prefs.dispose();
    });

    test('persists and reloads values', () async {
      await clearKeys();
      final prefs = MediaOpPrefs();
      await prefs.init();
      await prefs.setEngine(MediaOpEngine.v1);
      await prefs.denyPermissionPrompt();
      prefs.dispose();

      final reloaded = MediaOpPrefs();
      await reloaded.init();
      expect(reloaded.engine, MediaOpEngine.v1);
      expect(reloaded.allowPermissionPrompt, isFalse);
      reloaded.dispose();
    });

    test('falls back to defaults on unknown values', () async {
      final store = await SharedPreferences.getInstance();
      await store.setString(MediaOpKeys.engine, 'v3');

      final prefs = MediaOpPrefs();
      await prefs.init();
      expect(prefs.engine, MediaOpEngine.defaultEngine);
      prefs.dispose();
    });

    test('notifies listeners only on actual change', () async {
      await clearKeys();
      final prefs = MediaOpPrefs();
      await prefs.init();
      var notified = 0;
      prefs.addListener(() => notified++);

      await prefs.setEngine(MediaOpEngine.v1);
      expect(notified, 1);
      await prefs.setEngine(MediaOpEngine.v1);
      expect(notified, 1);

      await prefs.denyPermissionPrompt();
      expect(notified, 2);
      // an operation that keeps reporting denials must not rewrite the preference
      await prefs.denyPermissionPrompt();
      expect(notified, 2);

      await prefs.resetPermissionPrompt();
      expect(notified, 3);
      expect(prefs.allowPermissionPrompt, isTrue);
      prefs.dispose();
    });

    test('reset re-enables prompts after a denial', () async {
      await clearKeys();
      final prefs = MediaOpPrefs();
      await prefs.init();
      await prefs.denyPermissionPrompt();
      expect(prefs.allowPermissionPrompt, isFalse);

      await prefs.resetPermissionPrompt();
      expect(prefs.allowPermissionPrompt, isTrue);

      final reloaded = MediaOpPrefs();
      await reloaded.init();
      expect(reloaded.allowPermissionPrompt, isTrue);
      prefs.dispose();
      reloaded.dispose();
    });
  });
}
