package com.dot.gallery.core

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import com.dot.gallery.core.decoder.format.ImageReencoder
import com.dot.gallery.core.util.ext.overrideImageEncoded
import com.dot.gallery.core.util.ext.saveImageEncoded
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Write path used by the editor.
 *
 * ReFra routes these calls through its repository; the fork editor works on a staged copy in
 * `Pictures/aves_refra_edit`, so a thin resolver-backed implementation is enough and keeps the
 * editor sources unchanged.
 */
class MediaHandler(private val context: Context) {

    suspend fun saveImage(
        bitmap: Bitmap,
        writeFormat: ImageReencoder.ImageWriteFormat,
        config: ImageReencoder.ReencodeConfig,
        mimeType: String,
        relativePath: String,
        displayName: String,
    ): Uri? = withContext(Dispatchers.IO) {
        context.contentResolver.saveImageEncoded(
            bitmap = bitmap,
            writeFormat = writeFormat,
            config = config,
            mimeType = mimeType,
            relativePath = relativePath,
            displayName = displayName,
        )
    }

    suspend fun overrideImage(
        uri: Uri,
        bitmap: Bitmap,
        writeFormat: ImageReencoder.ImageWriteFormat,
        config: ImageReencoder.ReencodeConfig,
        mimeType: String,
        relativePath: String,
        displayName: String,
    ): Boolean = withContext(Dispatchers.IO) {
        context.contentResolver.overrideImageEncoded(
            uri = uri,
            bitmap = bitmap,
            writeFormat = writeFormat,
            config = config,
        )
    }
}
