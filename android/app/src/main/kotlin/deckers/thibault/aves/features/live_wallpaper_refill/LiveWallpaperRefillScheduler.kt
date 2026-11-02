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

package deckers.thibault.aves.features.live_wallpaper_refill

import android.content.Context
import android.util.Log
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit

/**
 * Schedules the headless refill runs of both live wallpapers.
 *
 * Both bake in Dart, so without a worker a tap or an interval would only be
 * served while the app process is alive. WorkManager (not an alarm) because the
 * work is deferrable and must survive reboots; auto-advance is a chain of
 * one-time runs instead of periodic work so long intervals stay exact.
 *
 * Every entry point takes a [LiveWallpaperTarget], so one scheduler keeps the two
 * wallpapers apart: unique work names, callback prefs and intervals are per
 * target, and only the engine boot is shared.
 */
object LiveWallpaperRefillScheduler {
    private const val TAG = "AvesLiveWallpaper"

    /** The channel the app registers the callback on and the worker boots. */
    const val CHANNEL = "deckers.thibault/aves/live_wallpaper_refill"

    /** Shared with [LiveWallpaperRefillWorker] and `FlutterUtils.initFlutterEngine`. */
    const val SHARED_PREFERENCES_KEY = "live_wallpaper_refill_service"
    const val PREF_CALLBACK_HANDLE_KEY = "callback_handle"

    private const val PREF_AUTO_INTERVAL_PREFIX = "auto_interval_seconds_"

    private const val PREF_PENDING_ADVANCE_PREFIX = "auto_pending_advance_"

    private fun tapWorkName(target: LiveWallpaperTarget) = "live_wallpaper_${target.id}_tap_refill"

    private fun autoWorkName(target: LiveWallpaperTarget) = "live_wallpaper_${target.id}_auto_advance"

    private fun commandWorkName(target: LiveWallpaperTarget) = "live_wallpaper_${target.id}_command"

    private fun advanceWorkName(target: LiveWallpaperTarget) = "live_wallpaper_${target.id}_pending_advance"

    private fun intervalKey(target: LiveWallpaperTarget) = "$PREF_AUTO_INTERVAL_PREFIX${target.id}"

    private fun pendingAdvanceKey(target: LiveWallpaperTarget) = "$PREF_PENDING_ADVANCE_PREFIX${target.id}"

    /**
     * Bounds shared with Dart's `WallpaperAdvanceInterval`.
     *
     * `0` is off. The minimum keeps a WorkManager chain from re-arming
     * back-to-back; the maximum is 30 days, the longest custom value the app
     * offers. Clamping here means a bad saved value can never schedule work in
     * the far future or in a tight loop.
     */
    object AutoAdvanceInterval {
        const val MIN_SECONDS = 3
        const val MAX_SECONDS = 30 * 24 * 60 * 60

        fun clamp(seconds: Int): Int =
            if (seconds <= 0) 0 else seconds.coerceIn(MIN_SECONDS, MAX_SECONDS)
    }

    /** Persists the `vm:entry-point` callback handle the worker boots. */
    fun registerCallback(context: Context, callbackHandle: Long) {
        context.getSharedPreferences(SHARED_PREFERENCES_KEY, Context.MODE_PRIVATE)
            .edit()
            .putLong(PREF_CALLBACK_HANDLE_KEY, callbackHandle)
            .apply()
        Log.d(TAG, "refill.callback registered=${callbackHandle != 0L}")
    }

    /**
     * Starts one refill after a wallpaper tap that no running app could serve.
     *
     * `APPEND_OR_REPLACE` serializes bursts: a second tap waits for the running
     * bake instead of cancelling it, because the renderer replays its buffered
     * taps one per refill. [ensure] is used by the recovery path (a tap found no
     * prefetched slot), where a single pending run is enough and `KEEP` avoids
     * stacking one work per tap.
     *
     * Deliberately not expedited: on Android 12+ that runs the work as a
     * foreground service, which requires `getForegroundInfo()` and a
     * notification for a two-second bake. The user just tapped the wallpaper, so
     * a plain job still runs right away.
     */
    fun enqueueTapRefill(context: Context, target: LiveWallpaperTarget, ensure: Boolean = false) {
        val request = OneTimeWorkRequestBuilder<LiveWallpaperRefillWorker>()
            .setInputData(
                workDataOf(
                    LiveWallpaperRefillWorker.KEY_TARGET to target.id,
                    LiveWallpaperRefillWorker.KEY_ADVANCE to false,
                ),
            )
            .build()
        val policy = if (ensure) ExistingWorkPolicy.KEEP else ExistingWorkPolicy.APPEND_OR_REPLACE
        WorkManager.getInstance(context).enqueueUniqueWork(tapWorkName(target), policy, request)
        Log.d(TAG, "refill.enqueue target=${target.id} ensure=$ensure")
    }

