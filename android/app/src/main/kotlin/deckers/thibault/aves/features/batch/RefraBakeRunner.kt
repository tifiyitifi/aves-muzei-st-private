package deckers.thibault.aves.features.batch

import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import androidx.exifinterface.media.ExifInterface
import androidx.core.net.toUri
import com.dot.gallery.core.decoder.format.ImageReencoder
import com.dot.gallery.core.util.SafeExif
import com.dot.gallery.core.util.ext.saveImageEncoded
import com.dot.gallery.core.util.ext.saveImageStreaming
import com.dot.gallery.feature_node.domain.model.editor.Adjustment
import com.dot.gallery.feature_node.domain.model.editor.TileBehavior
import com.dot.gallery.feature_node.presentation.edit.bake.EditReplay
import com.dot.gallery.feature_node.presentation.edit.bake.TiledBakeEngine
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Headless full-resolution bake for the batch pipeline.
 *
 * The editor's save path lives inside `EditViewModel` (Compose, Glide, an
 * Activity); a batch job has none of those. This runner reuses the same
 * resolution-independent pieces — [TiledBakeEngine], [EditReplay] and
 * [ImageReencoder] — behind a small, coroutine-friendly API.
 *
 * One decode and one encode per image: the whole adjustment chain is replayed on
 * a single bitmap, then resize and the footer composite run on the result, and
 * only then is the image written.
 */
class RefraBakeRunner(private val context: Context) {

    suspend fun run(item: BatchItem, pipeline: BatchPipeline, output: BatchOutputSpec): Uri? {
        val sourceUri = item.uri.toUri()
        val writeFormat = resolveFormat(pipeline.format ?: output.format, item.mimeType, item.displayName)
        val config = ImageReencoder.ReencodeConfig(
            mode = ImageReencoder.QualityMode.MANUAL,
            lossyQuality = (pipeline.quality ?: output.quality).coerceIn(1, 100),
        )
        val displayName = buildDisplayName(output.namePattern, item.displayName, writeFormat)
        val relativePath = output.relativePath.ifBlank { BatchJobParser.DEFAULT_RELATIVE_PATH }
        val adjustments = pipeline.adjustments.toList()
        val hasGeometry = adjustments.any { it.tileBehavior is TileBehavior.Geometry }

        val canStream = pipeline.resize == null &&
            pipeline.footer == null &&
            !hasGeometry &&
            (writeFormat == ImageReencoder.ImageWriteFormat.JPEG || writeFormat == ImageReencoder.ImageWriteFormat.PNG) &&
            runCatching { TiledBakeEngine.isStreamEligible(context, sourceUri, adjustments) }.getOrDefault(false)

        val uri = (if (canStream) streamBake(sourceUri, adjustments, writeFormat, config, relativePath, displayName) else null)
            ?: bitmapBake(sourceUri, pipeline, writeFormat, config, relativePath, displayName)
            ?: return null

        if (pipeline.refreshTime) {
            refreshModifiedTime(uri)
        }
        return uri
    }

    private suspend fun streamBake(
        sourceUri: Uri,
        adjustments: List<Adjustment>,
        writeFormat: ImageReencoder.ImageWriteFormat,
        config: ImageReencoder.ReencodeConfig,
        relativePath: String,
        displayName: String,
    ): Uri? {
        val streamFormat = when (writeFormat) {
            ImageReencoder.ImageWriteFormat.JPEG -> TiledBakeEngine.StreamFormat.JPEG
            ImageReencoder.ImageWriteFormat.PNG -> TiledBakeEngine.StreamFormat.PNG
            else -> return null
        }
        return runCatching {
            context.contentResolver.saveImageStreaming(
                mimeType = writeFormat.mimeType,
                relativePath = relativePath,
                displayName = displayName,
            ) { fd ->
                TiledBakeEngine.bakeToStream(
                    context,
                    sourceUri,
                    adjustments,
                    streamFormat,
                    config.effectiveLossyQuality,
                    fd,
                )
            }
        }.getOrNull()
    }

    private suspend fun bitmapBake(
        sourceUri: Uri,
        pipeline: BatchPipeline,
        writeFormat: ImageReencoder.ImageWriteFormat,
        config: ImageReencoder.ReencodeConfig,
        relativePath: String,
        displayName: String,
    ): Uri? {
        val source = decode(sourceUri) ?: return null
        var current = source
        return try {
            current = runCatching { EditReplay.replay(source, pipeline.adjustments) }.getOrNull() ?: return null
            pipeline.resize?.let { spec -> current = resize(current, spec) }
            pipeline.footer?.let { spec -> current = compositeFooter(current, spec, displayName) }
            context.contentResolver.saveImageEncoded(
                bitmap = current,
                writeFormat = writeFormat,
                config = config,
                mimeType = writeFormat.mimeType,
                relativePath = relativePath,
                displayName = displayName,
            )
        } catch (_: Throwable) {
            null
        } finally {
            if (current !== source && !current.isRecycled) current.recycle()
            if (!source.isRecycled) source.recycle()
        }
    }

    // -- decode -----------------------------------------------------------------

