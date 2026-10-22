package deckers.thibault.aves.model.provider

import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.util.Log
import deckers.thibault.aves.model.EntryFields
import deckers.thibault.aves.model.FieldMap
import deckers.thibault.aves.model.SourceEntry
import deckers.thibault.aves.storage.PathSegments
import deckers.thibault.aves.storage.StorageUtils
import deckers.thibault.aves.utils.LogUtils
import java.io.File

/**
 * The MediaStore reads the browse-only surface needs, and only those.
 *
 * The library stream (`MediaStoreImageProvider.fetchAll`) answers a different
 * question: it describes every row exactly, with two file stats per row and
 * embedded probes for the formats MediaStore misreports, and hands each row to
 * Dart on its own. That is the right shape for the import, which writes every
 * field, and the wrong one for browsing: a page of tiles needs none of it, and
 * paying for it per row is what made a first screen wait on a whole-library
 * pass.
 *
 * These reads are bounded and aggregate instead: a keyset-paged page of rows in
 * one reply (no per-row message, no file stats) and one pass that returns a
 * folder's count, size and cover rather than its rows.
 */
object BrowseMediaStore {
    private val LOG_TAG = LogUtils.createTag<BrowseMediaStore>()

    private val IMAGE_CONTENT_URI = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
    private val VIDEO_CONTENT_URI = MediaStore.Video.Media.EXTERNAL_CONTENT_URI

    /**
     * The date the browser sorts and sections by, and therefore the key a page
     * resumes from: capture, then modification, then addition.
     *
     * It has to be the exact expression the Dart side reads back out of a row
     * (`BrowseRow.bestDateMillis`), or a page boundary would skip or repeat the
     * rows whose dates disagree.
     */
    private const val SORT_DATE =
        "COALESCE(${MediaColumns.DATE_TAKEN} / 1000, ${MediaStore.MediaColumns.DATE_MODIFIED}, ${MediaStore.MediaColumns.DATE_ADDED})"

    private val PAGE_PROJECTION_BASE = arrayOf(
        MediaStore.MediaColumns._ID,
        MediaStore.MediaColumns.DATA,
        MediaStore.MediaColumns.MIME_TYPE,
        MediaStore.MediaColumns.SIZE,
        MediaStore.MediaColumns.WIDTH,
        MediaStore.MediaColumns.HEIGHT,
        MediaStore.MediaColumns.DATE_ADDED,
        MediaStore.MediaColumns.DATE_MODIFIED,
        MediaColumns.DATE_TAKEN,
    )

