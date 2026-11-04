package com.dot.gallery.feature_node.presentation.util

import android.app.Activity
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Matrix
import android.graphics.Paint
import android.net.Uri
import android.provider.MediaStore
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemGestures
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.core.graphics.createBitmap
import androidx.core.graphics.scale
import com.dot.gallery.core.util.SdkCompat
import com.dot.gallery.feature_node.domain.model.Media
import com.dot.gallery.feature_node.domain.util.getUri
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

/**
 * UI helpers the ported ReFra editor imports from the upstream `presentation.util` package.
 *
 * Upstream spreads these across several files that also carry gallery-wide concerns
 * (cloud, vaults, metadata sections). Only the editor-facing functions are kept here so the
 * port stays a small, self-contained slice.
 */

fun Long.getDate(format: String): String =
    SimpleDateFormat(format, Locale.getDefault()).format(Date(this * 1000L))

inline fun String.sentenceCase(): String = lowercase().replaceFirstChar { it.uppercase() }

/** Applies a full 4x5 color matrix with Android's native color filter. */
fun applyColorMatrix(src: Bitmap, matrix: FloatArray): Bitmap {
    val result = createBitmap(src.width, src.height, src.config ?: Bitmap.Config.ARGB_8888)
    val canvas = Canvas(result)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        colorFilter = ColorMatrixColorFilter(ColorMatrix(matrix))
    }
    canvas.drawBitmap(src, 0f, 0f, paint)
    return result
}

fun resizeBitmap(bitmap: Bitmap, maxWidth: Int, maxHeight: Int): Bitmap {
    val width = bitmap.width
    val height = bitmap.height
    val aspectRatio = width.toFloat() / height.toFloat()
    val newWidth: Int
    val newHeight: Int

    if (width > height) {
        newWidth = maxWidth
        newHeight = (maxWidth / aspectRatio).toInt()
    } else {
        newHeight = maxHeight
        newWidth = (maxHeight * aspectRatio).toInt()
    }
    return bitmap.scale(newWidth, newHeight)
}

fun Bitmap.flipHorizontally(): Bitmap {
    val matrix = Matrix().apply { postScale(-1f, 1f, width / 2f, height / 2f) }
    return Bitmap.createBitmap(this, 0, 0, width, height, matrix, true)
}

fun Bitmap.flipVertically(): Bitmap {
    val matrix = Matrix().apply { postScale(1f, -1f, width / 2f, height / 2f) }
    return Bitmap.createBitmap(this, 0, 0, width, height, matrix, true)
}

fun Bitmap.rotate(degrees: Float): Bitmap {
    val matrix = Matrix().apply { postRotate(degrees) }
    return Bitmap.createBitmap(this, 0, 0, width, height, matrix, true)
}

fun Dp.quantizeBlur(step: Dp = 4.dp): Dp {
    if (value <= 0f) return 0.dp
    val s = step.value.coerceAtLeast(1f)
    return ((value / s).roundToInt() * s).dp
}

/** Pixel/dp radius variant of [quantizeBlur]. */
fun Float.quantizeBlur(step: Float = 4f): Float {
    if (this <= 0f) return 0f
    val s = step.coerceAtLeast(1f)
    return (this / s).roundToInt() * s
}

fun Modifier.stableBlur(radius: Dp, step: Dp = 4.dp): Modifier {
    val quantized = radius.quantizeBlur(step)
    return if (quantized > 0.dp) this.blur(quantized) else this
}

fun Modifier.safeSystemGesturesPadding(
    onlyRight: Boolean = false,
    onlyLeft: Boolean = false,
): Modifier = composed {
    val gesturePadding = WindowInsets.systemGestures.asPaddingValues()
    if (onlyRight) {
        padding(end = gesturePadding.calculateEndPadding(LocalLayoutDirection.current))
    } else if (onlyLeft) {
        padding(start = gesturePadding.calculateStartPadding(LocalLayoutDirection.current))
    } else {
        padding(
            start = gesturePadding.calculateStartPadding(LocalLayoutDirection.current),
            end = gesturePadding.calculateEndPadding(LocalLayoutDirection.current),
        )
    }
}

fun Modifier.verticalFadingEdge(percentage: Float) = this.fadingEdge(
    Brush.verticalGradient(
        0f to Color.Transparent,
        percentage to Color.Red,
        1f - percentage to Color.Red,
        1f to Color.Transparent,
    )
)

fun Modifier.horizontalFadingEdge(percentage: Float) = this.fadingEdge(
    Brush.horizontalGradient(
        0f to Color.Transparent,
        percentage to Color.Red,
        1f - percentage to Color.Red,
        1f to Color.Transparent,
    )
)

fun Modifier.fadingEdge(brush: Brush) = this
    .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
    .drawWithContent {
        drawContent()
        drawRect(brush = brush, blendMode = BlendMode.DstIn)
    }

@Composable
fun rememberActivityResult(onResultCanceled: () -> Unit = {}, onResultOk: () -> Unit = {}) =
    rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartIntentSenderForResult(),
        onResult = {
            if (it.resultCode == Activity.RESULT_OK) onResultOk()
            if (it.resultCode == Activity.RESULT_CANCELED) onResultCanceled()
        },
    )

fun <T : Media> T.writeRequest(contentResolver: ContentResolver): IntentSenderRequest? =
    getUri().writeRequest(contentResolver)

fun Uri.writeRequest(contentResolver: ContentResolver): IntentSenderRequest? {
    if (!SdkCompat.supportsMediaStoreRequests) return null
    return try {
        IntentSenderRequest.Builder(
            MediaStore.createWriteRequest(contentResolver, arrayListOf(this))
        ).build()
    } catch (e: IllegalArgumentException) {
        printWarning("writeRequest: not a media item, skipping permission request: ${e.message}")
        null
    }
}

fun ActivityResultLauncher<IntentSenderRequest>.launchWriteRequest(
    request: IntentSenderRequest?,
    onGranted: () -> Unit,
) {
    if (request != null) {
        launch(request)
    } else {
        onGranted()
    }
}

/** External apps that can edit an image, excluding this one. */
fun Context.getEditImageCapableApps(): List<ResolveInfo> {
    val intent = Intent(Intent.ACTION_EDIT).apply { setType("image/*") }
    return packageManager.queryIntentActivities(intent, 0)
        .filterNot { it.activityInfo.packageName == packageName }
        .distinctBy { it.activityInfo.packageName }
}

/**
 * Opens a specific external editor on [uri]. The caller always passes a staged copy, so an
 * editor that overwrites its input can never touch the user's original.
 */
fun Context.launchEditImageIntent(packageName: String, uri: Uri) {
    val intent = Intent(Intent.ACTION_EDIT).apply {
        addCategory(Intent.CATEGORY_DEFAULT)
        setDataAndType(uri, "image/*")
        putExtra("mimeType", "image/*")
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        setPackage(packageName)
    }
    startActivity(intent)
}
