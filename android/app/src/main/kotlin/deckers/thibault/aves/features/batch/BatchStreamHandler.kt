package deckers.thibault.aves.features.batch

import android.content.Context
import deckers.thibault.aves.channel.streams.BaseStreamHandler
import deckers.thibault.aves.utils.LogUtils
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.launch

/**
 * Streams one batch job's events back to Dart.
 *
 * The job is passed as the stream arguments, so a job starts when Dart subscribes
 * and ends with `endOfStream`. Cancellation arrives on the sibling
 * [BatchHandler] method channel, because closing the subscription is not enough
 * to stop a job that is already writing files.
 */
class BatchStreamHandler(private val context: Context, private val arguments: Any?) : BaseStreamHandler() {
    override val logTag = LOG_TAG

    private val jobId = (arguments as? Map<*, *>)?.get("jobId") as? String

    override fun onCall(args: Any?) {
        val job = BatchJobParser.parse(args)
        if (job == null) {
            error("batch-args", "missing or invalid job arguments", null)
            endOfStream()
            return
        }
        ioScope.launch {
            safeSuspend(
                function = {
                    BatchExecutor(
                        context = context,
                        job = job,
                        isCancelled = { cancelledJobs.contains(job.jobId) },
                        emit = { event -> success(event) },
                    ).run()
                },
            )
        }
    }

    override fun endOfStream() {
        jobId?.let(cancelledJobs::remove)
        super.endOfStream()
    }

    companion object {
        private val LOG_TAG = LogUtils.createTag<BatchStreamHandler>()
        const val CHANNEL = "deckers.thibault/aves/batch_stream"

        /** Job ids whose remaining items must be skipped. */
        val cancelledJobs: MutableSet<String> = ConcurrentHashMap.newKeySet()
    }
}
