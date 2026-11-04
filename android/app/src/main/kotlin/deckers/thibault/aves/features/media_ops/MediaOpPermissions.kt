package deckers.thibault.aves.features.media_ops

import android.app.Activity
import android.content.Context
import android.net.Uri
import android.os.Build
import android.util.Log
import deckers.thibault.aves.storage.apis.MediaStorePermissions
import deckers.thibault.aves.utils.LogUtils

/**
 * Lazily escalates a refused Media Store write to one system access request.
 *
 * The operation starts on the fastest path and asks nothing. Only when the Media
 * Store refuses an update does it request access, for the whole remaining batch
 * and at most once per operation. A denial or an unavailable request is
 * remembered for the rest of the operation, so the batch degrades quietly
 * instead of prompting per file.
 */
class MediaOpPermissions(
    private val context: Context,
    private val allowPrompt: Boolean,
) {
    enum class Outcome(val key: String) {
        GRANTED("granted"),
        DENIED("denied"),
        UNAVAILABLE("unavailable"),
    }

    private var outcome: Outcome? = null

    private var reported = false

    /**
     * Requests write access to [uris] unless a decision was already made.
     *
     * @return whether the Media Store may be retried
     */
    fun ensureWriteAccess(uris: List<Uri>, mimeTypes: List<String>): Boolean {
        outcome?.let { return it == Outcome.GRANTED }

        // model URIs only: a write request rejects anything the Media Store cannot resolve
        val contentUris = ArrayList<Uri>(uris.size)
        val contentMimeTypes = ArrayList<String>(mimeTypes.size)
        uris.forEachIndexed { index, uri ->
            if (uri.scheme == "content") {
                contentUris.add(uri)
                contentMimeTypes.add(mimeTypes.getOrElse(index) { "*/*" })
            }
        }
        val requestUris = contentUris.take(MediaOpPlan.MAX_BULK_URIS)
        val requestMimeTypes = contentMimeTypes.take(requestUris.size)

        val activity = context as? Activity
        val activityReady = activity != null && !activity.isFinishing && !activity.isDestroyed
        if (!MediaOpPlan.canRequestPrompt(allowPrompt, Build.VERSION.SDK_INT, requestUris.size, activityReady)) {
            outcome = Outcome.UNAVAILABLE
            return false
        }

        outcome = try {
            if (MediaStorePermissions.requestFileAccess(activity!!, requestUris, requestMimeTypes)) {
                Outcome.GRANTED
            } else {
                Outcome.DENIED
            }
        } catch (e: Exception) {
            // e.g. `TransactionTooLargeException` or a provider that cannot build the request
            Log.w(LOG_TAG, "failed to request write access for ${requestUris.size} uris", e)
            Outcome.UNAVAILABLE
        }
        Log.i(LOG_TAG, "write access request for ${requestUris.size} uris yielded ${outcome?.key}")
        return outcome == Outcome.GRANTED
    }

    /**
     * Outcome to report on the next event, or `null` when there is nothing new.
     *
     * Reporting is separate from deciding because the event that carries the
     * outcome may be emitted after a batched scan.
     */
    fun consumeReport(): String? {
        if (reported) return null
        val value = outcome ?: return null
        reported = true
        return value.key
    }

    companion object {
        private val LOG_TAG = LogUtils.createTag<MediaOpPermissions>()
    }
}
