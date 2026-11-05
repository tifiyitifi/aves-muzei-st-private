import 'package:aves/services/common/channel.dart';
import 'package:aves/services/common/services.dart';

/// How the platform moved a whole album folder.
enum AlbumDirectoryRenameStrategy {
  /// Plain `File.renameTo` on storage the app owns (the vault).
  appPrivate,

  /// A SAF document rename: the provider moves the folder with its subfolders.
  saf,

  /// One Media Store `RELATIVE_PATH` update per collection: direct children
  /// only, which matches what the batched move does.
  mediaStoreBulk,
}

/// Why the platform refused a whole-directory rename.
enum AlbumDirectoryRenameFailure {
  /// No strategy applies to this folder: shared storage without a SAF grant
  /// or a write permission that needs no prompt. The batched move takes over.
  unsupported,

  /// A folder with that name already exists. The batched move merges into it,
  /// which a rename cannot, so the caller keeps that path.
  destinationExists,

  /// The folder is gone, e.g. a retry after the rename already happened.
  missing,

  invalidName,

  /// The folder is now split: some rows moved and kept their ids, the rest did
  /// not, and putting them back failed too. Only the Media Store bulk strategy
  /// can answer this; the caller syncs the database with the platform before
  /// falling back to the batched move.
  partial,

  /// The platform could not move the folder at all.
  failed,
}

/// The platform's answer to renaming one folder in place.
class AlbumDirectoryRenameOutcome {
  /// Whether the folder now carries the new name.
  final bool succeeded;

  /// Why it does not, when [succeeded] is false.
  final AlbumDirectoryRenameFailure? failure;

  /// Which strategy ran, when the platform reported one.
  final AlbumDirectoryRenameStrategy? strategy;

  /// How many rows the platform moved, or -1 when the strategy moves the whole
  /// folder and does not count rows.
  final int movedRows;

  const new({
    required this.succeeded,
    this.failure,
    this.strategy,
    this.movedRows = -1,
  });

  /// The folder now carries the new name.
  static AlbumDirectoryRenameOutcome renamed({required AlbumDirectoryRenameStrategy strategy, int movedRows = -1}) =>
      AlbumDirectoryRenameOutcome(succeeded: true, strategy: strategy, movedRows: movedRows);

  /// The caller keeps its batched move.
  static AlbumDirectoryRenameOutcome refused(
    AlbumDirectoryRenameFailure failure, {
    AlbumDirectoryRenameStrategy? strategy,
    int movedRows = -1,
  }) =>
      AlbumDirectoryRenameOutcome(succeeded: false, failure: failure, strategy: strategy, movedRows: movedRows);
}

/// Renames whole directories on the platform side.
abstract class AlbumDirectoryRenameService {
  Future<AlbumDirectoryRenameOutcome> renameAlbumDirectory({required String album, required String newName});
}

class PlatformAlbumDirectoryRenameService implements AlbumDirectoryRenameService {
  static const _platform = AvesMethodChannel('deckers.thibault/aves/storage');

  @override
  Future<AlbumDirectoryRenameOutcome> renameAlbumDirectory({required String album, required String newName}) async {
    try {
      final result = await _platform.invokeMapMethod<String, Object?>('renameAlbumDirectory', {
        'oldDir': album,
        'newName': newName,
      });
      if (result == null) return AlbumDirectoryRenameOutcome.refused(AlbumDirectoryRenameFailure.failed);
      final strategy = _strategyFrom(result['strategy'] as String?);
      final movedRows = (result['movedRows'] as int?) ?? -1;
      if (result['renamed'] == true) {
        // A strategy that moves the whole folder answers without rows; only a
        // Media Store bulk move has a count worth carrying.
        return AlbumDirectoryRenameOutcome.renamed(
          strategy: strategy ?? AlbumDirectoryRenameStrategy.appPrivate,
          movedRows: movedRows,
        );
      }
      return AlbumDirectoryRenameOutcome.refused(
        _failureFrom(result['failure'] as String?),
        strategy: strategy,
        movedRows: movedRows,
      );
    } catch (_) {
      // A missing channel (host/tests) or a platform-side crash both mean the
      // same to the caller: this album keeps the batched move.
      return AlbumDirectoryRenameOutcome.refused(AlbumDirectoryRenameFailure.failed);
    }
  }

  static AlbumDirectoryRenameStrategy? _strategyFrom(String? name) => switch (name) {
        'appPrivate' => AlbumDirectoryRenameStrategy.appPrivate,
        'saf' => AlbumDirectoryRenameStrategy.saf,
        'mediaStoreBulk' => AlbumDirectoryRenameStrategy.mediaStoreBulk,
        _ => null,
      };

  static AlbumDirectoryRenameFailure _failureFrom(String? reason) => switch (reason) {
        'unsupported' => AlbumDirectoryRenameFailure.unsupported,
        'destinationExists' => AlbumDirectoryRenameFailure.destinationExists,
        'missing' => AlbumDirectoryRenameFailure.missing,
        'invalidName' => AlbumDirectoryRenameFailure.invalidName,
        'partial' => AlbumDirectoryRenameFailure.partial,
        _ => AlbumDirectoryRenameFailure.failed,
      };
}

AlbumDirectoryRenameService get albumDirectoryRenameService => getIt<AlbumDirectoryRenameService>();
