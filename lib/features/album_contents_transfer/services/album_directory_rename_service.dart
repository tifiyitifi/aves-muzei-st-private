import 'package:aves/services/common/channel.dart';
import 'package:aves/services/common/services.dart';

/// Why the platform refused a whole-directory rename.
enum AlbumDirectoryRenameFailure {
  /// The folder is on shared storage, which has to go through the Media Store
  /// or SAF: `File.renameTo` there would change the row identity favourites,
  /// covers and pins are keyed on.
  notAppPrivate,

  /// A folder with that name already exists. The batched move merges into it,
  /// which a rename cannot, so the caller keeps that path.
  destinationExists,

  /// The folder is gone, e.g. a retry after the rename already happened.
  missing,

  invalidName,

  /// The platform could not move the folder at all.
  failed,
}

/// The platform's answer to renaming one folder in place.
class AlbumDirectoryRenameOutcome {
  /// Whether the folder now carries the new name.
  final bool succeeded;

  /// Why it does not, when [succeeded] is false.
  final AlbumDirectoryRenameFailure? failure;

  const new({required this.succeeded, this.failure});

  /// The folder now carries the new name.
  static const AlbumDirectoryRenameOutcome success = AlbumDirectoryRenameOutcome(succeeded: true);

  /// The caller keeps its batched move.
  static AlbumDirectoryRenameOutcome refused(AlbumDirectoryRenameFailure failure) => AlbumDirectoryRenameOutcome(succeeded: false, failure: failure);
}

/// Renames whole directories on the platform side.
abstract class AlbumDirectoryRenameService {
  Future<AlbumDirectoryRenameOutcome> renameAppPrivateDirectory({required String album, required String newName});
}

class PlatformAlbumDirectoryRenameService implements AlbumDirectoryRenameService {
  static const _platform = AvesMethodChannel('deckers.thibault/aves/storage');

  @override
  Future<AlbumDirectoryRenameOutcome> renameAppPrivateDirectory({required String album, required String newName}) async {
    try {
      final result = await _platform.invokeMapMethod<String, Object?>('renameAppPrivateDirectory', {
        'oldDir': album,
        'newName': newName,
      });
      if (result == null) return AlbumDirectoryRenameOutcome.refused(AlbumDirectoryRenameFailure.failed);
      if (result['renamed'] == true) return AlbumDirectoryRenameOutcome.success;
      return AlbumDirectoryRenameOutcome.refused(_failureFrom(result['failure'] as String?));
    } catch (_) {
      // A missing channel (host/tests) or a platform-side crash both mean the
      // same to the caller: this album keeps the batched move.
      return AlbumDirectoryRenameOutcome.refused(AlbumDirectoryRenameFailure.failed);
    }
  }

  static AlbumDirectoryRenameFailure _failureFrom(String? reason) => switch (reason) {
        'notAppPrivate' => AlbumDirectoryRenameFailure.notAppPrivate,
        'destinationExists' => AlbumDirectoryRenameFailure.destinationExists,
        'missing' => AlbumDirectoryRenameFailure.missing,
        'invalidName' => AlbumDirectoryRenameFailure.invalidName,
        _ => AlbumDirectoryRenameFailure.failed,
      };
}

AlbumDirectoryRenameService get albumDirectoryRenameService => getIt<AlbumDirectoryRenameService>();
