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

import android.app.KeyguardManager
import android.app.WallpaperManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.ViewConfiguration
import net.rbgrn.android.glwallpaperservice.GLWallpaperService

/**
 * Live wallpaper entry point.
 *
 * Ported from Muzei's `MuzeiWallpaperService.kt`
 * (https://github.com/muzei/muzei, Apache-2.0): the service/engine lifecycle,
 * `directBootAware`, desktop gestures, offset notifications and the lock-screen
 * observation follow it.
 *
 * v1 keeps the service in the app process (like Muzei) and only renders baked
 * bitmaps; it never touches the database. The background worker owns all querying.
 */
class AvesLiveWallpaperService : GLWallpaperService() {
    companion object {
        private const val TAG = "AvesLiveWallpaper"

        /** Muzei debounces three-finger taps so one touch does not repeat. */
        private const val THREE_FINGER_TAP_INTERVAL_MS = 1000L
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
        private var lockScreenVisible = false

        /**
         * Muzei consumes a tap command only when a double tap preceded it, so a
         * single tap on the wallpaper never triggers a gesture.
         */
        private var validDoubleTap = false
        private var lastThreeFingerTap = 0L
        private val gestureHandler = Handler(Looper.getMainLooper())
        private val clearDoubleTap = Runnable { validDoubleTap = false }

        private val gestureDetector = GestureDetector(
            this@AvesLiveWallpaperService,
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

        /**
         * Muzei's `LockscreenObserver`: the engine draws the same surface for
         * home and lock, so the surface is inferred from the screen broadcasts
         * and the keyguard state.
         */
        private val lockScreenReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    Intent.ACTION_USER_PRESENT -> updateLockScreen(false)
                    Intent.ACTION_SCREEN_OFF -> updateLockScreen(true)
                    Intent.ACTION_SCREEN_ON -> {
                        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                        updateLockScreen(keyguard.isKeyguardLocked)
                    }
                }
            }
        }

        override fun onCreate(surfaceHolder: SurfaceHolder) {
            super.onCreate(surfaceHolder)
            registerLockScreenReceiver()
            renderer = WallpaperRenderer(this@AvesLiveWallpaperService) { requestRender() }
            setEGLContextClientVersion(2)
            setEGLConfigChooser(8, 8, 8, 0, 0, 0)
            setRenderer(renderer)
            renderMode = RENDERMODE_WHEN_DIRTY
            requestRender()
            // Muzei parity: receive wallpaper taps and desktop offset notifications.
            setTouchEventsEnabled(true)
            setOffsetNotificationsEnabled(true)
            // The engine may be created while the screen is off, so hand the
            // initial keyguard state to the renderer before the first load.
            renderer.setLockScreenVisible(lockScreenVisible)
            Log.d(TAG, "engine.create preview=$isPreview lockScreen=$lockScreenVisible")
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
                // A state write can land while no engine is attached (process
                // restart, lost channel call). The load is a no-op when nothing
                // changed, so re-checking here is cheap.
                if (::renderer.isInitialized) renderer.requestReload()
            }
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
            renderer.setNormalOffsetX(if (xOffsetStep > 0f) xOffset else 0.5f)
        }

        override fun onZoomChanged(zoom: Float) {
            super.onZoomChanged(zoom)
            if (::renderer.isInitialized) renderer.setZoom(zoom)
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
            if (::renderer.isInitialized) renderer.onWallpaperTouch()
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
            renderer.performTapAction(action)
        }

        override fun onDestroy() {
            Log.d(TAG, "engine.destroy")
            gestureHandler.removeCallbacks(clearDoubleTap)
            try {
                applicationContext.unregisterReceiver(lockScreenReceiver)
            } catch (e: IllegalArgumentException) {
                // Already unregistered with the engine.
                Log.d(TAG, "lock screen receiver was not registered", e)
            }
            if (::renderer.isInitialized) {
                queueEvent { renderer.destroy() }
            }
            super.onDestroy()
        }

        private fun registerLockScreenReceiver() {
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_USER_PRESENT)
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_SCREEN_ON)
            }
            applicationContext.registerReceiver(lockScreenReceiver, filter)
            val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            lockScreenVisible = keyguard.isKeyguardLocked
        }

        private fun updateLockScreen(visible: Boolean) {
            if (lockScreenVisible == visible) return
            lockScreenVisible = visible
            if (::renderer.isInitialized) renderer.setLockScreenVisible(visible)
        }
    }
}
