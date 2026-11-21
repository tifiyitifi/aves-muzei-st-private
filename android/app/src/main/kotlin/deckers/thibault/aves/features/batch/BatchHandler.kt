package deckers.thibault.aves.features.batch

import android.content.Context
import android.util.Log
import androidx.core.net.toUri
import deckers.thibault.aves.channel.calls.Coresult.Companion.safe
import deckers.thibault.aves.channel.calls.Coresult.Companion.safeSuspend
import deckers.thibault.aves.features.media_ops.MediaOpPermissions
import deckers.thibault.aves.utils.LogUtils
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** Control channel for the batch engine: cancellation and result file operations. */
class BatchHandler(private val context: Context) : MethodChannel.MethodCallHandler {
    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "cancel" -> safe(call, result, ::cancel)
            "replaceWithResult" -> ioScope.launch { safeSuspend(call, result, ::replaceWithResult) }
            "deleteResult" -> ioScope.launch { safe(call, result, ::deleteResult) }
            "requestWriteAccess" -> ioScope.launch { safe(call, result, ::requestWriteAccess) }
            else -> result.notImplemented()
        }
    }

    private fun cancel(call: MethodCall, result: MethodChannel.Result) {
        val jobId = call.argument<String>("jobId")
        if (jobId == null) {
            result.error("cancel-args", "missing arguments", null)
            return
        }
        Log.i(LOG_TAG, "cancelling batch job $jobId")
        // Only a running job can be cancelled; a late request must not leave an
        // id behind that a reused id would inherit.
        if (BatchStreamHandler.activeJobs.contains(jobId)) {
            BatchStreamHandler.cancelledJobs.add(jobId)
        }
        result.success(null)
    }

    private suspend fun replaceWithResult(call: MethodCall, result: MethodChannel.Result) {
        val sourceUri = call.argument<String>("sourceUri")
        val resultUri = call.argument<String>("resultUri")
        if (sourceUri == null || resultUri == null) {
            result.error("replaceWithResult-args", "missing arguments", null)
            return
        }
        val outcome = BatchResultFiles.replace(context, sourceUri, resultUri)
        result.success(outcome)
    }

    private fun deleteResult(call: MethodCall, result: MethodChannel.Result) {
        val resultUri = call.argument<String>("resultUri")
        if (resultUri == null) {
            result.error("deleteResult-args", "missing arguments", null)
            return
        }
        result.success(BatchResultFiles.deleteResult(context, resultUri))
    }

    /**
     * Asks the system for write access to the files a replacement will touch.
     *
     * The run never modifies an original, so this is the only place the feature
     * needs the scoped-storage prompt. Requesting the whole selection at once
     * keeps it to one dialog instead of one per photo.
     */
    private fun requestWriteAccess(call: MethodCall, result: MethodChannel.Result) {
        val rawUris = call.argument<List<String>>("uris")
        val rawMimeTypes = call.argument<List<String>>("mimeTypes")
        if (rawUris.isNullOrEmpty()) {
            result.error("requestWriteAccess-args", "missing arguments", null)
            return
        }
        val granted = MediaOpPermissions(context, allowPrompt = true).ensureWriteAccess(
            uris = rawUris.map { it.toUri() },
            mimeTypes = rawMimeTypes ?: rawUris.map { "image/*" },
        )
        result.success(granted)
    }

    companion object {
        private val LOG_TAG = LogUtils.createTag<BatchHandler>()
        const val CHANNEL = "deckers.thibault/aves/batch"
    }
}
