package deckers.thibault.aves.features.batch

import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import androidx.core.net.toUri
import com.dot.gallery.core.util.ext.overrideImageStreaming
import java.io.File

/**
 * The two file operations a recorded batch result can perform on demand.
 *
 * A run never touches an original; only an explicit "replace" or "delete" from
 * the results view does, and both go through the MediaStore so the app's rows and
 * the scanner stay consistent.
 */
object BatchResultFiles {

    /**
     * Overwrites [sourceUri] with the bytes of [resultUri].
     *
     * The write goes through [overrideImageStreaming], which keeps the source
     * row's date columns and restores the original bytes if the write fails. When
     * the result uses another format, the source row takes the result's name and
     * MIME type so the file never claims an extension its bytes do not have. The
     * result file is consumed on success.
     */
    suspend fun replace(context: Context, sourceUri: String, resultUri: String): Boolean {
        val source = sourceUri.toUri()
        val result = resultUri.toUri()
        val resolver = context.contentResolver
        val resultInfo = query(resolver, result) ?: return false
        val sourceInfo = query(resolver, source)

        val staging = File.createTempFile("batch-replace-", ".tmp", context.cacheDir)
        val replaced = resolver.overrideImageStreaming(source, staging) { fd ->
            runCatching {
                val input = resolver.openInputStream(result) ?: return@runCatching false
                input.use {
                    // `fd` is a raw descriptor owned by the caller. Wrap it only
                    // to duplicate it, then close our copy and leave the caller's
                    // descriptor alone; closing both used to close one fd twice.
                    val dup = ParcelFileDescriptor.fromFd(fd).dup()
                    ParcelFileDescriptor.AutoCloseOutputStream(dup).use { output ->
                        it.copyTo(output)
                        output.flush()
                        output.fd.sync()
                    }
                }
                true
            }.getOrDefault(false)
        }
        if (!replaced) return false

        val renamed = if (resultInfo.displayName != sourceInfo?.displayName) {
            runCatching {
                resolver.update(
                    source,
                    ContentValues().apply {
                        put(MediaStore.MediaColumns.DISPLAY_NAME, resultInfo.displayName)
                        put(MediaStore.MediaColumns.MIME_TYPE, resultInfo.mimeType)
                    },
                    null,
                    null,
                )
                true
            }.getOrDefault(false)
        } else {
            true
        }

        // The result was consumed; a copy in the recycle bin would only be noise.
        // Both steps must report success: a row is deleted on the Dart side only
        // when the file was really consumed, so a failed rename or delete keeps
        // the result actionable instead of leaving an orphan file or a stale name.
        val consumed = runCatching { resolver.delete(result, null, null) > 0 }.getOrDefault(false)
        return renamed && consumed
    }

    /** Deletes a result file permanently. */
    fun deleteResult(context: Context, resultUri: String): Boolean =
        runCatching { context.contentResolver.delete(resultUri.toUri(), null, null) > 0 }.getOrDefault(false)

    private data class FileInfo(val displayName: String, val mimeType: String)

    private fun query(resolver: ContentResolver, uri: Uri): FileInfo? = runCatching {
        resolver.query(
            uri,
            arrayOf(MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.MIME_TYPE),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                FileInfo(
                    displayName = cursor.getString(0) ?: "",
                    mimeType = cursor.getString(1) ?: "",
                )
            } else {
                null
            }
        }
    }.getOrNull()
}
