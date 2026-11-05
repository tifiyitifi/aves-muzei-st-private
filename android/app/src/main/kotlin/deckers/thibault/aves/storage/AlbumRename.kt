package deckers.thibault.aves.storage

import android.content.Context
import android.util.Log
import deckers.thibault.aves.storage.apis.FilePermissions
import deckers.thibault.aves.utils.LogUtils
import java.io.File

/**
 * Whole-directory rename for albums the app can reach with plain `File` access.
 *
 * Only app-private storage qualifies (the vault lives under `filesDir`): on
 * shared storage `File.renameTo` bypasses the Media Store, and the row identity
 * that favourites, covers and pins are keyed on changes with it. Those albums
 * need a bulk `RELATIVE_PATH` update or a SAF document rename instead, and the
 * caller keeps its batched path until one of those ships.
 */
object AlbumRename {
    private val LOG_TAG = LogUtils.createTag<AlbumRename>()

    private const val REASON_INVALID_NAME = "invalidName"
    private const val REASON_NOT_APP_PRIVATE = "notAppPrivate"
    private const val REASON_MISSING = "missing"
    private const val REASON_DESTINATION_EXISTS = "destinationExists"
    private const val REASON_FAILED = "failed"

    /** Renames the folder `oldDir` to `newName` within the same parent directory. */
    fun renameAppPrivateDirectory(context: Context, oldDir: String, newName: String): Map<String, Any?> {
        if (newName.isEmpty() || newName.contains('/') || newName == "." || newName == "..") {
            return failure(REASON_INVALID_NAME)
        }

        val oldFile = File(oldDir)
        val parent = oldFile.parentFile ?: return failure(REASON_MISSING)
        if (!FilePermissions.canEdit(context, oldFile.path)) return failure(REASON_NOT_APP_PRIVATE)
        if (!oldFile.isDirectory) return failure(REASON_MISSING)

        val newFile = File(parent, newName)
        // An existing folder is merged into by the batched move, which a rename
        // cannot do: let the caller keep that path instead of failing halfway.
        if (newFile.exists()) return failure(REASON_DESTINATION_EXISTS)

        val caseOnly = oldFile.name != newName && oldFile.name.equals(newName, ignoreCase = true)
        val renamed = try {
            // Shared storage is case-insensitive, so a case-only rename can be a
            // silent no-op there. The vault is on app-private storage, but the
            // two-step costs nothing and keeps the contract for both.
            if (caseOnly) renameThroughTemporary(oldFile, parent, newFile) else oldFile.renameTo(newFile)
        } catch (e: SecurityException) {
            Log.w(LOG_TAG, "failed to rename $oldDir", e)
            false
        }

        if (!renamed) return failure(REASON_FAILED)
        Log.d(LOG_TAG, "renamed $oldDir to ${newFile.path}")
        return hashMapOf<String, Any?>(
            "renamed" to true,
            "destination" to newFile.path,
            "failure" to null,
        )
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

    private fun failure(reason: String) = hashMapOf<String, Any?>(
        "renamed" to false,
        "destination" to null,
        "failure" to reason,
    )
}