    /**
     * Decodes the source and normalizes EXIF orientation.
     *
     * The editor builds its recipe on a Glide-rotated proxy, so a full-res replay
     * must start from the same orientation. [TiledBakeEngine] only accepts normal
     * orientations for the same reason; this path is the fallback that makes a
     * non-normal source behave identically instead of producing a rotated recipe.
     */
    private fun decode(uri: Uri): Bitmap? {
        val decoded = decodeWithFactory(uri)
        if (decoded != null) return applyExifOrientation(uri, decoded)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            return decodeWithImageDecoder(uri)
        }
        return null
    }

    private fun decodeWithFactory(uri: Uri): Bitmap? = runCatching {
        context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) }
    }.getOrNull()

    @RequiresApi(Build.VERSION_CODES.P)
    private fun decodeWithImageDecoder(uri: Uri): Bitmap? = runCatching {
        val source = ImageDecoder.createSource(context.contentResolver, uri)
        ImageDecoder.decodeBitmap(source) { decoder, _, _ ->
            // Pixel operations need a software bitmap; hardware bitmaps cannot be
            // read back by the adjustment chain.
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        }
    }.getOrNull()

    private fun applyExifOrientation(uri: Uri, bitmap: Bitmap): Bitmap {
        val orientation = SafeExif.orientation(context, uri)
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(-90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(-90f)
            else -> return bitmap
        }
        val rotated = runCatching {
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        }.getOrNull() ?: return bitmap
        if (rotated !== bitmap) bitmap.recycle()
        return rotated
    }

    // -- transforms -------------------------------------------------------------

    private fun resize(source: Bitmap, spec: ResizeSpec): Bitmap {
        val maxLongEdge = spec.maxLongEdge
        val percent = spec.percent
        val width: Int
        val height: Int
        when {
            maxLongEdge != null -> {
                val scale = maxLongEdge.toFloat() / max(source.width, source.height)
                if (scale >= 1f) return source
                width = (source.width * scale).roundToInt()
                height = (source.height * scale).roundToInt()
            }
            percent != null -> {
                width = source.width * percent / 100
                height = source.height * percent / 100
            }
            else -> return source
        }
        val scaled = runCatching {
            Bitmap.createScaledBitmap(source, max(1, width), max(1, height), true)
        }.getOrNull() ?: return source
        if (scaled !== source) source.recycle()
        return scaled
    }

    /**
     * Appends (or prepends) a solid band carrying [fileName] or a custom label.
     *
     * The source pixels are copied unchanged; only the canvas grows. The text is
     * centred and shrinks until it fits, because file names have no length limit.
     */
    private fun compositeFooter(source: Bitmap, spec: FooterSpec, fileName: String): Bitmap {
        val bandHeight = max(1, (source.height * spec.bandHeightPercent / 100f).roundToInt())
        val output = Bitmap.createBitmap(source.width, source.height + bandHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        canvas.drawColor(spec.background)

        val sourceTop = if (spec.atTop) bandHeight else 0
        canvas.drawBitmap(source, 0f, sourceTop.toFloat(), null)

        val bandTop = if (spec.atTop) 0 else source.height
        val bandPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = spec.background
            style = Paint.Style.FILL
        }
        canvas.drawRect(Rect(0, bandTop, source.width, bandTop + bandHeight), bandPaint)

        val label = spec.text?.takeIf { it.isNotBlank() } ?: fileName
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = spec.foreground
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create("sans-serif", Typeface.NORMAL)
        }
        var textSize = bandHeight * (spec.textSizePercent / 100f)
        textPaint.textSize = textSize
        val maxWidth = source.width * 0.94f
        while (textSize > 8f && textPaint.measureText(label) > maxWidth) {
            textSize -= 1f
            textPaint.textSize = textSize
        }
        val metrics = textPaint.fontMetrics
        val baseline = bandTop + bandHeight / 2f - (metrics.ascent + metrics.descent) / 2f
        canvas.drawText(label, source.width / 2f, baseline, textPaint)

        source.recycle()
        return output
    }

    // -- output -----------------------------------------------------------------

    private fun resolveFormat(requested: String, mimeType: String?, displayName: String): ImageReencoder.ImageWriteFormat {
        return when (requested.lowercase(Locale.US)) {
            "jpeg", "jpg" -> ImageReencoder.ImageWriteFormat.JPEG
            "png" -> ImageReencoder.ImageWriteFormat.PNG
            "webp" -> ImageReencoder.ImageWriteFormat.WEBP_LOSSY
            "heic" -> ImageReencoder.ImageWriteFormat.HEIC
            "avif" -> ImageReencoder.ImageWriteFormat.AVIF
            "jxl" -> ImageReencoder.ImageWriteFormat.JXL
            else -> ImageReencoder.formatForMime(mimeType, displayName) ?: ImageReencoder.ImageWriteFormat.PNG
        }
    }

    private fun buildDisplayName(pattern: String, sourceName: String, format: ImageReencoder.ImageWriteFormat): String {
        val base = sourceName.substringBeforeLast('.', sourceName).ifBlank { "batch" }
        val date = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val name = pattern.replace("{name}", base).replace("{date}", date).ifBlank { base }
        return if (name.contains('.')) name else "$name.${format.fileExtension}"
    }

    /**
     * Makes the processed copy look "new" to other apps.
     *
     * Only the MediaStore timestamp is touched; EXIF capture time is left alone so
     * a batch never rewrites the user's provenance. A file this app just created
     * already carries the current timestamp, so this is only meaningful when a
     * future tool writes in place.
     */
    private fun refreshModifiedTime(uri: Uri) {
        val now = System.currentTimeMillis() / 1000L
        runCatching {
            context.contentResolver.update(
                uri,
                ContentValues().apply { put(MediaStore.MediaColumns.DATE_MODIFIED, now) },
                null,
                null,
            )
        }
    }
}
