package deckers.thibault.aves.storage

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import com.commonsware.cwac.document.DocumentFileCompat
import deckers.thibault.aves.storage.apis.MediaStorePermissions
import deckers.thibault.aves.storage.apis.SafPermissions
import deckers.thibault.aves.utils.LogUtils
import java.io.File

/**
 * Renames one album folder in place.
 *
 * Every strategy keeps the Media Store row ids, which favourites, covers, pins
 * and bookmarks are keyed on. They are tried in order of how completely they
 * move the folder:
 *
 * 1. **app-private storage** (the vault): a plain `File.renameTo`. The app owns
 *    the tree outright, and nothing outside it indexes the folder.
 * 2. **SAF**: a document rename. `DocumentsProvider` moves the folder with its
 *    subfolders and sidecars, and updates the Media Store itself.
 * 3. **Media Store**: one `RELATIVE_PATH` update per collection, moving the
 *    direct children only and keeping their ids. Attempted only when writing
 *    needs no interactive grant: prompting for it costs one system dialog per
 *    batch and caps the request at 2000 URIs.
 *
 * Anything else answers `unsupported`, and the caller keeps its batched move.
 * A folder with the destination name already existing is never renamed into:
 * only the batched move merges (and renames conflicting files) correctly.
 */
object AlbumRename {
    private val LOG_TAG = LogUtils.createTag<AlbumRename>()

    private const val STRATEGY_APP_PRIVATE = "appPrivate"
    private const val STRATEGY_SAF = "saf"
    private const val STRATEGY_MEDIA_STORE_BULK = "mediaStoreBulk"

    private const val REASON_INVALID_NAME = "invalidName"
    private const val REASON_UNSUPPORTED = "unsupported"
    private const val REASON_MISSING = "missing"
    private const val REASON_DESTINATION_EXISTS = "destinationExists"
    private const val REASON_PARTIAL = "partial"
    private const val REASON_FAILED = "failed"

    /** Renames the folder `oldDir` to `newName` within the same parent directory. */
    fun renameAlbumDirectory(context: Context, oldDir: String, newName: String): Map<String, Any?> {
        if (newName.isEmpty() || newName.contains('/') || newName == "." || newName == "..") {
            return failure(REASON_INVALID_NAME)
        }

        val oldFile = File(oldDir)
        val parent = oldFile.parentFile ?: return failure(REASON_MISSING)
        if (!oldFile.isDirectory) return failure(REASON_MISSING)
        val newFile = File(parent, newName)
        // A case-only rename would be a silent no-op on a case-insensitive
        // filesystem and looks like "already exists" to a plain check, so the
        // existence test is skipped for it and each strategy does two steps.
        val caseOnly = oldFile.name != newName && oldFile.name.equals(newName, ignoreCase = true)

        if (StorageUtils.isInAvesAppStorage(context, oldDir)) {
            return renameInAppStorage(oldFile, parent, newFile, caseOnly)
        }

        // `getAccessibleDirs` also lists app-private and legacy-writable
        // directories, so it cannot tell a real SAF grant from the rest.
        val oldDirWithSeparator = StorageUtils.ensureTrailingSeparator(oldDir)
        if (SafPermissions.getGrantedDirectories(context).any { oldDirWithSeparator.startsWith(it) }) {
            return renameWithSaf(context, oldFile, newFile, caseOnly)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            renameWithMediaStore(context, oldFile, newFile, caseOnly)?.let { return it }
        }

        return failure(REASON_UNSUPPORTED)
    }

    private fun renameInAppStorage(oldFile: File, parent: File, newFile: File, caseOnly: Boolean): Map<String, Any?> {
        if (!caseOnly && newFile.exists()) return failure(REASON_DESTINATION_EXISTS)

        val renamed = try {
            if (caseOnly) renameThroughTemporary(oldFile, parent, newFile) else oldFile.renameTo(newFile)
        } catch (e: Exception) {
            Log.w(LOG_TAG, "failed to rename ${oldFile.path}", e)
            false
        }

        if (!renamed) return failure(REASON_FAILED)
        Log.d(LOG_TAG, "renamed ${oldFile.path} to ${newFile.path} via app storage")
        return success(STRATEGY_APP_PRIVATE, newFile.path, movedRows = -1)
    }

