package com.dot.gallery.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

/**
 * Minimal Material 3 theme for the native editor surface.
 *
 * The editor is a full-screen, dark surface in ReFra, so the fork keeps that presentation and
 * leaves the app's Flutter theming untouched.
 */
private val EditorColorScheme = darkColorScheme()

@Composable
fun GalleryTheme(
    darkTheme: Boolean = true,
    @Suppress("UNUSED_PARAMETER") ignoreUserPreference: Boolean = true,
    content: @Composable () -> Unit,
) {
    @Suppress("UNUSED_PARAMETER")
    val unused = darkTheme
    MaterialTheme(
        colorScheme = EditorColorScheme,
        content = content,
    )
}
