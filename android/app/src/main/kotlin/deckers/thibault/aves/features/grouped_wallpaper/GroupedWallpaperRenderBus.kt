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

import java.lang.ref.WeakReference

/**
 * Connects the Flutter engine to the live renderer.
 *
 * The service can be recreated by the system at any time, so the bus holds a weak
 * reference and every call is a no-op when no engine is alive.
 */
object GroupedWallpaperRenderBus {
    @Volatile
    private var rendererRef: WeakReference<GroupedWallpaperRenderer>? = null

    fun attach(renderer: GroupedWallpaperRenderer) {
        rendererRef = WeakReference(renderer)
    }

    fun detach(renderer: GroupedWallpaperRenderer) {
        if (rendererRef?.get() === renderer) {
            rendererRef = null
        }
    }

    fun isAttached(): Boolean = rendererRef?.get() != null

    /** Re-reads `state.json` on the renderer's loader thread. */
    fun reload() {
        rendererRef?.get()?.requestReload()
    }

    /**
     * Promotes the next prefetched slot, like a wallpaper double tap.
     *
     * Returns false when no engine is alive or the queue cannot move (frozen,
     * or no prefetched slot), so the caller can fall back to a background run.
     */
    fun advance(): Boolean = rendererRef?.get()?.promote() == true
}
