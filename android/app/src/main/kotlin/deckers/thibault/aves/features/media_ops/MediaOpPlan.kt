package deckers.thibault.aves.features.media_ops

import android.os.Build
import deckers.thibault.aves.storage.apis.StorageApi

/**
 * Decisions of the v2 pipeline, kept free of Android I/O so they can be unit
 * tested on the JVM.
 *
 * The API cascade deliberately mirrors the legacy `ImageProvider.moveSingle`,
 * so v2 only changes *when* the storage APIs are resolved and how results are
 * scanned, never which API an entry may use.
 */
object MediaOpPlan {
    /** Hard-coded limit of `MediaStore.createWriteRequest`. */
    const val MAX_BULK_URIS = 2000

    /** Entries collected before a scan batch is flushed, to keep progress moving. */
    const val SCAN_BATCH_SIZE = 32

    /**
     * Storage API to use for one entry, or `null` when only the SAF copy fallback
     * is possible.
     *
     * @param sourceApi most preferred API granted on the source directory
     * @param targetApi most preferred API granted for insertion in the target directory
     * @param sourceInMediaStore whether the entry's row lives in the Media Store
     * @param sameVolume whether both paths are on the same storage volume
     * @param canMoveToPath whether the Media Store accepts the target primary directory for the MIME type
     * @param copy whether the operation copies instead of moving
     * @param sdkInt Android API level
     */
    fun selectMoveApi(
        sourceApi: StorageApi?,
        targetApi: StorageApi?,
        sourceInMediaStore: Boolean,
        sameVolume: Boolean,
        canMoveToPath: Boolean,
        copy: Boolean,
        sdkInt: Int,
    ): StorageApi? {
        // A same-volume move of a Media Store row is one row update that also moves
        // the file. It beats direct file access on purpose: renaming a file behind
        // its row leaves the index pointing at a missing file, so the entry cannot
        // be used again until the Media Scanner rebuilt it seconds later.
        if (!copy && sourceInMediaStore && sameVolume && canMoveToPath && sdkInt >= Build.VERSION_CODES.Q) {
            return StorageApi.MEDIA_STORE
        }

        if (sourceApi != null && sourceApi == targetApi) {
            if (sourceApi == StorageApi.FILE) {
                return StorageApi.FILE
            }
        }

        // direct file access is possible on Android 11 if Media Store permissions are granted,
        // but in practice moving files sometimes fails, so it is only used for copies
        if (sdkInt >= Build.VERSION_CODES.R && copy) {
            val apis = setOfNotNull(sourceApi, targetApi)
            if (apis.isNotEmpty() && setOf(StorageApi.FILE, StorageApi.MEDIA_STORE).containsAll(apis)) {
                return StorageApi.FILE
            }
        }

        return null
    }

    /**
     * Whether a bulk write request is worth raising right now.
     *
     * A request needs a foreground Activity, the bulk API (Android 11+), at
     * least one and at most [MAX_BULK_URIS] items, and the user's consent to be
     * asked at all. Anything else degrades silently instead of interrupting the
     * operation.
     */
    fun canRequestPrompt(
        allowPrompt: Boolean,
        sdkInt: Int,
        uriCount: Int,
        activityReady: Boolean,
    ): Boolean = allowPrompt && activityReady && sdkInt >= Build.VERSION_CODES.R && uriCount in 1..MAX_BULK_URIS
}
