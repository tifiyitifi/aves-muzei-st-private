package deckers.thibault.aves.storage

import android.content.Context
import android.util.Log
import com.commonsware.cwac.document.DocumentFileCompat
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
 *
 * Anything else answers `unsupported`, and the caller keeps its batched move.
 * A folder with the destination name already existing is never renamed into:
 * only the batched move merges (and renames conflicting files) correctly.
 */
object AlbumRename {
    private val LOG_TAG = LogUtils.createTag<AlbumRename>()

    private const val STRATEGY_APP_PRIVATE = "appPrivate"
    private const val STRATEGY_SAF = "saf"

    private const val REASON_INVALID_NAME = "invalidName"
    private const val REASON_UNSUPPORTED = "unsupported"
    private const val REASON_MISSING = "missing"
    private const val REASON_DESTINATION_EXISTS = "destinationExists"
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
        return success(STRATEGY_APP_PRIVATE, newFile.path)
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
        return success(STRATEGY_SAF, newFile.path)
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

    private fun success(strategy: String, destination: String) = hashMapOf<String, Any?>(
        "renamed" to true,
        "strategy" to strategy,
        "destination" to destination,
        "failure" to null,
    )

    private fun failure(reason: String) = hashMapOf<String, Any?>(
        "renamed" to false,
        "strategy" to null,
        "destination" to null,
        "failure" to reason,
    )
}
