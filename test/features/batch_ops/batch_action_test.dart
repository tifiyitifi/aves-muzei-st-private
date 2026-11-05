import 'package:aves/features/batch_ops/model/batch_action.dart';
import 'package:aves/features/batch_ops/model/batch_job.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BatchAction', () {
    test('round-trips a filter action through JSON', () {
      final action = BatchActions.filter('Vintage', intensity: 0.5);
      final restored = BatchAction.tryFromJson(action.toJson());

      expect(restored, isNotNull);
      expect(restored!.kind, BatchToolKind.filter);
      expect(restored.settings['name'], 'Vintage');
      expect(restored.settings['intensity'], 0.5);
      expect(restored.enabled, isTrue);
    });

    test('keeps the disabled flag through JSON', () {
      final action = BatchActions.rotate(angle: 180).copyWith(enabled: false);
      final restored = BatchAction.tryFromJson(action.toJson());

      expect(restored, isNotNull);
      expect(restored!.enabled, isFalse);
      expect(restored.kind, BatchToolKind.rotate);
    });

    test('ignores an unknown action kind', () {
      expect(BatchAction.tryFromJson({'kind': 'nope', 'settings': {}}), isNull);
    });

    test('tool spec uses the native tool id', () {
      expect(BatchActions.rotate(angle: 180).toToolSpec(), {
        'id': 'refra.rotate',
        'settings': {'angle': 180.0},
      });
    });

    test('footer defaults to the automatic file name', () {
      final action = BatchActions.footer();
      expect(action.kind, BatchToolKind.footer);
      expect(action.settings.containsKey('text'), isFalse);
      expect(action.settings['bandHeightPercent'], 8);
      expect(action.settings['atTop'], isFalse);
    });
  });

  group('BatchJob', () {
    test('drops disabled actions from the native job', () {
      final job = BatchJob(
        jobId: 'job',
        items: const [
          BatchItem(entryId: 1, uri: 'content://media/1', displayName: 'IMG_0001.jpg'),
        ],
        actions: [
          BatchActions.filter('Vintage'),
          BatchActions.footer().copyWith(enabled: false),
        ],
      );

      final tools = job.toMap()['tools'] as List;
      expect(tools, hasLength(1));
      expect((tools.single as Map)['id'], 'refra.filter');
    });

    test('sends the default output folder', () {
      const output = BatchOutput();
      expect(output.relativePath, 'Pictures/aves_batch');
      expect(output.namePattern, '{name}');
      expect(output.format, 'keep');
    });
  });
}