    /**
     * Runs a notification command even when no app is alive.
     *
     * Commands change the saved group or the freeze flag, so they are queued
     * (`APPEND_OR_REPLACE`) instead of replaced: "next group" followed by "freeze"
     * must keep that order.
     */
    fun enqueueCommand(context: Context, target: LiveWallpaperTarget, command: String) {
        val request = OneTimeWorkRequestBuilder<LiveWallpaperRefillWorker>()
            .setInputData(
                workDataOf(
                    LiveWallpaperRefillWorker.KEY_TARGET to target.id,
                    LiveWallpaperRefillWorker.KEY_ADVANCE to false,
                    LiveWallpaperRefillWorker.KEY_COMMAND to command,
                ),
            )
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(commandWorkName(target), ExistingWorkPolicy.APPEND_OR_REPLACE, request)
        Log.d(TAG, "refill.command target=${target.id} command=$command")
    }

    /**
     * Remembers that an advance came due while the wallpaper was invisible.
     *
     * The bake is deferred instead of skipped: the next time the surface is
     * shown, [consumePendingAdvance] hands it to [enqueueAdvanceRefill]. This is
     * what keeps an interval from baking a dozen frames behind a two-hour video.
     */
    fun markPendingAdvance(context: Context, target: LiveWallpaperTarget) {
        context.getSharedPreferences(SHARED_PREFERENCES_KEY, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(pendingAdvanceKey(target), true)
            .apply()
    }

    fun hasPendingAdvance(context: Context, target: LiveWallpaperTarget): Boolean =
        context.getSharedPreferences(SHARED_PREFERENCES_KEY, Context.MODE_PRIVATE)
            .getBoolean(pendingAdvanceKey(target), false)

    /** Reads and clears the deferred advance, so one catch-up is enqueued. */
    fun consumePendingAdvance(context: Context, target: LiveWallpaperTarget): Boolean {
        val prefs = context.getSharedPreferences(SHARED_PREFERENCES_KEY, Context.MODE_PRIVATE)
        val key = pendingAdvanceKey(target)
        val pending = prefs.getBoolean(key, false)
        if (pending) prefs.edit().remove(key).apply()
        return pending
    }

    /**
     * Runs one advance now, used for the catch-up when the wallpaper reappears.
     *
     * `KEEP` would drop the run while an older one is still queued, so it uses
     * `APPEND_OR_REPLACE` like the tap refill: the catch-up must not be swallowed
     * by a tap that is already running.
     */
    fun enqueueAdvanceRefill(context: Context, target: LiveWallpaperTarget) {
        val request = OneTimeWorkRequestBuilder<LiveWallpaperRefillWorker>()
            .setInputData(
                workDataOf(
                    LiveWallpaperRefillWorker.KEY_TARGET to target.id,
                    LiveWallpaperRefillWorker.KEY_ADVANCE to true,
                ),
            )
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(advanceWorkName(target), ExistingWorkPolicy.APPEND_OR_REPLACE, request)
        Log.d(TAG, "refill.advance target=${target.id}")
    }

    /**
     * Applies the interval chosen in the app; `0` disables auto-advance.
     *
     * Reopening the page must not restart the countdown, so an unchanged
     * interval keeps the pending run (`KEEP`) while a changed one replaces it.
     */
    fun scheduleAutoAdvance(context: Context, target: LiveWallpaperTarget, seconds: Int) {
        val clamped = AutoAdvanceInterval.clamp(seconds)
        val prefs = context.getSharedPreferences(SHARED_PREFERENCES_KEY, Context.MODE_PRIVATE)
        val key = intervalKey(target)
        val previous = prefs.getInt(key, 0)
        val manager = WorkManager.getInstance(context)
        if (clamped <= 0) {
            // Turning the interval off also drops a deferred advance: re-enabling
            // it later must not bake for a schedule that was cancelled.
            prefs.edit().putInt(key, 0).remove(pendingAdvanceKey(target)).apply()
            manager.cancelUniqueWork(autoWorkName(target))
            Log.d(TAG, "auto.schedule target=${target.id} off")
            return
        }
        prefs.edit().putInt(key, clamped).apply()
        val request = OneTimeWorkRequestBuilder<LiveWallpaperRefillWorker>()
            .setInputData(
                workDataOf(
                    LiveWallpaperRefillWorker.KEY_TARGET to target.id,
                    LiveWallpaperRefillWorker.KEY_ADVANCE to true,
                ),
            )
            .setInitialDelay(clamped.toLong(), TimeUnit.SECONDS)
            .build()
        val policy = if (previous == clamped) ExistingWorkPolicy.KEEP else ExistingWorkPolicy.REPLACE
        manager.enqueueUniqueWork(autoWorkName(target), policy, request)
        Log.d(TAG, "auto.schedule target=${target.id} seconds=$clamped previous=$previous")
    }

    /**
     * Starts a fresh countdown after the user stepped previous/next by hand.
     *
     * Unlike [scheduleAutoAdvance], an unchanged interval is replaced: the step
     * is the user changing the wallpaper now, so the next automatic change must
     * be a full interval away instead of firing right after it.
     */
    fun restartAutoAdvance(context: Context, target: LiveWallpaperTarget, seconds: Int) {
        val clamped = AutoAdvanceInterval.clamp(seconds)
        val prefs = context.getSharedPreferences(SHARED_PREFERENCES_KEY, Context.MODE_PRIVATE)
        val key = intervalKey(target)
        if (clamped <= 0) {
            prefs.edit().putInt(key, 0).apply()
            WorkManager.getInstance(context).cancelUniqueWork(autoWorkName(target))
            Log.d(TAG, "auto.restart target=${target.id} off")
            return
        }
        prefs.edit().putInt(key, clamped).apply()
        val request = OneTimeWorkRequestBuilder<LiveWallpaperRefillWorker>()
            .setInputData(
                workDataOf(
                    LiveWallpaperRefillWorker.KEY_TARGET to target.id,
                    LiveWallpaperRefillWorker.KEY_ADVANCE to true,
                ),
            )
            .setInitialDelay(clamped.toLong(), TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(autoWorkName(target), ExistingWorkPolicy.REPLACE, request)
        Log.d(TAG, "auto.restart target=${target.id} seconds=$clamped")
    }

    /**
     * Starts the next countdown after a run.
     *
     * The finished run still owns the unique name, so this appends rather than
     * inserts; `KEEP` would see the running work and drop the next interval.
     */
    fun rescheduleAutoAdvance(context: Context, target: LiveWallpaperTarget) {
        val seconds = autoAdvanceInterval(context, target)
        if (seconds <= 0) return
        val request = OneTimeWorkRequestBuilder<LiveWallpaperRefillWorker>()
            .setInputData(
                workDataOf(
                    LiveWallpaperRefillWorker.KEY_TARGET to target.id,
                    LiveWallpaperRefillWorker.KEY_ADVANCE to true,
                ),
            )
            .setInitialDelay(seconds.toLong(), TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(autoWorkName(target), ExistingWorkPolicy.APPEND_OR_REPLACE, request)
        Log.d(TAG, "auto.reschedule target=${target.id} seconds=$seconds")
    }

    /** The interval currently scheduled for [target], or 0 when it is off. */
    fun autoAdvanceInterval(context: Context, target: LiveWallpaperTarget): Int =
        AutoAdvanceInterval.clamp(
            context.getSharedPreferences(SHARED_PREFERENCES_KEY, Context.MODE_PRIVATE)
                .getInt(intervalKey(target), 0),
        )
}
