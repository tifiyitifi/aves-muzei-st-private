import 'package:aves/features/batch_ops/model/batch_action.dart';
import 'package:aves/features/batch_ops/model/batch_job.dart';
import 'package:flutter/foundation.dart';

/// One finished item of a batch job, as the controller saw it.
///
/// The controller knows the source item and the actions; the native event knows
/// where the file landed. Handing both to a recorder keeps persistence out of the
/// controller and lets tests pass a fake.
@immutable
class BatchRecordedItem {
  final String jobId;
  final int index;
  final BatchItem item;
  final List<BatchAction> actions;

  final String resultUri;
  final String? resultPath;
  final String? resultName;
  final int? resultSize;
  final String? resultMimeType;

  /// The output folder the job was told to write to, as a MediaStore relative
  /// path. The recorder uses it to accept only normal batch runs, before the
  /// absolute path of the file is known.
  final String? outputRelativePath;

  const new({
    required this.jobId,
    required this.index,
    required this.item,
    required this.actions,
    required this.resultUri,
    this.resultPath,
    this.resultName,
    this.resultSize,
    this.resultMimeType,
    this.outputRelativePath,
  });
}

/// Persists what a batch run produced.
abstract interface class BatchResultRecorder {
  Future<void> record(BatchRecordedItem recorded);
}
