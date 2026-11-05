package deckers.thibault.aves.features.batch

import android.content.Context
import kotlinx.coroutines.CancellationException

/**
 * Runs one job item by item.
 *
 * A failed item never aborts the run: the user asked for partial completion, so
 * interrupting a 20-image job leaves the finished copies finished and reports the
 * rest as failed/cancelled. Cancellation is checked before each item, never in
 * the middle of a write.
 */
class BatchExecutor(
    private val context: Context,
    private val job: BatchJob,
    private val isCancelled: () -> Boolean,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    suspend fun run() {
        emit(mapOf("type" to "jobStarted", "jobId" to job.jobId, "itemCount" to job.items.size))
        var done = 0
        var failed = 0
        var cancelled = false

        for ((index, item) in job.items.withIndex()) {
            if (isCancelled()) {
                cancelled = true
                break
            }
            emit(mapOf("type" to "itemStarted", "index" to index, "entryId" to item.entryId))
            try {
                val pipeline = BatchPipeline()
                for (tool in job.tools) {
                    BatchToolRegistry.get(tool.id)?.apply(pipeline, tool.settings)
                }
                val output = RefraBakeRunner(context).run(item, pipeline, job.output)
                if (output != null) {
                    done++
                    emit(
                        mapOf(
                            "type" to "itemDone",
                            "index" to index,
                            "entryId" to item.entryId,
                            "uri" to output.toString(),
                        ),
                    )
                } else {
                    failed++
                    emit(
                        mapOf(
                            "type" to "itemFailed",
                            "index" to index,
                            "entryId" to item.entryId,
                            "message" to "failed to write the processed image",
                        ),
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                failed++
                emit(
                    mapOf(
                        "type" to "itemFailed",
                        "index" to index,
                        "entryId" to item.entryId,
                        "message" to (e.message ?: e::class.java.simpleName),
                    ),
                )
            }
        }

        emit(
            mapOf(
                "type" to "jobDone",
                "jobId" to job.jobId,
                "done" to done,
                "failed" to failed,
                "cancelled" to (cancelled || isCancelled()),
            ),
        )
    }
}
