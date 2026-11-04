package com.dot.gallery.core

import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut

/**
 * Subset of the ReFra constants the editor port compiles against.
 *
 * The fork keeps the editor sources close to upstream, so the shared animation and date
 * constants stay in the upstream package/names instead of being inlined at call sites.
 */
object Constants {

    /** e.g. "Mon, Jan 1, 2026". */
    const val EXTENDED_DATE_FORMAT = "EEE, MMM d, yyyy"

    const val DEFAULT_LOW_VELOCITY_SWIPE_DURATION = 50
    const val DEFAULT_NAVIGATION_ANIMATION_DURATION = 300

    object Animation {

        val enterAnimation = fadeIn(tween(DEFAULT_LOW_VELOCITY_SWIPE_DURATION))
        val exitAnimation = fadeOut(tween(DEFAULT_LOW_VELOCITY_SWIPE_DURATION))

        val navigateInAnimation = fadeIn(tween(DEFAULT_NAVIGATION_ANIMATION_DURATION))
        val navigateUpAnimation = fadeOut(tween(DEFAULT_NAVIGATION_ANIMATION_DURATION))

        fun enterAnimation(durationMillis: Int): EnterTransition =
            fadeIn(tween(durationMillis))

        fun exitAnimation(durationMillis: Int): ExitTransition =
            fadeOut(tween(durationMillis))
    }
}
