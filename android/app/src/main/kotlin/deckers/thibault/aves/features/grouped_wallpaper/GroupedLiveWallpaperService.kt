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

import android.util.Log
import android.view.SurfaceHolder
import net.rbgrn.android.glwallpaperservice.GLWallpaperService

/**
 * Live wallpaper entry point of the grouped wallpaper.
 *
 * It renders only baked bitmaps and never touches the database: the Flutter
 * engine picks the image and writes `state.json`, and this service survives the
 * app being killed by drawing the last frame it can read. It is a separate
 * component from Muzei's service, so setting one wallpaper replaces the other and
 * each `isActive` check stays truthful.
 */
class GroupedLiveWallpaperService : GLWallpaperService() {
    companion object {
        private const val TAG = "AvesGroupedWallpaper"

        /** Whether the system currently keeps this service alive. */
        @Volatile
        var isRunning = false
            private set
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "service.create")
        isRunning = true
        // The app may already be running: ask it for a frame right away instead
        // of waiting for the next time the page is opened.
        GroupedWallpaperAppBridge.requestSync()
    }

    override fun onDestroy() {
        Log.d(TAG, "service.destroy")
        isRunning = false
        super.onDestroy()
    }

    override fun onCreateEngine(): Engine = GroupedEngine()

    inner class GroupedEngine : GLEngine() {
        private lateinit var renderer: GroupedWallpaperRenderer

        override fun onCreate(surfaceHolder: SurfaceHolder) {
            super.onCreate(surfaceHolder)
            renderer = GroupedWallpaperRenderer(this@GroupedLiveWallpaperService) { requestRender() }
            setEGLContextClientVersion(2)
            setEGLConfigChooser(8, 8, 8, 0, 0, 0)
            setRenderer(renderer)
            renderMode = RENDERMODE_WHEN_DIRTY
            requestRender()
            // The engine bakes at the launcher's desired width, so the surface
            // shows a window into it and pans with the launcher offset.
            setOffsetNotificationsEnabled(true)
            Log.d(TAG, "engine.create preview=$isPreview")
        }

        override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            super.onSurfaceChanged(holder, format, width, height)
            requestRender()
        }

        override fun onVisibilityChanged(visible: Boolean) {
            super.onVisibilityChanged(visible)
            if (!visible) return
            requestRender()
            // A frame can land while no engine is attached (process restart, a
            // reload lost during an engine swap), so re-check on every show.
            if (::renderer.isInitialized) renderer.requestReload()
        }

        override fun onOffsetsChanged(
            xOffset: Float,
            yOffset: Float,
            xOffsetStep: Float,
            yOffsetStep: Float,
            xPixelOffset: Int,
            yPixelOffset: Int,
        ) {
            super.onOffsetsChanged(xOffset, yOffset, xOffsetStep, yOffsetStep, xPixelOffset, yPixelOffset)
            if (!::renderer.isInitialized) return
            // Single-page launchers report a zero step and a zero offset; center
            // the artwork instead of pinning it to the left edge.
            renderer.setOffsetX(if (xOffsetStep > 0f) xOffset else 0.5f)
        }

        override fun onDestroy() {
            Log.d(TAG, "engine.destroy")
            if (::renderer.isInitialized) {
                queueEvent { renderer.destroy() }
            }
            super.onDestroy()
        }
    }
}
