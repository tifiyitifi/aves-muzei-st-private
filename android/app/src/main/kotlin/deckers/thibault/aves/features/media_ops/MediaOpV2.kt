package deckers.thibault.aves.features.media_ops

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import deckers.thibault.aves.model.AvesEntry
import deckers.thibault.aves.model.EntryFields
import deckers.thibault.aves.model.FieldMap
import deckers.thibault.aves.model.NameConflictStrategy
import deckers.thibault.aves.model.provider.CancelCheck
import deckers.thibault.aves.model.provider.FileImageProvider
import deckers.thibault.aves.model.provider.ImageProvider
import deckers.thibault.aves.model.provider.ImageProvider.ImageOpCallback
import deckers.thibault.aves.model.provider.MediaStoreImageProvider
import deckers.thibault.aves.storage.PathSegments
import deckers.thibault.aves.storage.PermissionManager
import deckers.thibault.aves.storage.StorageUtils
import deckers.thibault.aves.storage.StorageUtils.ensureTrailingSeparator
import deckers.thibault.aves.storage.StorageUtils.getVolumePath
import deckers.thibault.aves.storage.apis.FilePermissions
import deckers.thibault.aves.storage.apis.MediaStorePermissions
import deckers.thibault.aves.storage.apis.StorageApi
import deckers.thibault.aves.utils.LogUtils
import deckers.thibault.aves.utils.MimeTypes
import deckers.thibault.aves.utils.UriUtils.isContentScheme
import deckers.thibault.aves.utils.UriUtils.tryParseId
import java.io.File

/**
 * Fast pipeline for move/copy/rename.
 *
 * It is not a different set of storage rules: every entry still picks the same
 * storage API the legacy pipeline would. What changes is the cost around it:
 *
 * - storage APIs are resolved once per directory instead of twice per entry;
 * - a move on the same volume updates the Media Store row in place, so no scan
 *   is needed at all;
 * - work that does need the scanner is batched, one `scanFile` for a whole
 *   chunk instead of one awaited scan (with retries and sleeps) per file;
 * - a refused Media Store write escalates to a single system request for the
 *   remaining batch, then either retries or degrades silently.
 *
 * Events keep the legacy shape, plus a `strategy` per entry and at most one
 * `permission` outcome per operation.
 */