    private fun renameWithSaf(context: Context, oldFile: File, newFile: File, caseOnly: Boolean): Map<String, Any?> {
        val source = try {
            StorageUtils.getDocumentFileForExistingDirectory(context, oldFile.path)
        } catch (e: Exception) {
            Log.w(LOG_TAG, "failed to get document for path=${oldFile.path}", e)
            null
        } ?: return failure(REASON_FAILED)

        if (!caseOnly && hasDestination(source, newFile)) return failure(REASON_DESTINATION_EXISTS)

        val renamed = try {
            if (caseOnly) renameDocumentThroughTemporary(source, oldFile.name, newFile.name) else source.renameTo(newFile.name)
        } catch (e: Exception) {
            Log.w(LOG_TAG, "failed to rename document at path=${oldFile.path}", e)
            false
        }
        if (!renamed) return failure(REASON_FAILED)

        // A provider may normalize the name (e.g. a case-insensitive FAT card
        // keeps the old casing), which would leave the album under its old
        // name: report that instead of pretending it followed the request.
        val effectiveName = source.name
        if (effectiveName != newFile.name) {
            Log.w(LOG_TAG, "renamed document at path=${oldFile.path} to name=$effectiveName instead of ${newFile.name}")
            return failure(REASON_FAILED)
        }

        Log.d(LOG_TAG, "renamed ${oldFile.path} to ${newFile.path} via SAF")
        return success(STRATEGY_SAF, newFile.path, movedRows = -1)
    }

    /**
     * Whether the destination is already taken, looking at the parent document
     * when it is available so siblings differing only in case are found too.
     * A case-insensitive filesystem would otherwise silently rename into the
     * existing folder, while a case-sensitive one would ask the provider to
     * create a second folder that differs only by case.
     */
    private fun hasDestination(source: DocumentFileCompat, newFile: File): Boolean {
        if (File(newFile.path).exists()) return true

        val parent = try {
            source.parentFile
        } catch (e: Exception) {
            Log.w(LOG_TAG, "failed to get parent of ${source.uri}", e)
            null
        } ?: return false

        val sourceUri = source.uri
        return parent.listFiles()?.any { it.uri != sourceUri && it.name.equals(newFile.name, ignoreCase = true) } ?: false
    }

    /**
     * Moves the direct children of the folder with one Media Store update per
     * collection. Answers null when the strategy does not apply, so the caller
     * can fall through to `unsupported`.
     */
    @RequiresApi(Build.VERSION_CODES.Q)
    private fun renameWithMediaStore(context: Context, oldFile: File, newFile: File, caseOnly: Boolean): Map<String, Any?>? {
        // A case-only rename is not a `RELATIVE_PATH` change the Media Store can
        // tell apart from the old one on every filesystem, and the batched move
        // cannot express it either: leave it to a SAF grant instead of half
        // applying it.
        if (caseOnly) return null
        if (!canWriteWithoutPrompt(context)) return null
        // Moving rows out of another app's media directory throws
        // `IllegalArgumentException: Changing ownership ... not allowed`.
        if (StorageUtils.isInAppMediaStorage(context, oldFile.path)) return null

        val oldSegments = PathSegments(context, oldFile.path)
        val newSegments = PathSegments(context, newFile.path)
        val volumePath = oldSegments.volumePath ?: return null
        if (newSegments.volumePath != volumePath) return null
        val oldRelativeDir = oldSegments.relativeDir ?: return null
        val newRelativeDir = newSegments.relativeDir ?: return null

        if (File(newFile.path).exists()) return failure(REASON_DESTINATION_EXISTS)

        val volumeName = try {
            StorageUtils.getMediaStoreVolumeName(context, oldFile.path)
        } catch (e: Exception) {
            Log.w(LOG_TAG, "failed to resolve media store volume for path=${oldFile.path}", e)
            return null
        }
        val collections = listOf(
            MediaStore.Images.Media.getContentUri(volumeName),
            MediaStore.Video.Media.getContentUri(volumeName),
            MediaStore.Audio.Media.getContentUri(volumeName),
            MediaStore.Downloads.getContentUri(volumeName),
        )
        val selection = "${MediaStore.MediaColumns.RELATIVE_PATH} = ?"
        val oldArgs = arrayOf(oldRelativeDir)

        // Check every collection before moving any row: a destination that
        // already holds entries has to be merged into, which needs the batched
        // move's conflict handling, and a half-done bulk would leave the album
        // split across two folders.
        val before = collections.associateWith { countUnder(context, it, selection, oldArgs) }
        val expected = before.values.sum()
        if (expected == 0) return null
        if (collections.any { countUnder(context, it, selection, arrayOf(newRelativeDir)) > 0 }) {
            return failure(REASON_DESTINATION_EXISTS)
        }

        val values = ContentValues().apply { put(MediaStore.MediaColumns.RELATIVE_PATH, newRelativeDir) }
        var moved = 0
        for (collection in collections) {
            if (before[collection] == 0) continue
            moved += try {
                context.contentResolver.update(collection, values, selection, oldArgs)
            } catch (e: Exception) {
                Log.w(LOG_TAG, "failed to bulk move rows in collection=$collection", e)
                0
            }
        }

        // Comparing counts, rather than trusting the update results, also
        // covers providers that report rows they did not move.
        val remaining = collections.sumOf { countUnder(context, it, selection, oldArgs) }
        Log.d(LOG_TAG, "media store bulk move of ${oldFile.path}: expected=$expected moved=$moved remaining=$remaining")
        if (remaining == 0) {
            // The rows moved but the folder itself did not: remove it when the
            // move left it empty. `delete` refuses a non-empty directory, so an
            // unindexed sidecar keeps the folder instead of being lost.
            if (oldFile.delete()) {
                Log.d(LOG_TAG, "removed empty album folder ${oldFile.path}")
            }
            return success(STRATEGY_MEDIA_STORE_BULK, newFile.path, movedRows = moved)
        }
        if (moved == 0) return failure(REASON_FAILED)

        // A collection refused after another one had moved its rows. Put those
        // back, so the batched move finds every file at the path the database
        // records instead of one half of the album at the destination.
        val newArgs = arrayOf(newRelativeDir)
        val rollbackValues = ContentValues().apply { put(MediaStore.MediaColumns.RELATIVE_PATH, oldRelativeDir) }
        for (collection in collections) {
            if (countUnder(context, collection, selection, newArgs) == 0) continue
            try {
                context.contentResolver.update(collection, rollbackValues, selection, newArgs)
            } catch (e: Exception) {
                Log.w(LOG_TAG, "failed to roll back rows in collection=$collection", e)
            }
        }
        val stillMoved = collections.sumOf { countUnder(context, it, selection, newArgs) }
        if (stillMoved == 0) {
            Log.w(LOG_TAG, "rolled back a partial bulk move of ${oldFile.path}")
            // Only the destination folder the move created is removed, and only
            // when empty: anything else there belongs to someone else.
            File(newFile.path).delete()
            return failure(REASON_FAILED)
        }
        return partial(moved)
    }

