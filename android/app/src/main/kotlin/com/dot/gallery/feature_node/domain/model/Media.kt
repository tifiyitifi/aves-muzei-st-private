package com.dot.gallery.feature_node.domain.model

import android.content.ContentUris
import android.content.ContentResolver
import android.content.Context
import android.database.Cursor
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import com.dot.gallery.core.Constants
import com.dot.gallery.feature_node.presentation.util.getDate
import com.dot.gallery.feature_node.presentation.util.printError
import java.io.File
import java.util.Random

/**
 * Trimmed ReFra media model used by the editor port.
 *
 * Upstream backs this with Room entities and a repository; the fork editor only needs an
 * immutable descriptor of the staged copy it edits, so the shape is preserved while the
 * persistence concerns are left to Aves' own database.
 */
abstract class Media {

    abstract val id: Long
    abstract val label: String
    abstract val path: String
    abstract val relativePath: String
    abstract val timestamp: Long
    abstract val mimeType: String

    data class UriMedia(
        override val id: Long = 0,
        override val label: String,
        val uri: Uri,
        override val path: String,
        override val relativePath: String,
        override val timestamp: Long,
        override val mimeType: String,
        val size: Long = 0L,
        val fullDate: String = "",
    ) : Media()

    companion object {

        private const val TAG = "Media"

        /**
         * Reads the metadata the editor needs straight from the granted uri.
         *
         * The staged copy is a MediaStore row owned by this app, so a plain query (including
         * pending rows) is enough; unsupported columns fall back to sensible defaults.
         */
        fun createFromUri(context: Context?, uri: Uri): UriMedia? {
            val uriPath = uri.path ?: return null
            val isContent = uri.scheme == ContentResolver.SCHEME_CONTENT

            val extension = uri.toString().substringAfterLast(".")
            var mimeType: String? = if (isContent) context?.contentResolver?.getType(uri) else null
            if (mimeType == null) {
                mimeType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
                    ?: when (extension.lowercase()) {
                        "apng" -> "image/apng"
                        "jxl" -> "image/jxl"
                        else -> null
                    }
            }

            var timestamp = 0L
            var size = 0L
            var displayName: String? = null

            if (isContent && context != null) {
                try {
                    val projection = arrayOf(
                        MediaStore.MediaColumns.DISPLAY_NAME,
                        MediaStore.MediaColumns.SIZE,
                        MediaStore.MediaColumns.DATE_MODIFIED,
                        MediaStore.MediaColumns.MIME_TYPE,
                    )
                    val cursor: Cursor? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        val queryArgs = Bundle().apply {
                            putInt(MediaStore.QUERY_ARG_MATCH_PENDING, MediaStore.MATCH_INCLUDE)
                        }
                        context.contentResolver.query(uri, projection, queryArgs, null)
                    } else {
                        context.contentResolver.query(uri, projection, null, null, null)
                    }
                    cursor?.use { c ->
                        if (c.moveToFirst()) {
                            c.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                                .takeIf { it >= 0 }?.let { displayName = c.getString(it) }
                            c.getColumnIndex(MediaStore.MediaColumns.SIZE)
                                .takeIf { it >= 0 }?.let { size = c.getLong(it) }
                            c.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED)
                                .takeIf { it >= 0 }?.let { timestamp = c.getLong(it) }
                            if (mimeType == null) {
                                c.getColumnIndex(MediaStore.MediaColumns.MIME_TYPE)
                                    .takeIf { it >= 0 }?.let { mimeType = c.getString(it) }
                            }
                        }
                    }
                } catch (e: Exception) {
                    printError(TAG, "Failed to query media metadata for $uri", e)
                }
            } else {
                timestamp = try {
                    File(uriPath).lastModified()
                } catch (_: Exception) {
                    0L
                }
            }

            if (context != null) {
                try {
                    MediaMetadataRetriever().use { retriever ->
                        retriever.setDataSource(context, uri)
                        if (mimeType == null) {
                            mimeType = retriever.extractMetadata(
                                MediaMetadataRetriever.METADATA_KEY_MIMETYPE
                            )
                        }
                    }
                } catch (e: Exception) {
                    printError(TAG, "Failed to extract media metadata for $uri", e)
                }
            }

            val formattedDate = if (timestamp != 0L) timestamp.getDate(Constants.EXTENDED_DATE_FORMAT) else ""
            val resolvedId: Long = if (isContent) {
                try {
                    ContentUris.parseId(uri)
                } catch (_: Exception) {
                    Random(System.currentTimeMillis()).nextLong(-1000, 25600000)
                }
            } else {
                Random(System.currentTimeMillis()).nextLong(-1000, 25600000)
            }
            val label = displayName ?: uri.toString().substringAfterLast("/")
            return UriMedia(
                id = resolvedId,
                label = label,
                uri = uri,
                path = uriPath,
                relativePath = uriPath.substringBeforeLast("/"),
                timestamp = timestamp,
                mimeType = mimeType ?: "null",
                size = size,
                fullDate = formattedDate,
            )
        }
    }
}
