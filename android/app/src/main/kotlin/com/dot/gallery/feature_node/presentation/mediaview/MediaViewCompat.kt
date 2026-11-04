package com.dot.gallery.feature_node.presentation.mediaview

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisallowComposableCalls
import androidx.compose.runtime.State
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.remember

/**
 * Editor support kept in the upstream `mediaview` package.
 *
 * Upstream defines both helpers inside the (very large) media viewer screen; the fork editor
 * only needs the derived-state helper and the cutout tool enum, so they live in this small file.
 */

@Composable
fun <T> rememberedDerivedState(
    key: Any? = Unit,
    block: @DisallowComposableCalls () -> T,
): State<T> = remember(key) { derivedStateOf(block) }

@Composable
fun <T> rememberedDerivedState(
    vararg keys: Any? = arrayOf(Unit),
    block: @DisallowComposableCalls () -> T,
): State<T> = remember(*keys) { derivedStateOf(block) }
