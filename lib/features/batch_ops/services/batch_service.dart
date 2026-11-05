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
}