    // `IS_TRASHED` is only available on API 30+; the rows are filtered by the
    // selection the provider applies, not by a typed argument, so the column has
    // to be read here.
    private val PAGE_PROJECTION_TRASHED = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) arrayOf(
        MediaStore.MediaColumns.IS_TRASHED,
    ) else emptyArray()

    private val IMAGE_PROJECTION = arrayOf(
        *PAGE_PROJECTION_BASE,
        MediaColumns.ORIENTATION,
        *PAGE_PROJECTION_TRASHED,
    )

    private val VIDEO_PROJECTION = arrayOf(
        *PAGE_PROJECTION_BASE,
        MediaColumns.DURATION,
        // `ORIENTATION` was only available for videos before Android 10 (API 29)
        *if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) arrayOf(
            MediaStore.MediaColumns.ORIENTATION,
        ) else emptyArray(),
        *PAGE_PROJECTION_TRASHED,
    )

    /**
     * One page of media rows, newest first.
     *
     * Both collections are read and merged, so a page mixes images and videos in
     * one chronological order. The keyset cursor is the last row of the previous
     * page, so a page costs one bounded query per collection instead of a walk
     * over everything newer than it.
     */
    fun fetchPage(
        context: Context,
        limit: Int,
        beforeSortDateSecs: Long?,
        beforeId: Long?,
        directory: String?,
    ): Map<String, Any?> {
        val candidates = ArrayList<PageRow>(limit * 2)
        val imagesTruncated = fetchPageFrom(context, IMAGE_CONTENT_URI, IMAGE_PROJECTION, limit, beforeSortDateSecs, beforeId, directory, candidates)
        val videosTruncated = fetchPageFrom(context, VIDEO_CONTENT_URI, VIDEO_PROJECTION, limit, beforeSortDateSecs, beforeId, directory, candidates)
        candidates.sortWith(PAGE_ORDER)
        return mapOf(
            "rows" to candidates.take(limit).map { it.fields },
            // Either collection filling its own limit means the merged page may
            // have been cut, even when the merge itself did not exceed it.
            "hasMore" to (imagesTruncated || videosTruncated || candidates.size > limit),
        )
    }

    /**
     * Every folder MediaStore reports, with its count, size and newest row.
     *
     * The rows are counted here instead of being handed over: a folder's summary
     * is what the album grid shows, so the only row that has to cross the
     * channel is the one used as the cover. Grouping is by the row's parent
     * directory, which is exactly the key the browser's album list uses.
     */
    fun fetchAlbumSummaries(context: Context): List<Map<String, Any?>> {
        val buckets = LinkedHashMap<String, AlbumBucket>()
        fetchAlbumsFrom(context, IMAGE_CONTENT_URI, IMAGE_PROJECTION, buckets)
        fetchAlbumsFrom(context, VIDEO_CONTENT_URI, VIDEO_PROJECTION, buckets)
        return buckets.values.map { it.toMap() }
    }

    private class PageRow(val sortDateSecs: Long, val id: Long, val fields: FieldMap)

    private class AlbumBucket(val directory: String) {
        var count = 0
        var sizeBytes = 0L
        var cover: FieldMap? = null
        var coverSortDateSecs = Long.MIN_VALUE

        fun toMap(): Map<String, Any?> = mapOf(
            "directory" to directory,
            "count" to count,
            "sizeBytes" to sizeBytes,
            "cover" to cover,
        )
    }

    private class Columns(cursor: Cursor) {
        val id = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
        val path = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
        val mimeType = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
        val size = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
        val width = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.WIDTH)
        val height = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.HEIGHT)
        val dateAdded = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_ADDED)
        val dateModified = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
        val dateTaken = cursor.getColumnIndex(MediaColumns.DATE_TAKEN)
        val orientation = cursor.getColumnIndex(MediaColumns.ORIENTATION)
        val duration = cursor.getColumnIndex(MediaColumns.DURATION)

        // `IS_TRASHED` is only available on API 30+
        val trashed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) cursor.getColumnIndex(MediaStore.MediaColumns.IS_TRASHED) else -1
    }

    private val PAGE_ORDER = compareByDescending<PageRow> { it.sortDateSecs }.thenByDescending { it.id }

    private fun fetchPageFrom(
        context: Context,
        contentUri: Uri,
        projection: Array<String>,
        limit: Int,
        beforeSortDateSecs: Long?,
        beforeId: Long?,
        directory: String?,
        out: MutableList<PageRow>,
    ): Boolean {
        val conditions = ArrayList<String>()
        val selectionArgs = ArrayList<String>()
        if (directory != null) {
            val relativePathDirectory = StorageUtils.ensureTrailingSeparator(directory)
            val relativePath = PathSegments(context, relativePathDirectory).relativeDir
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && relativePath != null) {
                conditions.add("${MediaStore.MediaColumns.RELATIVE_PATH} = ?")
                selectionArgs.add(relativePath)
            }
            conditions.add("${MediaStore.MediaColumns.DATA} LIKE ?")
            selectionArgs.add("$relativePathDirectory%")
        }
        if (beforeSortDateSecs != null && beforeId != null) {
            // "After the cursor" is the sort key spelled out with plain column
            // comparisons. MediaProvider resolves a selection against its own
            // columns and drops one it cannot (a `COALESCE(...)` in it is
            // dropped *silently*, and every page would then answer the first
            // page again), so the key is written out instead of reused:
            //   value = COALESCE(date_taken / 1000, date_modified, date_added)
            //   after = value < V OR (value = V AND _id < ID)
            val takenMillis = beforeSortDateSecs * 1000
            val dateTaken = MediaColumns.DATE_TAKEN
            val dateModified = MediaStore.MediaColumns.DATE_MODIFIED
            val dateAdded = MediaStore.MediaColumns.DATE_ADDED
            val id = MediaStore.MediaColumns._ID
            conditions.add(
                "(" +
                    // value < V
                    "($dateTaken IS NOT NULL AND $dateTaken < ?)" +
                    " OR ($dateTaken IS NULL AND $dateModified IS NOT NULL AND $dateModified < ?)" +
                    " OR ($dateTaken IS NULL AND $dateModified IS NULL AND $dateAdded < ?)" +
                    // value = V, and the row is behind the cursor's id
                    " OR ($id < ? AND (" +
                    "($dateTaken IS NOT NULL AND $dateTaken >= ? AND $dateTaken < ?)" +
                    " OR ($dateTaken IS NULL AND $dateModified IS NOT NULL AND $dateModified = ?)" +
                    " OR ($dateTaken IS NULL AND $dateModified IS NULL AND $dateAdded = ?)" +
                    "))" +
                    ")",
            )
            selectionArgs.add(takenMillis.toString())
            selectionArgs.add(beforeSortDateSecs.toString())
            selectionArgs.add(beforeSortDateSecs.toString())
            selectionArgs.add(beforeId.toString())
            selectionArgs.add(takenMillis.toString())
            // `date_taken / 1000 == V` is a half-open range in milliseconds
            selectionArgs.add((takenMillis + 1000).toString())
            selectionArgs.add(beforeSortDateSecs.toString())
            selectionArgs.add(beforeSortDateSecs.toString())
        }
        val selection = conditions.joinToString(" AND ").takeIf { it.isNotEmpty() }
        // A page is bounded by the provider, not by a `LIMIT` written into the
        // sort order: MediaProvider validates that argument and rejects the
        // token. The bundle form carries the limit where the provider reads it,
        // and the sort-order form is only kept for the API levels that predate
        // it (their provider is plain SQLite and accepts it).
        val sortOrder = "$SORT_DATE DESC, ${MediaStore.MediaColumns._ID} DESC"
        // Below Android 10 the relative-path filter does not exist and `LIKE`
        // also matches subfolders: the parent is checked by string, not by stat.
        val parentCheck = if (directory != null && Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) StorageUtils.removeTrailingSeparator(directory) else null

        var read = 0
        Log.d(LOG_TAG, "fetching a browse page uri=$contentUri limit=$limit selection=$selection args=${selectionArgs.toList()}")
        try {
            val cursor = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val queryArgs = Bundle().apply {
                    selection?.let { putString(ContentResolver.QUERY_ARG_SQL_SELECTION, it) }
                    if (selectionArgs.isNotEmpty()) putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, selectionArgs.toTypedArray())
                    putString(ContentResolver.QUERY_ARG_SQL_SORT_ORDER, sortOrder)
                    putString(ContentResolver.QUERY_ARG_SQL_LIMIT, limit.toString())
                }
                context.contentResolver.query(contentUri, projection, queryArgs, null)
            } else {
                context.contentResolver.query(contentUri, projection, selection, selectionArgs.toTypedArray(), "$sortOrder LIMIT $limit")
            }
            cursor?.use {
                val columns = Columns(it)
                while (it.moveToNext()) {
                    read++
                    if (columns.trashed != -1 && it.getInt(columns.trashed) != 0) continue
                    val id = it.getLong(columns.id)
                    val path = it.getString(columns.path) ?: continue
                    if (parentCheck != null && File(path).parent != parentCheck) continue
                    val mimeType = it.getString(columns.mimeType) ?: continue
                    out.add(PageRow(sortDateSecs(it, columns), id, lightFields(it, columns, contentUri, id, path, mimeType)))
                }
            }
        } catch (e: Exception) {
            Log.e(LOG_TAG, "failed to fetch a browse page for uri=$contentUri", e)
        }
        // Whether the provider cut the page is read from what it returned, not
        // from what was kept: a page whose rows were all trashed is still a full
        // page, and claiming the end of the library there would hide every row
        // behind it.
        return read >= limit
    }

    private fun fetchAlbumsFrom(context: Context, contentUri: Uri, projection: Array<String>, buckets: MutableMap<String, AlbumBucket>) {
        // Newest first, so a folder's first row is usually its cover. The two
        // collections are still merged by date: a video can be newer than every
        // image of the same folder.
        val sortOrder = "$SORT_DATE DESC, ${MediaStore.MediaColumns._ID} DESC"
        try {
            context.contentResolver.query(contentUri, projection, null, null, sortOrder)?.use { cursor ->
                val columns = Columns(cursor)
                while (cursor.moveToNext()) {
                    if (columns.trashed != -1 && cursor.getInt(columns.trashed) != 0) continue
                    val path = cursor.getString(columns.path) ?: continue
                    val directory = File(path).parent ?: continue
                    val sortDate = sortDateSecs(cursor, columns)
                    val bucket = buckets.getOrPut(directory) { AlbumBucket(directory) }
                    bucket.count++
                    bucket.sizeBytes += cursor.getLong(columns.size)
                    if (bucket.cover == null || sortDate > bucket.coverSortDateSecs) {
                        val id = cursor.getLong(columns.id)
                        val mimeType = cursor.getString(columns.mimeType) ?: continue
                        bucket.cover = lightFields(cursor, columns, contentUri, id, path, mimeType)
                        bucket.coverSortDateSecs = sortDate
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(LOG_TAG, "failed to fetch browse album summaries for uri=$contentUri", e)
        }
    }

    private fun sortDateSecs(cursor: Cursor, columns: Columns): Long = when {
        // Mirrors the SQL expression above: a present-but-zero DATE_TAKEN wins,
        // which is what SQLite's COALESCE sees too.
        columns.dateTaken != -1 && !cursor.isNull(columns.dateTaken) -> cursor.getLong(columns.dateTaken) / 1000
        !cursor.isNull(columns.dateModified) -> cursor.getLong(columns.dateModified)
        !cursor.isNull(columns.dateAdded) -> cursor.getLong(columns.dateAdded)
        else -> 0L
    }

    /**
     * The fields a tile needs, without the exactness the import pays for: no
     * file stats, no embedded probes. Everything else matches the stream's row
     * shape, so both feed the same `AvesEntry` on the Dart side.
     */
    private fun lightFields(cursor: Cursor, columns: Columns, contentUri: Uri, id: Long, path: String, mimeType: String): FieldMap = hashMapOf(
        EntryFields.ORIGIN to SourceEntry.ORIGIN_MEDIA_STORE_CONTENT,
        EntryFields.URI to ContentUris.withAppendedId(contentUri, id).toString(),
        EntryFields.PATH to path,
        EntryFields.SOURCE_MIME_TYPE to mimeType,
        EntryFields.WIDTH to cursor.getInt(columns.width),
        EntryFields.HEIGHT to cursor.getInt(columns.height),
        EntryFields.SOURCE_ROTATION_DEGREES to if (columns.orientation != -1) cursor.getInt(columns.orientation) else 0,
        EntryFields.SIZE_BYTES to cursor.getLong(columns.size),
        EntryFields.DATE_ADDED_SECS to cursor.getLong(columns.dateAdded),
        EntryFields.DATE_MODIFIED_MILLIS to cursor.getLong(columns.dateModified) * 1000L,
        EntryFields.SOURCE_DATE_TAKEN_MILLIS to if (columns.dateTaken != -1 && !cursor.isNull(columns.dateTaken)) cursor.getLong(columns.dateTaken) else null,
        EntryFields.DURATION_MILLIS to if (columns.duration != -1) cursor.getLong(columns.duration) else 0L,
        EntryFields.CONTENT_ID to id,
    )
}
