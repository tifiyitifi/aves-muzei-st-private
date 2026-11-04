package deckers.thibault.aves.channel.calls

import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.os.Environment
import android.util.Log
import androidx.core.net.toUri
import deckers.thibault.aves.channel.calls.Coresult.Companion.safe
import deckers.thibault.aves.channel.calls.Coresult.Companion.safeSuspend
import deckers.thibault.aves.model.FieldMap
import deckers.thibault.aves.model.NameConflictStrategy
import deckers.thibault.aves.model.provider.ImageProvider.ImageOpCallback
import deckers.thibault.aves.model.provider.ImageProviderFactory.getProvider
import deckers.thibault.aves.storage.StorageUtils.ensureTrailingSeparator
import deckers.thibault.aves.utils.LogUtils
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class MediaEditHandler(private val context: Context) : MethodCallHandler {
    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "cancelFileOp" -> safe(call, result, ::cancelFileOp)
            "captureFrame" -> ioScope.launch { safeSuspend(call, result, ::captureFrame) }
            "refraStagingDir" -> safe(call, result, ::refraStagingDir)
            "refraListOutputs" -> ioScope.launch { safe(call, result, ::refraListOutputs) }
            else -> result.notImplemented()
        }
    }

    private fun cancelFileOp(call: MethodCall, result: MethodChannel.Result) {        val opId = call.argument<String>("opId")
        if (opId == null) {
            result.error("cancelFileOp-args", "missing arguments", null)
            return
        }

        Log.i(LOG_TAG, "cancelling file op $opId")
        cancelledOps.add(opId)

        result.success(null)
    }

    /**
     * Absolute directory every edit session stages into.
     *
     * The Dart shell copies the source here before any editor runs, so every write of a built-in
     * or third-party editor stays inside `Pictures/aves_refra_edit` and the user's original is
     * never touched. Sessions share the folder so the album list holds one edit album, not one per
     * edit; the session records which files it produced.
     */
    private fun refraStagingDir(call: MethodCall, result: MethodChannel.Result) {
        val pictures = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
        result.success(File(pictures, REFRA_STAGING_ROOT).absolutePath)
    }

    /**
     * Lists the files a session currently holds in its staging directory.
     *
     * The editor writes through MediaStore, so the folder (not a cached entry list) is the source
     * of truth for "how many results did this edit produce".
     */
    private fun refraListOutputs(call: MethodCall, result: MethodChannel.Result) {
        val relativePath = call.argument<String>("relativePath")
        val directoryPath = call.argument<String>("directory")
        if (relativePath == null || directoryPath == null) {
            result.error("refraListOutputs-args", "missing arguments", null)
            return
        }
        val outputs = ArrayList<Map<String, Any?>>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
            val projection = arrayOf(
                MediaStore.MediaColumns._ID,
                MediaStore.MediaColumns.DISPLAY_NAME,
                MediaStore.MediaColumns.SIZE,
                MediaStore.MediaColumns.MIME_TYPE,
            )
            val selection = "${MediaStore.MediaColumns.RELATIVE_PATH} = ?"
            val selectionArgs = arrayOf(ensureTrailingSeparator(relativePath))
            context.contentResolver.query(collection, projection, selection, selectionArgs, null)?.use { cursor ->
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(0)
                    val mimeType = cursor.getString(3)
                    // The rest of the app resolves entries through the image/video collections; a
                    // `file/` URI is not a media entry and would never be catalogued.
                    val mediaCollection = if (mimeType?.startsWith("video/") == true) {
                        MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                    } else {
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                    }
                    outputs.add(
                        mapOf(
                            "uri" to ContentUris.withAppendedId(mediaCollection, id).toString(),
                            "name" to cursor.getString(1),
                            "size" to cursor.getLong(2),
                            "mimeType" to mimeType,
                        )
                    )
                }
            }
        } else {
            File(directoryPath).listFiles()?.forEach { file ->
                if (file.isFile) {
                    outputs.add(
                        mapOf(
                            "uri" to Uri.fromFile(file).toString(),
                            "name" to file.name,
                            "size" to file.length(),
                            "mimeType" to null,
                        )
                    )
                }
            }
        }
        result.success(outputs)
    }
    private suspend fun captureFrame(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")?.toUri()
        val desiredName = call.argument<String>("desiredName")
        val exifFields = call.argument<FieldMap>("exif") ?: HashMap()
        val bytes = call.argument<ByteArray>("bytes")
        var destinationDir = call.argument<String>("destinationPath")
        val nameConflictStrategy = NameConflictStrategy.fromKey(call.argument<String>("nameConflictStrategy"))
        if (uri == null || desiredName == null || bytes == null || destinationDir == null || nameConflictStrategy == null) {
            result.error("captureFrame-args", "missing arguments", null)
            return
        }

        val provider = getProvider(context, uri)
        if (provider == null) {
            result.error("captureFrame-provider", "failed to find provider for uri=$uri", null)
            return
        }

        destinationDir = ensureTrailingSeparator(destinationDir)
        provider.captureFrame(context, desiredName, exifFields, bytes, destinationDir, nameConflictStrategy, object : ImageOpCallback {
            override fun onSuccess(fields: FieldMap) = result.success(fields)
            override fun onFailure(throwable: Throwable) = result.error("captureFrame-failure", "failed to capture frame for uri=$uri", throwable.message)
        })
    }

    companion object {
        private val LOG_TAG = LogUtils.createTag<MediaEditHandler>()
        const val CHANNEL = "deckers.thibault/aves/media_edit"

        val cancelledOps = HashSet<String>()
        const val REFRA_STAGING_ROOT = "aves_refra_edit"
    }
}