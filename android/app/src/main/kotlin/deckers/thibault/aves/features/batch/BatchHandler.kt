package deckers.thibault.aves.features.batch

import android.util.Log
import deckers.thibault.aves.channel.calls.Coresult.Companion.safe
import deckers.thibault.aves.utils.LogUtils
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Control channel for the batch stream (currently cancellation only). */
class BatchHandler : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "cancel" -> safe(call, result, ::cancel)
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
        BatchStreamHandler.cancelledJobs.add(jobId)
        result.success(null)
    }

    companion object {
        private val LOG_TAG = LogUtils.createTag<BatchHandler>()
        const val CHANNEL = "deckers.thibault/aves/batch"
    }
}
