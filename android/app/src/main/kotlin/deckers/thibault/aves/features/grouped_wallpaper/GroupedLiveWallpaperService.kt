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

import android.app.KeyguardManager
import android.app.WallpaperManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.ViewConfiguration
import androidx.core.app.ServiceCompat
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

        /** The live instance, so the notification's actions can refresh the bar. */
        @Volatile
        private var instance: GroupedLiveWallpaperService? = null

        /** Re-posts the notification from the state the service is drawing. */
        fun refreshNotification() {
            instance?.updateNotification()
        }

        /**
         * Drops a bar whose service is gone.
         *
         * A service the system or the OEM kills never runs `onDestroy`, so its
         * notification can outlive the wallpaper until the next boot. The app calls
         * this when it attaches the engine and finds this service is no longer the
         * system wallpaper. A live instance is left alone: it owns its bar and
         * clears it on the way out, and a foreground notification cannot be
         * cancelled behind its back anyway.
         */
        fun cancelNotification(context: Context) {
            if (instance != null) return
            GroupedWallpaperNotification.cancel(context)
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "service.create")
        isRunning = true
        instance = this
        // A restart rebuilds the bar from scratch: the keyguard picks the set.
        GroupedWallpaperNotification.resetGroupActionsOverride()
        GroupedWallpaperNotification.ensureChannel(this)
        updateNotification()
        // The app may already be running: ask it for a frame right away instead
        // of waiting for the next time the page is opened.
        GroupedWallpaperAppBridge.requestSync()
    }

    override fun onDestroy() {
        Log.d(TAG, "service.destroy")
        // `super.onDestroy()` tears the engines down, and their
        // `onRealEngineDestroyed` would post the bar again after this method
        // cleared it. Nothing may post from here on.
        destroying = true
        isRunning = false
        instance = null
        // A foreground notification cannot be cancelled directly: drop the
        // foreground state first.
        clearNotification()
        super.onDestroy()
    }

    /**
     * Whether this instance is being destroyed.
     *
     * The wallpaper is gone, so the bar must go with it, including the refresh
     * the engines request on their way out.
     */
    @Volatile
    private var destroying = false

    /** The slot the renderer is drawing, reported so the notification matches. */
    @Volatile
    private var displayedSlotId = -1

    /** Non-preview engines currently drawing the wallpaper. */
    private var realEngines = 0

    /** Whether this instance holds the foreground-service notification. */
    private var isForeground = false

    /**
     * Content key of the bar this service last posted, and whether it was posted
     * as this service's foreground notification.
     *
     * A frame load asks for a refresh every time, and the bar used to be re-posted
     * even when nothing it shows had changed: hundreds of posts a day, which made
     * MIUI rate-limit the app and then hide its notifications on the lock screen.
     * Only a changed bar, or a change of foreground state, is posted now.
     */
    private var postedKey: String? = null
    private var postedAsForeground = false

    /**
     * Re-reads `state.json` and refreshes the notification.
     *
     * The service owns the notification: an engine can be recreated by the system
     * at any time, and the preview engine must not cancel the real one's.
     */
    private fun updateNotification() {
        // The wallpaper is going away: whatever the engines report on their way
        // out must not bring the bar back.
        if (destroying) return
        val state = GroupedWallpaperStateFile.read(this)
        // Off means no bar at all, and no foreground service either: the user
        // turned the notification off, so posting a hidden one would still keep
        // the process in the foreground against that choice.
        if (state == null || state.status == GroupedWallpaperFileState.STATUS_DISABLED || !state.notification) {
            // Cheap on every frame: only touch the manager when something is posted.
            if (postedKey != null || isForeground) {
                clearNotification()
            }
            return
        }
        val slot = if (displayedSlotId >= 0) state.slot(displayedSlotId) else state.currentSlot
        val foreground = realEngines > 0
        // The plain bar belongs to a wallpaper the system is showing. During the
        // picker preview, or when an engine outlives a replacement, this service
        // is not it, and a bar there would outlive the wallpaper. The foreground
        // path is exempt: on some devices `wallpaperInfo` lags behind the real
        // switch, and a wrong answer there would keep the bar off the lock screen.
        if (!foreground && !isSystemWallpaper()) {
            if (postedKey != null || isForeground) {
                clearNotification()
            }
            return
        }
        val key = GroupedWallpaperNotification.contentKey(this, state, slot)
        if (key == postedKey && foreground == postedAsForeground) return
        // With a real engine attached the bar has to be this service's foreground
        // notification: MIUI hides a silent, non-foreground one on the lock screen.
        if (foreground && promoteToForeground(state, slot)) {
            postedKey = key
            postedAsForeground = true
            return
        }
        GroupedWallpaperNotification.update(this, state, slot)
        postedKey = key
        postedAsForeground = false
    }

    /** Whether this service is the wallpaper the system is showing. */
    private fun isSystemWallpaper(): Boolean = WallpaperManager.getInstance(this).wallpaperInfo?.serviceName == GroupedLiveWallpaperService::class.java.name

    /** Drops the bar and forgets what was posted, so a re-enable posts again. */
    private fun clearNotification() {
        demoteFromForeground()
        GroupedWallpaperNotification.cancel(this)
        postedKey = null
        postedAsForeground = false
    }

    /**
     * Promotes the bar to a foreground-service notification.
     *
     * Promoting this already-running service is the only form Android 12+ allows:
     * starting a second foreground service from the background is rejected. The
     * notification is `setOnlyAlertOnce`, so promoting it does not beep again.
     */
    private fun promoteToForeground(state: GroupedWallpaperFileState, slot: GroupedWallpaperSlotFile?): Boolean {
        val notification = GroupedWallpaperNotification.build(this, state, slot) ?: return false
        // `specialUse` is only a known type from Android 14; older releases accept
        // the call without one.
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0
        return try {
            ServiceCompat.startForeground(this, GroupedWallpaperNotification.NOTIFICATION_ID, notification, type)
            if (!isForeground) Log.d(TAG, "notification.foreground=true")
            isForeground = true
            true
        } catch (t: Throwable) {
            // Promotion is only for the lock screen, never a reason to take the
            // wallpaper down: fall back to a normal notification.
            Log.w(TAG, "failed to promote the grouped wallpaper notification", t)
            false
        }
    }

    private fun demoteFromForeground() {
        if (!isForeground) return
        try {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            Log.d(TAG, "notification.foreground=false")
        } catch (t: Throwable) {
            Log.w(TAG, "failed to drop the grouped wallpaper foreground notification", t)
        } finally {
            isForeground = false
        }
    }

    private fun onRealEngineCreated() {
        realEngines++
        if (realEngines == 1) updateNotification()
    }

    private fun onRealEngineDestroyed() {
        realEngines = (realEngines - 1).coerceAtLeast(0)
        if (realEngines != 0) return
        // The bar outlives the engine that drew it: demote, then post it as a
        // normal notification so it does not vanish with the foreground state.
        demoteFromForeground()
        updateNotification()
    }

    private fun onFrameLoaded(displayed: Int) {
        displayedSlotId = displayed
        updateNotification()
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

        /**
         * The engine draws the same surface for home and lock, so the surface is
         * inferred from the screen broadcasts and the keyguard state.
         */
        private var lockScreenVisible = false

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
            registerLockScreenReceiver()
            renderer = GroupedWallpaperRenderer(
                this@GroupedLiveWallpaperService,
                requestRender = { requestRender() },
                onAdvanced = ::notifyAdvance,
                onFrameLoaded = {
                    val displayed = renderer.displayedSlotId()
                    gestureHandler.post { this@GroupedLiveWallpaperService.onFrameLoaded(displayed) }
                },
            )
            setEGLContextClientVersion(2)
            setEGLConfigChooser(8, 8, 8, 0, 0, 0)
            setRenderer(renderer)
            renderMode = RENDERMODE_WHEN_DIRTY
            requestRender()
            // The engine may be created while the screen is off, so hand the
            // initial keyguard state to the renderer before the first load.
            renderer.setLockScreenVisible(lockScreenVisible)
            // The engine bakes at the launcher's desired width, so the surface
            // shows a window into it and pans with the launcher offset.
            setOffsetNotificationsEnabled(true)
            setTouchEventsEnabled(true)
            Log.d(TAG, "engine.create preview=$isPreview lockScreen=$lockScreenVisible")
            // Only the engine drawing the real wallpaper promotes the bar: a
            // picker preview must not claim the foreground service.
            if (!isPreview) this@GroupedLiveWallpaperService.onRealEngineCreated()
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
            if (!renderer.canAdvance()) {
                Log.d(TAG, "advance ignored: the wallpaper cannot move")
                return
            }
            if (renderer.promote()) {
                notifyAdvance()
                return
            }
            renderer.enqueueAdvance()
            requestRefill()
        }

        /** Tells a running app about a promotion, or schedules a background run. */
        private fun notifyAdvance() {
            if (::renderer.isInitialized) {
                val displayed = renderer.displayedSlotId()
                gestureHandler.post { this@GroupedLiveWallpaperService.onFrameLoaded(displayed) }
            }
            if (GroupedWallpaperAppBridge.requestSync()) return
            Log.d(TAG, "advance notification: no listening app, using the background refill")
            LiveWallpaperRefillScheduler.enqueueTapRefill(this@GroupedLiveWallpaperService, LiveWallpaperTarget.GROUPED)
        }

        /** Asks for a refill even though no slot was promoted. */
        private fun requestRefill() {
            if (GroupedWallpaperAppBridge.requestSync()) return
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
            try {
                applicationContext.unregisterReceiver(lockScreenReceiver)
            } catch (e: IllegalArgumentException) {
                // Already unregistered with the engine.
                Log.d(TAG, "lock screen receiver was not registered", e)
            }
            if (::renderer.isInitialized) {
                queueEvent { renderer.destroy() }
            }
            if (!isPreview) this@GroupedLiveWallpaperService.onRealEngineDestroyed()
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
            // Locking or unlocking returns the bar to its default button set; the
            // user's switch applies until the keyguard changes.
            GroupedWallpaperNotification.resetGroupActionsOverride()
            this@GroupedLiveWallpaperService.updateNotification()
        }
    }
}
