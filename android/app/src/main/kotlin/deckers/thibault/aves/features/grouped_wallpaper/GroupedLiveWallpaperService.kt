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

import android.app.WallpaperManager
import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.ViewConfiguration
import deckers.thibault.aves.features.live_wallpaper_refill.LiveWallpaperRefillScheduler
import deckers.thibault.aves.features.live_wallpaper_refill.LiveWallpaperTarget
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

        /** A three-finger tap fires once per gesture, not once per pointer event. */
        private const val THREE_FINGER_TAP_INTERVAL_MS = 500L

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
        GroupedWallpaperAppBridge.requestSync(null)
    }

    override fun onDestroy() {
        Log.d(TAG, "service.destroy")
        isRunning = false
        super.onDestroy()
    }

    override fun onCreateEngine(): Engine = GroupedEngine()

    inner class GroupedEngine : GLEngine() {
        private lateinit var renderer: GroupedWallpaperRenderer

        /**
         * A wallpaper tap arrives as `COMMAND_TAP` after the gesture detector has
         * already seen the double tap, so the command only fires the gesture when
         * a double tap just happened. A single tap does nothing, like Muzei.
         */
        private var validDoubleTap = false
        private var lastThreeFingerTap = 0L
        private val gestureHandler = Handler(Looper.getMainLooper())
        private val clearDoubleTap = Runnable { validDoubleTap = false }

        private val gestureDetector = GestureDetector(
            this@GroupedLiveWallpaperService,
            object : GestureDetector.SimpleOnGestureListener() {
                override fun onDown(e: MotionEvent): Boolean = true

                override fun onDoubleTap(e: MotionEvent): Boolean {
                    validDoubleTap = true
                    gestureHandler.removeCallbacks(clearDoubleTap)
                    gestureHandler.postDelayed(clearDoubleTap, ViewConfiguration.getDoubleTapTimeout().toLong())
                    return true
                }
            },
        )

        override fun onCreate(surfaceHolder: SurfaceHolder) {
            super.onCreate(surfaceHolder)
            renderer = GroupedWallpaperRenderer(
                this@GroupedLiveWallpaperService,
                requestRender = { requestRender() },
                onAdvanced = ::notifyAdvance,
            )
            setEGLContextClientVersion(2)
            setEGLConfigChooser(8, 8, 8, 0, 0, 0)
            setRenderer(renderer)
            renderMode = RENDERMODE_WHEN_DIRTY
            requestRender()
            // The engine bakes at the launcher's desired width, so the surface
            // shows a window into it and pans with the launcher offset.
            setOffsetNotificationsEnabled(true)
            setTouchEventsEnabled(true)
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

        override fun onCommand(
            action: String?,
            x: Int,
            y: Int,
            z: Int,
            extras: Bundle?,
            resultRequested: Boolean,
        ): Bundle? {
            if (WallpaperManager.COMMAND_TAP == action && validDoubleTap) {
                validDoubleTap = false
                performGesture(threeFinger = false)
            }
            return super.onCommand(action, x, y, z, extras, resultRequested)
        }

        override fun onTouchEvent(event: MotionEvent) {
            super.onTouchEvent(event)
            gestureDetector.onTouchEvent(event)
            if (event.pointerCount == 3) {
                val now = SystemClock.elapsedRealtime()
                if (now - lastThreeFingerTap > THREE_FINGER_TAP_INTERVAL_MS) {
                    lastThreeFingerTap = now
                    performGesture(threeFinger = true)
                }
            }
        }

        private fun performGesture(threeFinger: Boolean) {
            if (!::renderer.isInitialized) return
            val action = renderer.actionFor(threeFinger)
            Log.d(TAG, "gesture threeFinger=$threeFinger action=$action")
            when (action) {
                GroupedWallpaperFileState.ACTION_NEXT_ARTWORK -> advance()
                GroupedWallpaperFileState.ACTION_VIEW_ARTWORK -> openViewPage()
                else -> Log.d(TAG, "gesture action ignored action=$action")
            }
        }

        /**
         * Promotes the prefetched slot, then asks someone to bake the freed one.
         *
         * A tap that cannot be served yet is buffered and replayed as soon as a
         * reload uploads a promotable slot, so a burst of double taps keeps
         * advancing instead of stopping after the prefetched queue.
         */
        private fun advance() {
            val promotion = renderer.promote()
            if (promotion != null) {
                notifyAdvance(promotion)
                return
            }
            renderer.enqueueAdvance()
            requestRefill()
        }

        /** Tells a running app about a promotion, or schedules a background run. */
        private fun notifyAdvance(promotion: GroupedWallpaperPromotion) {
            if (GroupedWallpaperAppBridge.requestSync(promotion)) return
            Log.d(TAG, "advance notification: no listening app, using the background refill")
            LiveWallpaperRefillScheduler.enqueueTapRefill(this@GroupedLiveWallpaperService, LiveWallpaperTarget.GROUPED)
        }

        /** Asks for a refill even though no slot was promoted. */
        private fun requestRefill() {
            if (GroupedWallpaperAppBridge.requestSync(null)) return
            Log.d(TAG, "refill notification: no listening app, using the background refill")
            LiveWallpaperRefillScheduler.enqueueTapRefill(this@GroupedLiveWallpaperService, LiveWallpaperTarget.GROUPED)
        }

        /** Opens the grouped wallpaper's view page, like Muzei's artwork view. */
        private fun openViewPage() {
            GroupedWallpaperAppBridge.requestView()
        }

        override fun onDestroy() {
            Log.d(TAG, "engine.destroy")
            gestureHandler.removeCallbacks(clearDoubleTap)
            if (::renderer.isInitialized) {
                queueEvent { renderer.destroy() }
            }
            super.onDestroy()
        }
    }
}
