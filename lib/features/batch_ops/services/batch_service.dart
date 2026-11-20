import 'package:aves/features/batch_ops/log.dart';
import 'package:aves/features/batch_ops/model/batch_job.dart';
import 'package:aves/services/common/channel.dart';
import 'package:flutter/services.dart';

/// Starts one native batch job and streams its per-item events.
class BatchService {
  static final _stream = AvesStreamsChannel('deckers.thibault/aves/batch_stream');
  static const _platform = AvesMethodChannel('deckers.thibault/aves/batch');

  const new();

  Stream<BatchEvent> run(BatchJob job) {
    try {
      return _stream
          .receiveBroadcastStream(job.toMap())
          .where((event) => event is Map)
          .map((event) => BatchEvent.tryFromMap(event as Map<Object?, Object?>))
          .where((event) => event != null)
          .cast<BatchEvent>();
    } on PlatformException catch (error, stack) {
      batchLog.w('failed to start batch job ${job.jobId}', error, stack);
      return Stream.error(error);
    }
  }

  Future<void> cancel(String jobId) async {
    try {
      await _platform.invokeMethod('cancel', <String, Object?>{'jobId': jobId});
    } on PlatformException catch (error, stack) {
      batchLog.w('failed to cancel batch job $jobId', error, stack);
    }
  }

  /// Overwrites [sourceUri] with the bytes of [resultUri].
  ///
  /// Native keeps the source row's date columns and renames the file when the
  /// result uses another format; the result file is consumed. Returns whether the
  /// replacement happened.
  Future<bool> replaceWithResult({required String sourceUri, required String resultUri}) async {
    try {
      final replaced = await _platform.invokeMethod<bool>('replaceWithResult', <String, Object?>{
        'sourceUri': sourceUri,
        'resultUri': resultUri,
      });
      return replaced == true;
    } on PlatformException catch (error, stack) {
      batchLog.w('failed to replace $sourceUri with $resultUri', error, stack);
      return false;
    }
  }

  /// Asks the system for write access to the files a replacement will touch.
  ///
  /// Scoped storage only lets the app overwrite files it does not own after the
  /// user grants access, so the whole selection is requested at once instead of
  /// prompting per photo. A denial is not fatal: files the app owns still write.
  Future<bool> requestWriteAccess({required List<String> uris, required List<String> mimeTypes}) async {
    if (uris.isEmpty) return true;
    try {
      final granted = await _platform.invokeMethod<bool>('requestWriteAccess', <String, Object?>{
        'uris': uris,
        'mimeTypes': mimeTypes,
      });
      return granted == true;
    } on PlatformException catch (error, stack) {
      batchLog.w('failed to request write access for ${uris.length} files', error, stack);
      return false;
    }
  }

  /// Deletes a result file permanently.
  ///
  /// Consumed and superseded results must not clutter the recycle bin, so this
  /// bypasses the app's delete setting on purpose.
  Future<bool> deleteResult(String resultUri) async {
    try {
      final deleted = await _platform.invokeMethod<bool>('deleteResult', <String, Object?>{'resultUri': resultUri});
      return deleted == true;
    } on PlatformException catch (error, stack) {
      batchLog.w('failed to delete result $resultUri', error, stack);
      return false;
    }
  }
}