class MediaOpV2(
    private val context: Context,
    private val allowPermissionPrompt: Boolean,
) {
    private val provider = MediaStoreImageProvider()

    private val permissions = MediaOpPermissions(context, allowPermissionPrompt)

    /** Edition API per (directory, insertion) pair, resolved once per operation. */
    private val editionApis = HashMap<Pair<String, Boolean>, StorageApi?>()

    /** Entries whose new Media Store URI is only known after a batched scan. */
    private val pending = ArrayList<PendingEmit>()

    /** Old paths whose Media Store row must be cleared in the same scan batch. */
    private val obsolete = ArrayList<Pair<String, String>>()

    private var mediastoreCount = 0

    private var fileCount = 0

    private var safCount = 0

    private var scanNanos = 0L

    /**
     * Set when the Media Store rejects a structural update (e.g. a row that
     * cannot change ownership). Retrying it for every remaining entry would
     * cost one failed IPC each, so the rest of the operation uses the file path.
     */
    private var mediaStoreUnsupported = false

    private var startedNanos = 0L

    private class PendingEmit(val path: String, val mimeType: String, val result: FieldMap)

    suspend fun moveMultiple(
        copy: Boolean,
        nameConflictStrategy: NameConflictStrategy,
        entriesByTargetDir: Map<String, List<AvesEntry>>,
        isCancelledOp: CancelCheck,
        callback: ImageOpCallback,
    ) {
        startedNanos = System.nanoTime()
        var total = 0

        entriesByTargetDir.forEach { (targetDir, entries) ->
            val toBin = targetDir == StorageUtils.TRASH_PATH_PLACEHOLDER
            entries.forEachIndexed { index, entry ->
                total += 1
                val result: FieldMap = hashMapOf("uri" to entry.uri.toString(), "success" to false)
                try {
                    val newFields = if (isCancelledOp()) {
                        ImageProvider.skippedFieldMap
                    } else {
                        handleMove(
                            entry = entry,
                            remaining = entries.subList(index, entries.size),
                            targetDir = targetDir,
                            toBin = toBin,
                            copy = copy,
                            nameConflictStrategy = nameConflictStrategy,
                            result = result,
                        )
                    }
                    if (newFields != null) {
                        result["newFields"] = newFields
                        result["success"] = true
                        emit(result, callback)
                    }
                } catch (ex: Exception) {
                    Log.w(LOG_TAG, "failed to move entry with uri=${entry.uri}", ex)
                    emit(result, callback)
                }
                if (pending.size >= MediaOpPlan.SCAN_BATCH_SIZE) {
                    flushPending(callback)
                }
            }
            flushPending(callback)
        }
        flushPending(callback)
        logSummary("move", total)
    }

    suspend fun renameMultiple(
        entriesToNewName: Map<AvesEntry, String>,
        isCancelledOp: CancelCheck,
        callback: ImageOpCallback,
    ) {
        startedNanos = System.nanoTime()
        val entries = entriesToNewName.entries.toList()

        entries.forEachIndexed { index, (entry, desiredName) ->
            val result: FieldMap = hashMapOf("uri" to entry.uri.toString(), "success" to false)
            try {
                val newFields = if (isCancelledOp()) {
                    ImageProvider.skippedFieldMap
                } else {
                    handleRename(
                        entry = entry,
                        desiredName = desiredName,
                        remaining = entries.subList(index, entries.size).map { it.key },
                        result = result,
                    )
                }
                if (newFields != null) {
                    result["newFields"] = newFields
                    result["success"] = true
                    emit(result, callback)
                }
            } catch (ex: Exception) {
                Log.w(LOG_TAG, "failed to rename entry with uri=${entry.uri}", ex)
                emit(result, callback)
            }
            if (pending.size >= MediaOpPlan.SCAN_BATCH_SIZE) {
                flushPending(callback)
            }
        }
        flushPending(callback)
        logSummary("rename", entries.size)
    }

    /**
     * Moves or copies one entry.
     *
     * @return the fields to emit right away, or `null` when the entry was queued
     * for the batched scan (its event is emitted after the scan resolves the URI)
     */
    private suspend fun handleMove(
        entry: AvesEntry,
        remaining: List<AvesEntry>,
        targetDir: String,
        toBin: Boolean,
        copy: Boolean,
        nameConflictStrategy: NameConflictStrategy,
        result: FieldMap,
    ): FieldMap? {
        val mimeType = entry.mimeType
        val sourceUri = entry.uri
        val sourcePath = entry.storagePath
        val desiredName = if (entry.trashed) entry.path?.let { File(it).name } else null

        val sourceFile = sourcePath?.let { File(it) }
        if (sourceFile != null && !sourceFile.exists() && toBin) {
            // trashed entry whose file is already gone: drop the orphaned row
            provider.deleteSingle(context, sourceUri, sourcePath, mimeType)
            return ImageProvider.deletedFieldMap
        }

        var effectiveTargetDir = targetDir
        if (toBin) {
            // the trash directory must be on the same volume as the entry
            val trashDir = StorageUtils.trashDirFor(context, sourcePath ?: StorageUtils.getPrimaryVolumePath(context))
                ?: throw Exception("failed to find trash dir for path=$sourcePath")
            effectiveTargetDir = trashDir.path
        }
        effectiveTargetDir = ensureTrailingSeparator(effectiveTargetDir)

        sourceFile ?: throw Exception("failed to move entry without a storage path, uri=$sourceUri")
        val sourceDirPath = sourceFile.parent?.let { ensureTrailingSeparator(it) }
            ?: throw Exception("failed to resolve source directory for path=${sourceFile.path}")

        if (sourceDirPath == effectiveTargetDir && !(copy && nameConflictStrategy == NameConflictStrategy.RENAME)) {
            // nothing to do unless it is a renamed copy
            return ImageProvider.skippedFieldMap
        }
        if (!sourceFile.exists()) {
            throw Exception("failed to move file because it is missing at path=${sourceFile.path}")
        }

        val sourceExtension = sourceFile.extension
        val desiredNameWithoutExtension = (desiredName ?: sourceFile.name).substringBeforeLast(".")
        val resolution = provider.resolveTargetFileNameWithoutExtension(
            context = context,
            dir = effectiveTargetDir,
            desiredNameWithoutExtension = desiredNameWithoutExtension,
            mimeType = mimeType,
            defaultExtension = sourceExtension,
            conflictStrategy = nameConflictStrategy,
        )
        val targetNameWithoutExtension = resolution.nameWithoutExtension ?: return ImageProvider.skippedFieldMap
        val targetFile = File(effectiveTargetDir, "$targetNameWithoutExtension.$sourceExtension")

        val sourceApi = editionApi(sourceDirPath, insertion = false)
        val targetApi = editionApi(effectiveTargetDir, insertion = true)
        val moveApi = MediaOpPlan.selectMoveApi(
            sourceApi = sourceApi,
            targetApi = targetApi,
            sameVolume = getVolumePath(context, sourceFile.path) == getVolumePath(context, targetFile.path),
            canMoveToPath = MediaStorePermissions.canMoveToPath(context, mimeType, effectiveTargetDir),
            copy = copy,
            sdkInt = Build.VERSION.SDK_INT,
        )

        if (moveApi == StorageApi.MEDIA_STORE && !mediaStoreUnsupported) {
            when (updateMediaStorePath(sourceUri, mimeType, targetFile, remaining)) {
                UpdateResult.SUCCESS -> {
                    mediastoreCount += 1
                    result["strategy"] = STRATEGY_MEDIA_STORE
                    return if (toBin) binFields(targetFile.path) else MediaOpScan.buildFields(context, targetFile.path, sourceUri)
                }

                UpdateResult.UNSUPPORTED -> {
                    Log.d(LOG_TAG, "media store cannot update uri=$sourceUri, skipping it for the rest of the operation")
                    mediaStoreUnsupported = true
                }

                UpdateResult.REFUSED -> Log.d(LOG_TAG, "falling back from the Media Store for uri=$sourceUri")
            }
        }

        val fileCapable = sourceApi == StorageApi.FILE && targetApi == StorageApi.FILE
        if (moveApi == StorageApi.FILE || (moveApi == StorageApi.MEDIA_STORE && fileCapable)) {
            FileImageProvider.move(sourceFile, targetFile, copy)
            fileCount += 1
            result["strategy"] = STRATEGY_FILE
            if (!copy && !sourceFile.exists()) {
                obsolete.add(sourceFile.path to mimeType)
            }
            return if (toBin) binFields(targetFile.path) else queueScan(targetFile.path, mimeType, result)
        }

        // SAF: always copy, then delete the source when moving
        safCount += 1
        result["strategy"] = STRATEGY_SAF
        val targetPath = provider.createSingle(
            context = context,
            mimeType = mimeType,
            targetDir = effectiveTargetDir,
            targetNameWithoutExtension = targetNameWithoutExtension,
            defaultExtension = sourceExtension,
        ) { output ->
            StorageUtils.openInputStream(context, sourceUri)?.use { input -> input.copyTo(output) }
        }
        if (!copy) {
            try {
                provider.deleteSingle(context, sourceUri, sourcePath, mimeType)
            } catch (ex: Exception) {
                Log.w(LOG_TAG, "failed to delete source entry with path=$sourcePath", ex)
            }
        }
        return if (toBin) binFields(targetPath) else queueScan(targetPath, mimeType, result)
    }

    private suspend fun handleRename(
        entry: AvesEntry,
        desiredName: String,
        remaining: List<AvesEntry>,
        result: FieldMap,
    ): FieldMap? {
        val sourceUri = entry.uri
        val oldFile = entry.path?.let { File(it) } ?: return ImageProvider.skippedFieldMap
        val mimeType = entry.mimeType
        val desiredNameWithoutExtension = desiredName.substringBeforeLast(".")
        if (oldFile.nameWithoutExtension == desiredNameWithoutExtension) {
            return ImageProvider.skippedFieldMap
        }
        val dir = oldFile.parent ?: return ImageProvider.skippedFieldMap
        val resolution = provider.resolveTargetFileNameWithoutExtension(
            context = context,
            dir = dir,
            desiredNameWithoutExtension = desiredNameWithoutExtension,
            mimeType = mimeType,
            defaultExtension = oldFile.extension,
            conflictStrategy = NameConflictStrategy.RENAME,
        )
        val targetNameWithoutExtension = resolution.nameWithoutExtension ?: return ImageProvider.skippedFieldMap
        val newFile = File(dir, "$targetNameWithoutExtension${MimeTypes.extensionFor(mimeType, oldFile.extension)}")
        if (oldFile == newFile) {
            return ImageProvider.skippedFieldMap
        }

        if (sourceUri.isContentScheme && !mediaStoreUnsupported) {
            when (updateMediaStoreName(sourceUri, mimeType, newFile, remaining)) {
                UpdateResult.SUCCESS -> {
                    mediastoreCount += 1
                    result["strategy"] = STRATEGY_MEDIA_STORE
                    return MediaOpScan.buildFields(context, newFile.path, sourceUri)
                }

                UpdateResult.UNSUPPORTED -> {
                    Log.d(LOG_TAG, "media store cannot rename uri=$sourceUri, skipping it for the rest of the operation")
                    mediaStoreUnsupported = true
                }

                UpdateResult.REFUSED -> Log.d(LOG_TAG, "falling back from the Media Store for uri=$sourceUri")
            }
        }

        if (FilePermissions.canEdit(context, oldFile.path)) {
            if (!oldFile.renameTo(newFile)) {
                throw Exception("failed to rename file at path=${oldFile.path}")
            }
            fileCount += 1
            result["strategy"] = STRATEGY_FILE
            obsolete.add(oldFile.path to mimeType)
            return queueScan(newFile.path, mimeType, result)
        }

        val document = StorageUtils.getDocumentFileForExistingFile(context, filePath = oldFile.path, mediaUri = sourceUri)
            ?: throw Exception("failed to get document at path=${oldFile.path}")
        if (!document.renameTo(newFile.name)) {
            throw Exception("failed to rename document at path=${oldFile.path}")
        }
        safCount += 1
        result["strategy"] = STRATEGY_SAF
        obsolete.add(oldFile.path to mimeType)
        return queueScan(File(dir, document.name).path, mimeType, result)
    }

    /** Queues an entry whose URI is only known after scanning, unless it is outside the Media Store. */
    private fun queueScan(path: String, mimeType: String, result: FieldMap): FieldMap? {
        if (StorageUtils.isInVault(context, path)) {
            return MediaOpScan.buildFileFields(context, path)
        }
        pending.add(PendingEmit(path, mimeType, result))
        return null
    }

    private suspend fun flushPending(callback: ImageOpCallback) {
        if (pending.isEmpty() && obsolete.isEmpty()) return

        val items = pending.toList()
        val stale = obsolete.toList()
        pending.clear()
        obsolete.clear()

        val scanPaths = items.map { it.path } + stale.map { it.first }
        val scanMimeTypes = items.map { it.mimeType } + stale.map { it.second }

        val scanStarted = System.nanoTime()
        val uris = if (scanPaths.isEmpty()) emptyArray() else MediaOpScan.scan(context, scanPaths, scanMimeTypes)
        scanNanos += System.nanoTime() - scanStarted

        items.forEachIndexed { index, item ->
            val fields = resolveScannedFields(item, uris.getOrNull(index))
            if (fields != null) {
                item.result["newFields"] = fields
                item.result["success"] = true
            }
            emit(item.result, callback)
        }
    }

    private suspend fun resolveScannedFields(item: PendingEmit, scannedUri: Uri?): FieldMap? {
        scannedUri?.let { return MediaOpScan.buildFields(context, item.path, it) }
        // the scanner reports nothing for some providers, so fall back to the legacy retry loop
        return try {
            MediaStoreImageProvider.scanNewPathByMediaStore(context, item.path, item.mimeType)
        } catch (ex: Exception) {
            Log.w(LOG_TAG, "failed to scan new path=${item.path}", ex)
            null
        }
    }

    private fun emit(result: FieldMap, callback: ImageOpCallback) {
        permissions.consumeReport()?.let { result["permission"] = it }
        callback.onSuccess(result)
    }

    private fun binFields(trashPath: String): FieldMap = hashMapOf(
        EntryFields.TRASHED to true,
        EntryFields.TRASH_PATH to trashPath,
    )

    private fun editionApi(dirPath: String, insertion: Boolean): StorageApi? {
        val key = ensureTrailingSeparator(dirPath) to insertion
        if (editionApis.containsKey(key)) return editionApis[key]
        val api = try {
            PermissionManager.getStorageEditionApis(context, listOf(key.first), insertion).values.firstOrNull()?.firstOrNull()
        } catch (ex: Exception) {
            Log.w(LOG_TAG, "failed to resolve edition API for dir=${key.first} insertion=$insertion", ex)
            null
        }
        editionApis[key] = api
        return api
    }

    /** Moves a row within the Media Store, which also moves the file and needs no scan. */
    private fun updateMediaStorePath(sourceUri: Uri, mimeType: String, targetFile: File, remaining: List<AvesEntry>): UpdateResult {
        if (!sourceUri.isContentScheme) return UpdateResult.UNSUPPORTED
        val safeUri = StorageUtils.getMediaStoreScopedStorageSafeUri(sourceUri, mimeType)
        val targetSegments = PathSegments(context, targetFile.path)
        val queryUri = mediaUriOnVolume(safeUri, mimeType, targetSegments.volumePath) ?: safeUri
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, targetFile.name)
            put(MediaStore.MediaColumns.RELATIVE_PATH, targetSegments.relativeDir)
        }
        return updateContent(queryUri, values, remaining)
    }

    /** Renames a row in place, keeping its URI and needing no scan. */
    private fun updateMediaStoreName(sourceUri: Uri, mimeType: String, newFile: File, remaining: List<AvesEntry>): UpdateResult {
        if (!sourceUri.isContentScheme) return UpdateResult.UNSUPPORTED
        val safeUri = StorageUtils.getMediaStoreScopedStorageSafeUri(sourceUri, mimeType)
        val queryUri = mediaUriOnVolume(safeUri, mimeType, getVolumePath(context, newFile.path)) ?: safeUri

        // `IS_PENDING` is required for `TITLE`, not for `DISPLAY_NAME`
        val pendingValues = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 1) }
        val markedPending = updateContent(queryUri, pendingValues, remaining)

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, newFile.name)
            put(MediaStore.MediaColumns.TITLE, newFile.nameWithoutExtension)
            put(MediaStore.MediaColumns.IS_PENDING, 0)
        }
        val renamed = updateContent(queryUri, values, remaining)
        if (renamed == UpdateResult.SUCCESS) return UpdateResult.SUCCESS

        // retry without `TITLE`, which some providers reject, and never leave the row hidden
        val fallback = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, newFile.name)
            put(MediaStore.MediaColumns.IS_PENDING, 0)
        }
        val fallbackRenamed = updateContent(queryUri, fallback, remaining)
        if (fallbackRenamed == UpdateResult.SUCCESS) return UpdateResult.SUCCESS

        if (markedPending == UpdateResult.SUCCESS) {
            try {
                context.contentResolver.update(queryUri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
            } catch (ex: Exception) {
                Log.w(LOG_TAG, "failed to clear pending flag for uri=$queryUri", ex)
            }
        }
        return if (renamed == UpdateResult.UNSUPPORTED || fallbackRenamed == UpdateResult.UNSUPPORTED) UpdateResult.UNSUPPORTED else UpdateResult.REFUSED
    }

    private fun updateContent(uri: Uri, values: ContentValues, remaining: List<AvesEntry>): UpdateResult {
        try {
            if (context.contentResolver.update(uri, values, null, null) > 0) return UpdateResult.SUCCESS
            Log.w(LOG_TAG, "media store updated no row for uri=$uri, falling back")
            return UpdateResult.REFUSED
        } catch (ex: IllegalArgumentException) {
            Log.w(LOG_TAG, "media store update not allowed for uri=$uri ex=${ex.message}")
            return UpdateResult.UNSUPPORTED
        } catch (ex: SecurityException) {
            Log.w(LOG_TAG, "media store update refused for uri=$uri ex=${ex.message}")
            // ask once, for the whole remaining batch, then retry or degrade
            if (!permissions.ensureWriteAccess(remaining.map { it.uri }, remaining.map { it.mimeType })) return UpdateResult.REFUSED
            return try {
                if (context.contentResolver.update(uri, values, null, null) > 0) UpdateResult.SUCCESS else UpdateResult.REFUSED
            } catch (e: Exception) {
                Log.w(LOG_TAG, "media store update still refused for uri=$uri", e)
                UpdateResult.REFUSED
            }
        }
    }

    private fun mediaUriOnVolume(uri: Uri, mimeType: String, volumePath: String?): Uri? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || volumePath == null) return null
        val rootContentUri = StorageUtils.getMediaStoreRootContentUri(context, mimeType, volumePath) ?: return null
        val contentId = uri.tryParseId() ?: return null
        return ContentUris.withAppendedId(rootContentUri, contentId)
    }

    private fun logSummary(op: String, total: Int) {
        if (total == 0) return
        val durationMillis = (System.nanoTime() - startedNanos) / 1_000_000
        val scanMillis = scanNanos / 1_000_000
        Log.d(LOG_TAG, "v2 $op $total entries via mediastore=$mediastoreCount file=$fileCount saf=$safCount in ${durationMillis}ms (scan ${scanMillis}ms)")
    }

    companion object {
        private val LOG_TAG = LogUtils.createTag<MediaOpV2>()

        const val STRATEGY_MEDIA_STORE = "mediastore"
        const val STRATEGY_FILE = "file"
        const val STRATEGY_SAF = "saf"
    }

    /** How a Media Store write ended, which decides whether to keep trying it. */
    private enum class UpdateResult {
        SUCCESS,

        /** The row was refused for this operation (no grant), but the API is usable. */
        REFUSED,

        /** The provider rejects this kind of update, so later entries skip the attempt. */
        UNSUPPORTED,
    }
}
