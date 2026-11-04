package com.dot.gallery.core

import android.net.Uri

/**
 * No-op stand-in for ReFra's original-image backup.
 *
 * The fork never edits the user's original: every session first copies the source into
 * `Pictures/aves_refra_edit` and edits that copy. The copy *is* the backup, so the internal
 * `edit_backups` store (and its Room table) is deliberately not ported.
 */
class EditBackupManager {

    suspend fun backupOriginal(
        @Suppress("UNUSED_PARAMETER") mediaId: Long,
        @Suppress("UNUSED_PARAMETER") uri: Uri,
        @Suppress("UNUSED_PARAMETER") mimeType: String,
    ): Boolean = true

    suspend fun hasOriginalBackup(@Suppress("UNUSED_PARAMETER") mediaId: Long): Boolean = false
}