    private fun countUnder(context: Context, collectionUri: Uri, selection: String, args: Array<String>): Int {
        return try {
            context.contentResolver.query(collectionUri, arrayOf(MediaStore.MediaColumns._ID), selection, args, null)?.use { it.count } ?: 0
        } catch (e: Exception) {
            Log.w(LOG_TAG, "failed to count rows in collection=$collectionUri", e)
            0
        }
    }

    /**
     * Whether rows can be written without asking the user. On Android 10 this
     * means the legacy write permission; from Android 12, `MANAGE_MEDIA`.
     * Android 11 only offers `createWriteRequest`, which prompts and caps the
     * request at 2000 URIs, so it is not a strategy of its own.
     */
    private fun canWriteWithoutPrompt(context: Context): Boolean = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> MediaStorePermissions.isMediaManagementGranted(context)
        Build.VERSION.SDK_INT == Build.VERSION_CODES.Q ->
            ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        else -> false
    }

    /**
     * Two-step rename through a fresh name, so no step differs only in case.
     * Puts the folder back under its old name when the second step fails.
     */
    private fun renameThroughTemporary(oldFile: File, parent: File, newFile: File): Boolean {
        val temporary = File(parent, "${newFile.name}.aves_renaming_${System.nanoTime()}")
        if (!oldFile.renameTo(temporary)) return false
        if (temporary.renameTo(newFile)) return true
        temporary.renameTo(oldFile)
        return false
    }

    /** Same two steps for a SAF document, whose id changes with each rename. */
    private fun renameDocumentThroughTemporary(document: DocumentFileCompat, oldName: String, newName: String): Boolean {
        val temporaryName = "$newName.aves_renaming_${System.nanoTime()}"
        if (!document.renameTo(temporaryName)) return false
        if (document.renameTo(newName)) return true
        document.renameTo(oldName)
        return false
    }

    private fun success(strategy: String, destination: String, movedRows: Int) = hashMapOf<String, Any?>(
        "renamed" to true,
        "strategy" to strategy,
        "destination" to destination,
        "movedRows" to movedRows,
        "failure" to null,
    )

    /** Some rows moved and kept their ids, but the folder is now split. */
    private fun partial(movedRows: Int) = hashMapOf<String, Any?>(
        "renamed" to false,
        "strategy" to STRATEGY_MEDIA_STORE_BULK,
        "destination" to null,
        "movedRows" to movedRows,
        "failure" to REASON_PARTIAL,
    )

    private fun failure(reason: String) = hashMapOf<String, Any?>(
        "renamed" to false,
        "strategy" to null,
        "destination" to null,
        "movedRows" to -1,
        "failure" to reason,
    )
}
