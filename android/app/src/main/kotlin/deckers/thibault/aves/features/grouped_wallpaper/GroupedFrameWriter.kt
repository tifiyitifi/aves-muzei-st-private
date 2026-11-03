/*
 * Copyright 2026 Aves contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package deckers.thibault.aves.features.grouped_wallpaper

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.os.Build
import android.util.Log
import androidx.core.net.toUri
import com.bumptech.glide.Glide
import deckers.thibault.aves.glide.AvesAppGlideModule
import deckers.thibault.aves.utils.BitmapUtils.applyExifOrientation
import deckers.thibault.aves.utils.MimeTypes.needRotationAfterGlide
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer

/**
 * Decodes, covers, encodes and writes one wallpaper frame.
 *
 * Dart owns everything that needs judgement — which photo, at which layout,
 * under which key — and this writer owns only the pixels. Doing the bitmap work
 * here avoids handing a full-size image back and forth: the old path encoded a
 * PNG in Dart and decoded the same PNG here, which was most of a bake.
 *
 * The effect images are deliberately not rendered here. The effects page
 * previews them on the GPU with the same math Dart uses, so a second
 * implementation in Kotlin would let preview and wallpaper drift apart.
 */
object GroupedFrameWriter {
    private const val TAG = "AvesGroupedWallpaper"

    /** Side of the square sample Dart uses to measure the artwork's darkness. */
    const val DARKNESS_SIDE = 64

    const val DEFAULT_QUALITY = 95

    data class Request(
        val uri: String,
        val mimeType: String,
        val pageId: Int?,
        val sizeBytes: Long?,
        val rotationDegrees: Int,
        val isFlipped: Boolean,
        val targetWidth: Int,
        val targetHeight: Int,
        val outputPath: String,
        val quality: Int,
        /** The user's quarter turn, on top of the EXIF orientation. */
        val extraRotationDegrees: Int = 0,
        /** The image fit mode, as Dart's `WallpaperImageFit` name. */
        val fit: String = "fill",
    )

    data class Result(
        val width: Int,
        val height: Int,
        /** `DARKNESS_SIDE²` RGBA pixels of the baked frame. */
        val thumbnail: ByteArray,
    )

    /**
     * Writes [request] to its output path, or returns null when this entry
     * cannot be decoded here.
     *
     * Null is the contract's "use the Dart fallback": a missing service, an
     * undecodable format and a failed channel all look the same to the caller,
     * and the fallback path is the same one desktop and tests use.
     */
    suspend fun write(context: Context, request: Request): Result? = withContext(Dispatchers.IO) {
        val startedAt = System.currentTimeMillis()
        val output = File(request.outputPath)
        if (!FrameOutputPath.isInside(GroupedWallpaperStateFile.ensureRoot(context), output)) {
            Log.w(TAG, "frame.write refused a path outside the state root: ${request.outputPath}")
            return@withContext null
        }

        val rotateAfter = needRotationAfterGlide(request.mimeType, request.pageId)
        val exifRotation = if (rotateAfter) request.rotationDegrees else 0
        val extraRotation = ((request.extraRotationDegrees % 360) + 360) % 360
        val quarterTurns = (extraRotation / 90) % 4
        // The decode box is swapped when the *combined* rotation is a quarter
        // turn: Glide crops in the stored orientation, so decoding to the display
        // size first and rotating after would lose resolution and cut the wrong
        // part of the photo.
        val (decodeWidth, decodeHeight) = FrameDecodeSize.beforeRotation(request.targetWidth, request.targetHeight, exifRotation + extraRotation)
        val fitMode = FrameFitMode.parse(request.fit)
        val target = Glide.with(context)
            .asBitmap()
            .apply(AvesAppGlideModule.uncachedFullImageOptions)
            .override(decodeWidth, decodeHeight)
            .load(AvesAppGlideModule.getModel(context, request.uri.toUri(), request.mimeType, request.pageId, request.sizeBytes))
            .submit()
        try {
            val decoded = target.get()
            if (decoded == null) {
                Log.w(TAG, "frame.write decoded nothing uri=${request.uri} mime=${request.mimeType}")
                return@withContext null
            }
            val rotated = if (rotateAfter) applyExifOrientation(context, decoded, request.rotationDegrees, request.isFlipped) else decoded
            val upright = rotated ?: decoded
            try {
                val bitmap = renderFrame(upright, request.targetWidth, request.targetHeight, quarterTurns, fitMode)
                try {
                    writeAtomically(output, bitmap, request.quality)
                    val thumbnail = darknessThumbnail(bitmap)
                    Log.d(
                        TAG,
                        "frame.write size=${bitmap.width}x${bitmap.height} request=${request.targetWidth}x${request.targetHeight}" +
                                " rotation=$extraRotation fit=${request.fit} decode=${decodeWidth}x$decodeHeight ms=${System.currentTimeMillis() - startedAt}",
                    )
                    Result(bitmap.width, bitmap.height, thumbnail)
                } finally {
                    // The output is ours; the decoded one belongs to Glide.
                    bitmap.recycle()
                }
            } finally {
                // The EXIF-rotated bitmap is ours; the decoded one belongs to Glide.
                if (rotated !== null && rotated !== decoded) rotated.recycle()
            }
        } catch (t: Throwable) {
            // Undecodable entries (SVG, a broken file, a vault the app cannot
            // open) fall back to the Dart path instead of failing the bake.
            Log.w(TAG, "frame.write failed uri=${request.uri} mime=${request.mimeType}", t)
            null
        } finally {
            Glide.with(context).clear(target)
        }
    }

