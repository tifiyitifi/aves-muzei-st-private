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
import androidx.core.app.ServiceCompat
import deckers.thibault.aves.features.live_wallpaper_refill.LiveWallpaperRefillEngine
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

        /**
         * Fraction of the scroll range one home page takes, as last reported by
         * the launcher's `onOffsetsChanged`.
         *
         * `0` means a single-page home screen that never pans, and `-1` means no
         * callback has arrived yet. The engine bakes wider frames only when the
         * launcher can actually pan them.
         */
        @Volatile
        var scrollStep = -1.0
            private set

        /**
         * Records the launcher's scroll step.
         *
         * @return whether the launcher just started panning, i.e. the step moved
         * from "cannot pan" to a real one. The first callback arrives after the
         * wallpaper was bound, so the frame already baked used the earlier
         * answer; the caller asks for one refill so the photo on screen gains its
         * wide frame now instead of on the next advance.
         */
        fun recordScrollStep(step: Float): Boolean {
            val previous = scrollStep
            scrollStep = step.toDouble()
            return previous <= 0.0 && step > 0f
        }

        /** The live instance, so the notification's actions can refresh the bar. */
        @Volatile
        private var instance: GroupedLiveWallpaperService? = null

        /** Re-posts the notification from the state the service is drawing. */
        fun refreshNotification() {
            instance?.updateNotification()
        }

        /**
         * The slot the real engine is drawing, or `-1` when no engine is running.
         *
         * The app asks for this instead of trusting `state.json`: the renderer can
         * promote a slot on its own, and a reload keeps drawing the one it had. It
         * asks the renderer directly ([GroupedWallpaperRenderBus]) because a bar
         * promotion moves the frame without reporting back; the service's cached
         * field is only the fallback for a renderer that has not attached yet.
         */
        val displayedSlot: Int
            get() = GroupedWallpaperRenderBus.displayedSlot().takeIf { it >= 0 } ?: instance?.displayedSlotId ?: -1

        /**
         * Whether the real engine is drawing the lock screen, so the effect image
         * on screen is `lock.png` rather than `home.png`.
         *
         * The app asks for it with [displayedSlot] so the view page shows the same
         * effect the wallpaper does.
         */
        @Volatile
        var lockScreenVisible = false
            private set

        /**
         * Whether the wallpaper surface is actually visible.
         *
         * The battery gate uses it: a scheduled advance only bakes while the user
         * can see the wallpaper, so two hours of video do not cost a dozen bakes.
         * Screen-off and another app in front both count as invisible.
         */
        @Volatile
        var wallpaperVisible = false
            private set

        /** Records the visibility the engine reports, for the refill gate. */
        fun recordWallpaperVisible(visible: Boolean) {
            wallpaperVisible = visible
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
        // The wallpaper is bound again, so a "it stopped" hint left from an update
        // is stale, and the next loss must be able to hint again.
        GroupedWallpaperRestore.onWallpaperActive(this)
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

    /**
     * The slot the renderer last reported, used only when no renderer is attached.
     *
     * [displayedSlot] prefers the live renderer; this field keeps the last known
     * slot across an engine swap, when the app still has to describe the frame
     * the service was drawing.
     */
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
        val splitLock = GroupedLiveWallpaperService.lockScreenVisible && (state.lock != null || state.lockRangeId.isNotEmpty())
        val displayed = displayedSlot
        // The lock screen describes the decoy. Showing the home title there would
        // leak what the private group is playing, which is the whole point of the
        // split surface.
        val slot = if (splitLock) {
            state.lock
        } else if (displayed >= 0) {
            state.slot(displayed)
        } else {
            state.currentSlot
        }
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
        val key = GroupedWallpaperNotification.contentKey(this, state, slot, lock = splitLock)
        if (key == postedKey && foreground == postedAsForeground) return
        // With a real engine attached the bar has to be this service's foreground
        // notification: MIUI hides a silent, non-foreground one on the lock screen.
        if (foreground && promoteToForeground(state, slot, lock = splitLock)) {
            postedKey = key
            postedAsForeground = true
            return
        }
        GroupedWallpaperNotification.update(this, state, slot, lock = splitLock)
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
    private fun promoteToForeground(state: GroupedWallpaperFileState, slot: GroupedWallpaperSlotFile?, lock: Boolean = false): Boolean {
        val notification = GroupedWallpaperNotification.build(this, state, slot, lock = lock) ?: return false
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
        // The wallpaper service lives as long as the wallpaper is set, so its
        // refill engine should too: a cold start on every tap is most of the
        // delay the user sees when the app is not open.
        LiveWallpaperRefillEngine.holdWarm(true)
        if (realEngines == 1) updateNotification()
    }

    private fun onRealEngineDestroyed() {
        realEngines = (realEngines - 1).coerceAtLeast(0)
        if (realEngines != 0) return
        // The last real surface is gone, so nothing can be seen any more: leaving
        // this true would let a scheduled advance bake for a wallpaper the user
        // no longer has.
        recordWallpaperVisible(false)
        LiveWallpaperRefillEngine.holdWarm(false)
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
         * Decides when a tap is really a double tap.
         *
         * The launcher sends `COMMAND_TAP` for every tap, single ones included, so
         * the command alone cannot tell them apart; the gate fires only when a
         * second signal arrives inside the double-tap window. See
         * [GroupedTapGate].
         */
        private val tapGate = GroupedTapGate(clock = SystemClock::elapsedRealtime)
        private var lastThreeFingerTap = 0L
        private val gestureHandler = Handler(Looper.getMainLooper())

        /**
         * The launcher reports the scroll step on every frame; it is only
         * interesting when it changes, and logging it every time buried the
         * gesture lines in the last bug report.
         */
        private var lastScrollStep = Float.NaN

        /**
         * The engine draws the same surface for home and lock, so the surface is
         * inferred from the screen broadcasts and the keyguard state.
         */
        private var lockScreenVisible = false

        private val lockScreenReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    Intent.ACTION_USER_PRESENT -> updateLockScreen(false)
                    Intent.ACTION_SCREEN_OFF -> {
                        updateLockScreen(true)
                        // Nothing can tap a sleeping screen: drop the warm engine
                        // instead of holding a second Flutter isolate in memory.
                        LiveWallpaperRefillEngine.releaseIfIdle()
                    }
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
                    val fired = tapGate.onTapSignal()
                    Log.d(TAG, "tap.signal src=touch fired=$fired dt=${tapGate.lastGapMs}")
                    if (fired) performGesture(threeFinger = false)
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
                    // Only the engine drawing the real wallpaper reports: a picker
                    // preview paints its own copy of the current slot, and letting
                    // it write here would make the app describe a frame nobody
                    // sees after the picker closes.
                    if (!isPreview) {
                        val displayed = renderer.displayedSlotId()
                        gestureHandler.post { this@GroupedLiveWallpaperService.onFrameLoaded(displayed) }
                    }
                },
                // A picker preview must not answer the app's commands: it would
                // promote a surface nobody sees and swallow the reload the real
                // wallpaper needs.
                attachToBus = !isPreview,
            )
            setEGLContextClientVersion(2)
            setEGLConfigChooser(8, 8, 8, 0, 0, 0)
            setRenderer(renderer)
            renderMode = RENDERMODE_WHEN_DIRTY
            requestRender()
            // The engine may be created while the screen is off, so hand the
            // initial keyguard state to the renderer before the first load.
            renderer.setLockScreenVisible(lockScreenVisible)
            // The frame may be wider than the surface when the scroll effect is
            // on, so the surface shows a window into it and pans with the
            // launcher offset.
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
            if (!isPreview) GroupedLiveWallpaperService.recordWallpaperVisible(visible)
            if (!visible) return
            requestRender()
            // A frame can land while no engine is attached (process restart, a
            // reload lost during an engine swap), so re-check on every show.
            if (::renderer.isInitialized) renderer.requestReload()
            // An advance that came due while the wallpaper was hidden is applied
            // now, so the user sees the new photo on the first frame instead of
            // paying for a bake nobody could see.
            if (!isPreview) requestPendingAdvance()
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
            // The step is how much of the wallpaper's scroll range one page
            // covers: the engine uses it to decide whether a wide frame can pan.
            // A picker preview says nothing about the launcher the wallpaper will
            // live on — it reports its own step, often the single-page `0` — so
            // only the real engine records it. Logged because "the first photos
            // lost the effect" is otherwise untraceable, but only on a change:
            // a launcher reports it on every frame.
            if (lastScrollStep != xOffsetStep) {
                lastScrollStep = xOffsetStep
                Log.d(TAG, "scroll.step step=$xOffsetStep preview=$isPreview")
            }
            if (!isPreview) {
                val startsPanning = GroupedLiveWallpaperService.recordScrollStep(xOffsetStep)
                if (startsPanning) {
                    Log.d(TAG, "scroll.step refill for the wider frame")
                    requestRefill()
                }
            }
            if (!::renderer.isInitialized) return
            // Single-page launchers report a zero step and a zero offset; center
            // the artwork instead of pinning it to the left edge. A step of zero
            // must not throw a real offset away: some launchers scroll while
            // reporting no step, and dropping the offset is what made the pan
            // silently stop following the home pages.
            renderer.setOffsetX(if (xOffsetStep > 0f || xOffset > 0f) xOffset else 0.5f)
        }

        override fun onCommand(
            action: String?,
            x: Int,
            y: Int,
            z: Int,
            extras: Bundle?,
            resultRequested: Boolean,
        ): Bundle? {
            if (WallpaperManager.COMMAND_TAP == action) {
                // Only a tap the gesture detector already saw twice acts: a single
                // tap must never change the wallpaper.
                val fired = tapGate.onTapSignal()
                Log.d(TAG, "tap.signal src=command fired=$fired dt=${tapGate.lastGapMs}")
                if (fired) performGesture(threeFinger = false)
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
            // The decoy only advances with time: a double tap or a three-finger
            // tap on the lock screen must not change what the user is hiding,
            // and the bar's group switch is the intended action there.
            val splitLock = GroupedWallpaperStateFile.read(this@GroupedLiveWallpaperService)
                ?.let { it.lock != null || it.lockRangeId.isNotEmpty() } == true
            // Ask the keyguard now instead of trusting the cached broadcast state:
            // a missed ACTION_USER_PRESENT used to swallow every gesture on the
            // home screen until the next screen cycle.
            val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            if (keyguard.isKeyguardLocked && splitLock) {
                Log.d(TAG, "gesture ignored on the split lock surface threeFinger=$threeFinger")
                return
            }
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
            if (!renderer.canQueueAdvance()) {
                Log.d(TAG, "advance ignored: the wallpaper cannot move")
                return
            }
            if (renderer.promote()) {
                notifyAdvance()
                return
            }
            // The wallpaper may move but the next slot is still baking: keep the
            // tap and ask for the refill that lets `drainPendingAdvance` serve it.
            renderer.enqueueAdvance()
            // Show the wait, so the bar does not keep describing the photo the
            // tap already left.
            GroupedWallpaperNotification.beginPhotoSwitch(this@GroupedLiveWallpaperService, forward = true)
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

        /**
         * Applies an advance that came due while the wallpaper was hidden.
         *
         * The scheduled run deferred the bake to keep a video or a dark screen
         * from costing frames, so the first moment the user can see the wallpaper
         * is when it is owed one.
         */
        private fun requestPendingAdvance() {
            if (!GroupedLiveWallpaperService.isRunning) return
            if (!LiveWallpaperRefillScheduler.consumePendingAdvance(this@GroupedLiveWallpaperService, LiveWallpaperTarget.GROUPED)) return
            Log.d(TAG, "advance.catchup")
            LiveWallpaperRefillScheduler.enqueueAdvanceRefill(this@GroupedLiveWallpaperService, LiveWallpaperTarget.GROUPED)
        }

        /** Opens the grouped wallpaper's view page, like Muzei's artwork view. */
        private fun openViewPage() {
            GroupedWallpaperAppBridge.requestView(this@GroupedLiveWallpaperService)
        }

        override fun onDestroy() {
            Log.d(TAG, "engine.destroy")
            if (!isPreview) {
                try {
                    applicationContext.unregisterReceiver(lockScreenReceiver)
                } catch (e: IllegalArgumentException) {
                    // Already unregistered with the engine.
                    Log.d(TAG, "lock screen receiver was not registered", e)
                }
            }
            if (::renderer.isInitialized) {
                queueEvent { renderer.destroy() }
            }
            if (!isPreview) this@GroupedLiveWallpaperService.onRealEngineDestroyed()
            super.onDestroy()
        }

        private fun registerLockScreenReceiver() {
            val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            lockScreenVisible = keyguard.isKeyguardLocked
            // A picker preview owns a temporary surface and is torn down when the
            // picker closes: letting it register would overwrite the real
            // wallpaper's keyguard state and post the bar from a preview. It still
            // reads the current state, so it is drawn with the effect the lock
            // screen would use.
            if (isPreview) return
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_USER_PRESENT)
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_SCREEN_ON)
            }
            applicationContext.registerReceiver(lockScreenReceiver, filter)
            GroupedLiveWallpaperService.lockScreenVisible = lockScreenVisible
        }

        private fun updateLockScreen(visible: Boolean) {
            if (lockScreenVisible == visible) return
            lockScreenVisible = visible
            if (::renderer.isInitialized) renderer.setLockScreenVisible(visible)
            if (isPreview) return
            GroupedLiveWallpaperService.lockScreenVisible = visible
            // Locking or unlocking returns the bar to its default button set; the
            // user's switch applies until the keyguard changes.
            GroupedWallpaperNotification.resetGroupActionsOverride()
            this@GroupedLiveWallpaperService.updateNotification()
            // The keyguard is a visibility signal of its own: some launchers do
            // not call onVisibilityChanged for the lock surface, so a deferred
            // advance is also picked up here.
            if (visible) requestPendingAdvance()
        }
    }
}
