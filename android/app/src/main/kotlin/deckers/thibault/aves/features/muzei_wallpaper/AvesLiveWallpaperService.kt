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

package deckers.thibault.aves.features.muzei_wallpaper

import android.os.Bundle
import android.util.Log
import android.view.SurfaceHolder
import net.rbgrn.android.glwallpaperservice.GLWallpaperService

/**
 * Live wallpaper entry point.
 *
 * Ported from Muzei's `MuzeiWallpaperService.kt`
 * (https://github.com/muzei/muzei, Apache-2.0): the service/engine lifecycle,
 * `directBootAware`, desktop gestures and offset notifications follow it.
 *
 * v1 keeps the service in the app process (like Muzei) and only renders baked
 * bitmaps; it never touches the database. The background worker owns all querying.
 */
class AvesLiveWallpaperService : GLWallpaperService() {
    companion object {
        private const val TAG = "AvesLiveWallpaper"
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "service.create")
    }

    override fun onDestroy() {
        Log.d(TAG, "service.destroy")
        super.onDestroy()
    }

    override fun onCreateEngine(): Engine = AvesEngine()

    inner class AvesEngine : GLEngine() {
        private lateinit var renderer: WallpaperRenderer

        override fun onCreate(surfaceHolder: SurfaceHolder) {
            super.onCreate(surfaceHolder)
            renderer = WallpaperRenderer(this@AvesLiveWallpaperService)
            setEGLContextClientVersion(2)
            setEGLConfigChooser(8, 8, 8, 0, 0, 0)
            setRenderer(renderer)
            renderMode = RENDERMODE_WHEN_DIRTY
            requestRender()
            // Muzei parity: receive wallpaper taps and desktop offset notifications.
            // Gesture handling is added with the state-driven renderer.
            setTouchEventsEnabled(true)
            setOffsetNotificationsEnabled(true)
            Log.d(TAG, "engine.create preview=$isPreview")
        }

        override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            super.onSurfaceChanged(holder, format, width, height)
            Log.d(TAG, "surface.changed w=$width h=$height")
            requestRender()
        }

        override fun onVisibilityChanged(visible: Boolean) {
            super.onVisibilityChanged(visible)
            Log.d(TAG, "visibility=$visible")
            if (visible) {
                requestRender()
            }
        }

        override fun onCommand(
            action: String?,
            x: Int,
            y: Int,
            z: Int,
            extras: Bundle?,
            resultRequested: Boolean,
        ): Bundle? {
            Log.d(TAG, "command action=$action")
            return super.onCommand(action, x, y, z, extras, resultRequested)
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
