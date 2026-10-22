package deckers.thibault.aves.channel.calls

import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import deckers.thibault.aves.channel.calls.Coresult.Companion.safe
import deckers.thibault.aves.model.provider.BrowseMediaStore
import deckers.thibault.aves.model.provider.MediaStoreImageProvider
import deckers.thibault.aves.utils.LogUtils
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class MediaStoreHandler(private val context: Context) : MethodCallHandler {
    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkObsoleteContentIds" -> ioScope.launch { safe(call, result, ::checkObsoleteContentIds) }
            "checkObsoletePaths" -> ioScope.launch { safe(call, result, ::checkObsoletePaths) }
            "getChangedUris" -> ioScope.launch { safe(call, result, ::getChangedUris) }
            "getGenerationByVolume" -> ioScope.launch { safe(call, result, ::getGenerationByVolume) }
            "countEntries" -> ioScope.launch { safe(call, result, ::countEntries) }
            "getMediaPage" -> ioScope.launch { safe(call, result, ::getMediaPage) }
            "getAlbumSummaries" -> ioScope.launch { safe(call, result, ::getAlbumSummaries) }
            "scanFile" -> ioScope.launch { safe(call, result, ::scanFile) }
            else -> result.notImplemented()
        }
    }

    private fun checkObsoleteContentIds(call: MethodCall, result: MethodChannel.Result) {
        val knownContentIds = call.argument<List<Number?>>("knownContentIds")?.map { it?.toLong() }
        if (knownContentIds == null) {
            result.error("checkObsoleteContentIds-args", "missing arguments", null)
            return
        }
        result.success(MediaStoreImageProvider().checkObsoleteContentIds(context, knownContentIds))
    }

    private fun checkObsoletePaths(call: MethodCall, result: MethodChannel.Result) {
        val knownPathById = call.argument<Map<Number?, String?>>("knownPathById")?.mapKeys { it.key?.toLong() }
        if (knownPathById == null) {
            result.error("checkObsoletePaths-args", "missing arguments", null)
            return
        }
        result.success(MediaStoreImageProvider().checkObsoletePaths(context, knownPathById))
    }

    private fun getChangedUris(call: MethodCall, result: MethodChannel.Result) {
        val sinceGenerationByVolume: Map<String, Long?>? = call.argument<Map<String, Number?>>("sinceGenerationByVolume")?.mapValues { kv -> kv.value?.toLong() }
        if (sinceGenerationByVolume == null) {
            result.error("getChangedUris-args", "missing arguments", null)
            return
        }
        val uris = MediaStoreImageProvider().getChangedUris(context, sinceGenerationByVolume)
        result.success(uris)
    }

    private fun getGenerationByVolume(@Suppress("unused_parameter") call: MethodCall, result: MethodChannel.Result) {
        val generationByVolume: Map<String, Long?>? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            MediaStore.getExternalVolumeNames(context).associateWith { volumeName ->
                try {
                    MediaStore.getGeneration(context, volumeName)
                } catch (ex: IllegalArgumentException) {
                    Log.w(LOG_TAG, "failed to get generation for volume=$volumeName", ex)
                    null
                }
            }
        } else {
            null
        }
        result.success(generationByVolume)
    }

    private fun countEntries(@Suppress("unused_parameter") call: MethodCall, result: MethodChannel.Result) {
        result.success(MediaStoreImageProvider().countEntries(context))
    }

    private fun getMediaPage(call: MethodCall, result: MethodChannel.Result) {
        val limit = call.argument<Number>("limit")?.toInt()
        if (limit == null || limit <= 0) {
            result.error("getMediaPage-args", "missing or invalid limit", null)
            return
        }
        val beforeSortDateSecs = call.argument<Number>("beforeSortDateSecs")?.toLong()
        val beforeId = call.argument<Number>("beforeId")?.toLong()
        val directory = call.argument<String>("directory")
        result.success(BrowseMediaStore.fetchPage(context, limit, beforeSortDateSecs, beforeId, directory))
    }

    private fun getAlbumSummaries(@Suppress("unused_parameter") call: MethodCall, result: MethodChannel.Result) {
        result.success(BrowseMediaStore.fetchAlbumSummaries(context))
    }

    private fun scanFile(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val mimeType = call.argument<String>("mimeType")
        MediaScannerConnection.scanFile(context, arrayOf(path), arrayOf(mimeType)) { _, uri: Uri? -> result.success(uri?.toString()) }
    }

    companion object {
        private val LOG_TAG = LogUtils.createTag<MediaStoreHandler>()
        const val CHANNEL = "deckers.thibault/aves/media_store"
    }
}