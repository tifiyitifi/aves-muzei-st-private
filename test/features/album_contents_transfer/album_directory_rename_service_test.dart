import 'package:aves/features/album_contents_transfer/services/album_directory_rename_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The platform answers with a strategy and, for a partial Media Store move,
/// how many rows already moved: the caller decides between falling back and
/// syncing the database first.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('deckers.thibault/aves/storage');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;

  setUp(() {
    calls = [];
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<AlbumDirectoryRenameOutcome> rename({required Object? reply, Object? error}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (error != null) throw error;
      return reply;
    });
    return PlatformAlbumDirectoryRenameService().renameAlbumDirectory(
      album: '/storage/emulated/0/Pictures/Holidays',
      newName: 'Trips',
    );
  }

  test('passes the folder and the new name to the platform', () async {
    await rename(reply: {'renamed': true, 'strategy': 'appPrivate'});

    expect(calls.single.method, 'renameAlbumDirectory');
    expect(calls.single.arguments, {
      'oldDir': '/storage/emulated/0/Pictures/Holidays',
      'newName': 'Trips',
    });
  });

  test('a renamed folder carries the strategy back', () async {
    final outcome = await rename(reply: {
      'renamed': true,
      'strategy': 'saf',
      'destination': '/storage/emulated/0/Pictures/Trips',
      'movedRows': -1,
      'failure': null,
    });

    expect(outcome.succeeded, isTrue);
    expect(outcome.strategy, AlbumDirectoryRenameStrategy.saf);
    expect(outcome.movedRows, -1);
  });

  test('an unsupported folder falls back to the batched move', () async {
    final outcome = await rename(reply: {'renamed': false, 'strategy': null, 'failure': 'unsupported'});

    expect(outcome.succeeded, isFalse);
    expect(outcome.failure, AlbumDirectoryRenameFailure.unsupported);
    expect(outcome.strategy, isNull);
  });

  test('a partial bulk move reports the rows that already moved', () async {
    final outcome = await rename(reply: {
      'renamed': false,
      'strategy': 'mediaStoreBulk',
      'movedRows': 3,
      'failure': 'partial',
    });

    expect(outcome.succeeded, isFalse);
    expect(outcome.failure, AlbumDirectoryRenameFailure.partial);
    expect(outcome.strategy, AlbumDirectoryRenameStrategy.mediaStoreBulk);
    expect(outcome.movedRows, 3);
  });

  test('a missing platform answers a plain failure', () async {
    final outcome = await rename(reply: null, error: PlatformException(code: 'boom'));

    expect(outcome.succeeded, isFalse);
    expect(outcome.failure, AlbumDirectoryRenameFailure.failed);
  });
}