    /**
     * Draws [source] into a target-sized frame: the quarter turn first, then the
     * image fit. The canvas rotation maps the swapped target box onto the real
     * one, so no intermediate rotated bitmap is needed.
     */
    private fun renderFrame(
        source: Bitmap,
        targetWidth: Int,
        targetHeight: Int,
        quarterTurns: Int,
        fit: FrameFitMode,
    ): Bitmap {
        val output = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        // Wallpapers are opaque; an image with alpha must not show the previous
        // wallpaper or undefined GL memory through it.
        canvas.drawColor(Color.BLACK)
        val frameWidth = if (quarterTurns % 2 == 0) targetWidth else targetHeight
        val frameHeight = if (quarterTurns % 2 == 0) targetHeight else targetWidth
        val transform = FrameFit.transform(source.width, source.height, frameWidth, frameHeight, fit)
        val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
        val matrix = Matrix()
        matrix.setScale(transform.scaleX, transform.scaleY)
        // The fit transform is relative to the rotated frame's top-left; after
        // moving the canvas origin to the frame centre, that corner is at
        // (-frameWidth/2, -frameHeight/2).
        matrix.postTranslate(transform.translateX - frameWidth / 2f, transform.translateY - frameHeight / 2f)
        canvas.save()
        canvas.translate(targetWidth / 2f, targetHeight / 2f)
        if (quarterTurns != 0) canvas.rotate(quarterTurns * 90f)
        canvas.drawBitmap(source, matrix, paint)
        canvas.restore()
        return output
    }

    /** Encodes through a temporary file, so the renderer never sees half a frame. */
    private fun writeAtomically(output: File, bitmap: Bitmap, quality: Int) {
        val dir = output.parentFile
        dir?.mkdirs()
        // A unique staging name: the app engine and the background engine can bake
        // the same photo at the same time, and a shared `.tmp` would interleave.
        val tmp = File(dir, "${output.name}.${System.nanoTime()}.tmp")
        val encoded = tmp.outputStream().use { stream -> bitmap.compress(webpFormat(), quality.coerceIn(0, 100), stream) }
        if (!encoded) {
            tmp.delete()
            throw IOException("failed to encode ${output.name}")
        }
        if (!tmp.renameTo(output)) {
            // Android's rename replaces atomically; keep the desktop/JVM path
            // working anyway.
            output.delete()
            if (!tmp.renameTo(output)) {
                tmp.delete()
                throw IOException("failed to publish ${output.name}")
            }
        }
    }

    /**
     * WebP keeps the frame small without the ringing a JPEG would add, and the
     * renderer decodes it natively either way.
     */
    private fun webpFormat(): Bitmap.CompressFormat = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        Bitmap.CompressFormat.WEBP_LOSSY
    } else {
        @Suppress("DEPRECATION")
        Bitmap.CompressFormat.WEBP
    }

    /**
     * Downsamples the frame for Dart's darkness measurement.
     *
     * The weights stay in Dart, next to the dim curve that consumes them, so the
     * sample is the only thing that crosses the channel.
     */
    private fun darknessThumbnail(bitmap: Bitmap): ByteArray {
        val side = DARKNESS_SIDE
        val scaled = Bitmap.createScaledBitmap(bitmap, side, side, true)
        val argb = if (scaled.config == Bitmap.Config.ARGB_8888) scaled else scaled.copy(Bitmap.Config.ARGB_8888, false)
        try {
            val buffer = ByteBuffer.allocate(side * side * 4)
            argb.copyPixelsToBuffer(buffer)
            return buffer.array()
        } finally {
            if (argb !== scaled && argb !== bitmap) argb.recycle()
            if (scaled !== bitmap) scaled.recycle()
        }
    }
}
