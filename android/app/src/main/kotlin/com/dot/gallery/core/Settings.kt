package com.dot.gallery.core

import android.content.Context
import androidx.compose.runtime.Composable
import com.dot.gallery.core.decoder.format.ImageReencoder
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf

/**
 * The small slice of ReFra settings the editor port needs.
 *
 * Aves persists user settings in its own store; the editor is a native surface that only reads
 * the re-encode policy and the "keep modified date" flag, so both are resolved here rather than
 * pulling ReFra's DataStore implementation into the fork.
 */
object Settings {

    object Album {
        /** Whether saving keeps the source's modified date; the editor only needs the default. */
        fun updateModifiedDate(context: Context): Flow<Boolean> = flowOf(DEFAULT_UPDATE_MODIFIED_DATE_)
    }

    object Misc {

        fun getReencodeConfig(
            context: Context,
            detectedQuality: Int? = null,
        ): ImageReencoder.ReencodeConfig = ImageReencoder.ReencodeConfig(
            mode = ImageReencoder.QualityMode.AUTO,
            lossyQuality = DEFAULT_LOSSY_QUALITY_,
            jxlEffort = 7,
            jxlLossless = true,
            detectedQuality = detectedQuality,
        )

        @Composable
        fun rememberAllowBlur(): Boolean = true

        @Composable
        fun rememberAllowGlass(): Boolean = false
    }

    private const val DEFAULT_UPDATE_MODIFIED_DATE_ = false
    private const val DEFAULT_LOSSY_QUALITY_ = 90
}
