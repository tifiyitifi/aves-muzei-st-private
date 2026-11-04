package com.dot.gallery.core.util

import android.os.Build

/**
 * API-level gates the editor port relies on.
 *
 * Aves supports devices below Android 11, while ReFra's write paths assume scoped-storage
 * request APIs, so every gate stays explicit here instead of being inlined.
 */
object SdkCompat {

    val supportsTrash: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R

    val supportsMediaStoreRequests: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R

    val supportsBlur: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S

    /** Android 13+ shows its own clipboard confirmation UI. */
    val showsClipboardConfirmation: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
}
