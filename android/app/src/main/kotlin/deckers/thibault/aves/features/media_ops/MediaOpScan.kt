package deckers.thibault.aves.features.media_ops

import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.provider.MediaStore
import android.util.Log
import deckers.thibault.aves.model.EntryFields
import deckers.thibault.aves.model.FieldMap
import deckers.thibault.aves.model.SourceEntry
import deckers.thibault.aves.storage.StorageUtils
import deckers.thibault.aves.utils.LogUtils
import deckers.thibault.aves.utils.UriUtils.tryParseId
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import kotlin.coroutines.resume

/**
 * Batched Media Store bookkeeping for the v2 pipeline.
 *
 * The legacy pipeline waits for one `scanFile` callback per entry and retries
 * with sleeps when the Media Store is slow, which costs seconds on a batch. Here
 * every path of a chunk is scanned in a single call, and the resulting entries
 * are turned into field maps without any additional round trip per file.
 */
object MediaOpScan {
    private val LOG_TAG = LogUtils.createTag<MediaOpScan>()

    /** Scanning is best effort: a silent scanner must not stall the whole operation. */
    private const val TIMEOUT_MILLIS = 15_000L

    private val DATE_PROJECTION = arrayOf(
        MediaStore.MediaColumns.DATE_ADDED,
        MediaStore.MediaColumns.DATE_MODIFIED,
    )

    /**
     * Scans [paths] in one call.
     *
     * @return one URI per path, in the same order; `null` when the scanner did not
     * report a usable entry (missing file, unsupported location, timeout)
     */
    suspend fun scan(context: Context, paths: List<String>, mimeTypes: List<String>): Array<Uri?> {
        if (paths.isEmpty()) return emptyArray()

        val results = arrayOfNulls<Uri>(paths.size)
        val indexByPath = HashMap<String, Int>(paths.size)
        paths.forEachIndexed { index, path -> indexByPath.putIfAbsent(path, index) }

        withTimeoutOrNull(TIMEOUT_MILLIS) {
            suspendCancellableCoroutine { cont ->
                var remaining = paths.size
                try {
                    MediaScannerConnection.scanFile(context, paths.toTypedArray(), mimeTypes.toTypedArray()) { path, uri ->
                        indexByPath[path]?.let { index -> results[index] = uri }
                        remaining -= 1
                        if (remaining <= 0 && cont.isActive) {
                            cont.resume(Unit)
                        }
                    }
                } catch (e: Exception) {
                    Log.w(LOG_TAG, "failed to scan ${paths.size} paths", e)
                    if (cont.isActive) {
                        cont.resume(Unit)
                    }
                }
            }
        }
        if (results.any { it == null }) {
            Log.w(LOG_TAG, "scanner resolved ${results.count { it != null }}/${paths.size} paths")
        }
        return results
    }

    /**
     * Field map for an entry that now lives at [path] under media store [uri].
     *
     * A single-row query only; the legacy pipeline ran the same query and then
     * overrode the date with the file timestamp anyway.
     */
    fun buildFields(context: Context, path: String, uri: Uri): FieldMap {
        val fields: FieldMap = hashMapOf(
            EntryFields.ORIGIN to SourceEntry.ORIGIN_MEDIA_STORE_CONTENT,
            EntryFields.URI to uri.toString(),
            EntryFields.CONTENT_ID to uri.tryParseId(),
            EntryFields.PATH to path,
        )
        try {
            context.contentResolver.query(uri, DATE_PROJECTION, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    cursor.getColumnIndex(MediaStore.MediaColumns.DATE_ADDED).takeIf { it != -1 }?.let {
                        fields[EntryFields.DATE_ADDED_SECS] = cursor.getInt(it)
                    }
                    cursor.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED).takeIf { it != -1 }?.let {
                        fields[EntryFields.DATE_MODIFIED_MILLIS] = cursor.getInt(it) * 1000L
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(LOG_TAG, "failed to query dates for uri=$uri", e)
        }
        fileModifiedDateMillis(path)?.let { fields[EntryFields.DATE_MODIFIED_MILLIS] = it }
        return fields
    }

    /** Field map for a path that is not indexed by the Media Store (e.g. a vault entry). */
    fun buildFileFields(context: Context, path: String): FieldMap {
        val uri = Uri.fromFile(File(path))
        return hashMapOf(
            EntryFields.ORIGIN to if (StorageUtils.isInVault(context, path)) SourceEntry.ORIGIN_VAULT else SourceEntry.ORIGIN_FILE,
            EntryFields.URI to uri.toString(),
            EntryFields.CONTENT_ID to null,
            EntryFields.PATH to path,
            EntryFields.DATE_MODIFIED_MILLIS to fileModifiedDateMillis(path),
        )
    }

    // the file timestamp is more precise than the Media Store one
    private fun fileModifiedDateMillis(path: String): Long? {
        return try {
            File(path).lastModified()
        } catch (_: SecurityException) {
            null
        }
    }
}
