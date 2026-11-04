package com.dot.gallery.core.ml

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.ConcurrentHashMap

/**
 * Bundled on-device models for the editor's Smart tools.
 *
 * ReFra ships this either as a Play asset pack or downloads the ONNX files on demand, and also
 * carries the CLIP/ArcFace models for search and people grouping. The fork only ports the two
 * editor features, so the two model sets it needs are read from the APK's `refra_models/` assets
 * and copied into the app's private storage on first use; anything not bundled stays unavailable
 * and the corresponding tool is hidden by the UI.
 */
enum class ModelGroup(val subDir: String, val files: List<String>) {
    CUTOUT(
        subDir = "sam",
        files = listOf("mobile_sam_image_encoder.onnx", "sam_mask_decoder_single.onnx"),
    ),

    /** UltraFace RFB-320 detector, powers the editor's "Blur faces" action. */
    FACE_DETECT(
        subDir = "face_detect",
        files = listOf("version-RFB-320.onnx"),
    ),

    /**
     * ArcFace embedding model. The fork does not port ReFra's people grouping, so this group is
     * declared for source compatibility but is never bundled: [ModelManager.isReady] stays false.
     */
    FACE_RECOGNITION(
        subDir = "face_recog",
        files = listOf("arcface.onnx"),
    );

    companion object {
        fun of(fileName: String): ModelGroup = entries.firstOrNull { fileName in it.files } ?: CUTOUT
    }
}

data class ModelFileInfo(
    val name: String,
    val size: Long,
)

class ModelsNotAvailableException(
    message: String = "ML models are not installed for this build.",
) : RuntimeException(message)

class ModelManager(private val context: Context) {

    private val prepared = preparedModels

    private val modelsDir: File
        get() = File(context.filesDir, MODELS_DIR_NAME)

    /**
     * Whether [group] can be used right now.
     *
     * Besides the copy state, the destination files are checked, so a second [ModelManager]
     * instance (the editor creates one per view model) sees the models another instance already
     * installed.
     */
    fun isReady(group: ModelGroup): Boolean =
        prepared[group] == true || group.files.all { File(modelsDir, "${group.subDir}/$it").let { f -> f.exists() && f.length() > 0L } }

    /**
     * Copies [group]'s assets into private storage if needed. Safe to call repeatedly and from
     * any thread; a missing asset leaves the group unavailable instead of failing the editor.
     */
    suspend fun initializeModels(): Boolean = withContext(Dispatchers.IO) {
        var allInstalled = true
        ModelGroup.entries.forEach { group ->
            val installed = runCatching { installGroup(group) }.getOrElse { e ->
                Log.w(TAG, "ModelManager: failed to install ${group.name}: ${e.message}")
                false
            }
            prepared[group] = installed
            if (!installed) allInstalled = false
        }
        allInstalled
    }

    /**
     * Returns the on-disk file for [name], installing its group on demand. Callers gate on
     * [isReady] first, so a missing model surfaces as a plain file-not-found failure.
     */
    fun getModelFile(name: String): File {
        val group = ModelGroup.of(name)
        if (prepared[group] != true) {
            runCatching { installGroup(group) }
                .onSuccess { prepared[group] = it }
                .onFailure { Log.w(TAG, "ModelManager: install failed for ${group.name}", it) }
        }
        return File(modelsDir, "${group.subDir}/$name")
    }

    private fun installGroup(group: ModelGroup): Boolean {
        val dir = File(modelsDir, group.subDir)
        val dest = group.files.map { File(dir, it) }
        if (dest.all { it.exists() && it.length() > 0L }) return true
        dir.mkdirs()
        var complete = true
        group.files.forEach { name ->
            val target = File(dir, name)
            if (target.exists() && target.length() > 0L) return@forEach
            val assetPath = "$ASSET_ROOT/${group.subDir}/$name"
            val installed = runCatching {
                context.assets.open(assetPath).use { input ->
                    target.outputStream().use { output -> input.copyTo(output, bufferSize = 64 * 1024) }
                }
                target.length() > 0L
            }.getOrDefault(false)
            if (!installed) complete = false
        }
        return complete
    }

    private companion object {
        const val TAG = "RefraEditor"
        const val MODELS_DIR_NAME = "refra_models"
        const val ASSET_ROOT = "refra_models"

        /** Shared across instances so the editor and its helpers see one install state. */
        val preparedModels = ConcurrentHashMap<ModelGroup, Boolean>()
    }
}
