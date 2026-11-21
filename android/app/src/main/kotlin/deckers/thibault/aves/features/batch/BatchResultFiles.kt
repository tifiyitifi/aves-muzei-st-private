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
     * Outcomes of [replace], mirrored by `BatchReplaceOutcome` on the Dart side.
     *
     * The write and the cleanup are separate facts: once the source bytes are
     * replaced the change cannot be undone, so a failed cleanup must not be
     * reported as "nothing happened".
     */
    object Outcome {
        const val FAILED = "failed"
        const val REPLACED = "replaced"
        const val REPLACED_CLEANUP_FAILED = "replacedCleanupFailed"
    }

    /**
     * Overwrites [sourceUri] with the bytes of [resultUri].
     *
     * The write goes through [overrideImageStreaming], which keeps the source
     * row's date columns and restores the original bytes if the write fails. When
     * the result uses another name or format, the source row takes the result's
     * name and MIME type so the file never claims an extension its bytes do not
     * have. The result file is consumed on success.
     */
    suspend fun replace(context: Context, sourceUri: String, resultUri: String): String {
        val source = sourceUri.toUri()
        val result = resultUri.toUri()
        val resolver = context.contentResolver
        val resultInfo = query(resolver, result) ?: return Outcome.FAILED
        val sourceInfo = query(resolver, source)

        val staging = File.createTempFile("batch-replace-", ".tmp", context.cacheDir)
        val replaced = resolver.overrideImageStreaming(source, staging) { fd ->
            runCatching {
                val input = resolver.openInputStream(result) ?: return@runCatching false
                input.use {
                    // `fd` is a raw descriptor owned by `overrideImageStreaming`,
                    // which closes it after this callback. `fromFd` transfers
                    // ownership to the wrapper, so take it back with `detachFd`
                    // (which does not close it) and write through an independent
                    // duplicate. Closing the wrapper instead would close the
                    // caller's descriptor, and leaving it attached would close it
                    // a second time when the wrapper is finalized.
                    val wrapper = ParcelFileDescriptor.fromFd(fd)
                    val dup = try {
                        wrapper.dup()
                    } finally {
                        wrapper.detachFd()
                    }
                    ParcelFileDescriptor.AutoCloseOutputStream(dup).use { output ->
                        it.copyTo(output)
                        output.flush()
                        output.fd.sync()
                    }
                }
                true
            }.getOrDefault(false)
        }
        if (!replaced) return Outcome.FAILED

        val renamed = if (resultInfo.displayName != sourceInfo?.displayName || resultInfo.mimeType != sourceInfo?.mimeType) {
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
        // A failed delete leaves a file the row can still point at, so it is
        // retried instead of silently losing track of it.
        val consumed = runCatching { resolver.delete(result, null, null) > 0 }.getOrDefault(false)
        return if (renamed && consumed) Outcome.REPLACED else Outcome.REPLACED_CLEANUP_FAILED
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
