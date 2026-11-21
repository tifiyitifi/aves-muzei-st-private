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
        // Register before the launch body runs, so a cancel arriving right after
        // the subscription is not lost to a race.
        jobId?.let(activeJobs::add)
        ioScope.launch {
            try {
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
            } finally {
                // The job is over: its id no longer means anything, so a late
                // cancel or a stale subscription cannot restart it.
                jobId?.let {
                    activeJobs.remove(it)
                    cancelledJobs.remove(it)
                }
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        // Closing the subscription does not stop a job that is already writing.
        // Mark it cancelled so the executor stops before the next item; only a
        // job that really ended clears its id. Clearing it here used to revoke a
        // cancellation that had just been requested.
        jobId?.let { if (activeJobs.contains(it)) cancelledJobs.add(it) }
        super.onCancel(arguments)
    }

    companion object {
        private val LOG_TAG = LogUtils.createTag<BatchStreamHandler>()
        const val CHANNEL = "deckers.thibault/aves/batch_stream"

        /** Job ids whose remaining items must be skipped. */
        val cancelledJobs: MutableSet<String> = ConcurrentHashMap.newKeySet()

        /** Job ids a stream handler is still running; cancel may only target these. */
        val activeJobs: MutableSet<String> = ConcurrentHashMap.newKeySet()
    }
}
