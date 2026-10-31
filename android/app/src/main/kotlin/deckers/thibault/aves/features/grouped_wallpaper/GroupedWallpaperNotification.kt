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
import android.app.Notification
import android.app.PendingIntent
import android.app.WallpaperManager
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import deckers.thibault.aves.MainActivity
import deckers.thibault.aves.R

/**
 * The grouped wallpaper's notification, styled after Aves-ST's `fgw` bar.
 *
 * The layout family follows the keyguard: unlocked shows photo actions
 * (previous/next photo, plus the two copy/record placeholders), locked shows
 * group actions (previous/next group, lock, next photo). The expanded bar's
 * first button switches between the two sets, like the reference bar, so group
 * actions are reachable while unlocked too. The badge carries the group number,
 * the title the group name and the subtitle the photo on screen, so the
 * notification is useful without opening the app.
 *
 * A group switch and a lock are decided here, before the app has done any work:
 * switching only needs the rotation carried by `state.json`, and locking only
 * needs the group on screen. Both are shown at once and persisted in the
 * background, so the bar never appears to ignore a tap.
 *
 * The notification is posted by [GroupedLiveWallpaperService] only while it is
 * the system wallpaper; turning the grouped wallpaper off cancels it.
 */
object GroupedWallpaperNotification {
    private const val TAG = "AvesGroupedWallpaper"

    /**
     * Channel of the wallpaper bar.
     *
     * MIUI hides a silent notification on the lock screen even when it belongs to
     * a foreground service, so this channel keeps the system's default sound. The
     * notification itself is `setOnlyAlertOnce`, so a frame update never beeps:
     * only the first post after the service starts does. A channel's sound cannot
     * be changed after creation, hence the version suffix.
     *
     * The id must never change again. Some devices only show a channel on the lock
     * screen after the user marks it as important, and that choice is stored per
     * channel id: a new id would silently drop it and bring back the "no bar on
     * the lock screen" report.
     */
    const val CHANNEL_ID = "grouped_wallpaper_v3"

    /** Older channels, deleted so an upgraded install does not keep a silent one. */
    private val LEGACY_CHANNEL_IDS = listOf("grouped_wallpaper", "grouped_wallpaper_v2")

    const val NOTIFICATION_ID = 3

    /**
     * Id of the "the wallpaper stopped" hint.
     *
     * It is not the bar: the bar only exists while the wallpaper is bound, and this
     * notification exists exactly when it is not, so the two never replace each
     * other.
     */
    private const val RESTORE_HINT_ID = 0x5757

    /** The app route of the immersive wallpaper view. */
    private const val VIEW_ROUTE = "/grouped_wallpaper/view"

    /** The app route of the usage history. */
    private const val HISTORY_ROUTE = "/grouped_wallpaper/history"

    /** The app route of the wallpaper group page, where the wallpaper is applied. */
    private const val GROUPS_ROUTE = "/wallpaper_groups"

    // Broadcast actions handled by GroupedWallpaperActionReceiver.
    const val ACTION_PREVIOUS_ARTWORK = "deckers.thibault.aves.grouped_wallpaper.PREVIOUS_ARTWORK"
    const val ACTION_NEXT_ARTWORK = "deckers.thibault.aves.grouped_wallpaper.NEXT_ARTWORK"
    const val ACTION_PREVIOUS_GROUP = "deckers.thibault.aves.grouped_wallpaper.PREVIOUS_GROUP"
    const val ACTION_NEXT_GROUP = "deckers.thibault.aves.grouped_wallpaper.NEXT_GROUP"

    /** Locks the group on screen, or opens the group that is already locked. */
    const val ACTION_TOGGLE_GROUP_LOCK = "deckers.thibault.aves.grouped_wallpaper.TOGGLE_GROUP_LOCK"

    /** Switches the button set; it no longer opens the group page. */
    const val ACTION_SWITCH_ACTIONS = "deckers.thibault.aves.grouped_wallpaper.SWITCH_ACTIONS"

    /**
     * How long a switch feedback stays when the new frame never arrives.
     *
     * A bake can fail; without a deadline the bar would keep saying "switching"
     * forever instead of returning to the group that is really drawing.
     */
    private const val PENDING_SWITCH_TIMEOUT_MILLIS = 20_000L

    /**
     * How long a lock may stay pending before the bar stops claiming it.
     *
     * The request file is the source of truth and is adopted on the next start,
     * so the flag only decides what the bar shows in the meantime.
     */
    private const val PENDING_LOCK_TIMEOUT_MILLIS = 30_000L

    private class PendingSwitch(
        val targetGroupId: String,
        val targetNumber: Int,
        val targetName: String,
        val fromNumber: Int,
        val fromName: String,
    )

    @Volatile
    private var pendingSwitch: PendingSwitch? = null

    @Volatile
    private var pendingSwitchAt = 0L

    @Volatile
    private var pendingLockGroupId: String? = null

    @Volatile
    private var pendingLockAt = 0L

    private val handler = Handler(Looper.getMainLooper())

    /** Used to re-post from the timeout, when no service is holding a context. */
    @Volatile
    private var appContext: Context? = null

    private val clearStaleState = Runnable {
        val now = SystemClock.elapsedRealtime()
        var changed = false
        if (pendingSwitch != null && now - pendingSwitchAt > PENDING_SWITCH_TIMEOUT_MILLIS) {
            pendingSwitch = null
            changed = true
        }
        if (pendingLockGroupId != null && now - pendingLockAt > PENDING_LOCK_TIMEOUT_MILLIS) {
            pendingLockGroupId = null
            changed = true
        }
        if (changed) {
            Log.d(TAG, "notification.pending cleared by timeout")
            appContext?.let { refresh(it) }
        }
    }

    /** Badge colours; the group number picks one, so a group keeps its colour. */
    private val badgeColors = intArrayOf(
        0xFFF6BF26.toInt(),
        0xFF8AB4F8.toInt(),
        0xFF81C995.toInt(),
        0xFFF28B82.toInt(),
        0xFFC58AF9.toInt(),
        0xFF78D9EC.toInt(),
        0xFFFCAD70.toInt(),
        0xFFD7AEFB.toInt(),
    )

    private class NotificationButton(
        val viewId: Int,
        val iconRes: Int,
        val action: String?,
        val contentDescription: CharSequence,
        val enabled: Boolean = true,
        /** An app route to open instead of broadcasting [action]. */
        val page: String? = null,
    )

    fun ensureChannel(context: Context) {
        val channel = NotificationChannelCompat.Builder(CHANNEL_ID, NotificationManagerCompat.IMPORTANCE_HIGH)
            .setName(context.getString(R.string.grouped_wallpaper_channel_name))
            .setShowBadge(false)
            // MIUI's lock screen filters silent notifications out, even foreground
            // ones. The notification is `setOnlyAlertOnce`, so frame updates stay
            // quiet and only the first post after the service starts alerts.
            .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION), null)
            .setVibrationEnabled(false)
            .build()
        val manager = NotificationManagerCompat.from(context)
        manager.createNotificationChannel(channel)
        LEGACY_CHANNEL_IDS.forEach { manager.deleteNotificationChannel(it) }
    }

    /**
     * A user toggle that switches the button set, or null to follow the keyguard.
     *
     * It mirrors the reference bar's "switch" action: the same five buttons are
     * reachable on the lock screen and while unlocked, instead of group actions
     * being locked to the keyguard.
     */
    @Volatile
    private var groupActionsOverride: Boolean? = null

    /** Switches between the photo actions and the group actions. */
    fun toggleGroupActions(context: Context) {
        groupActionsOverride = !usesGroupActions(context)
    }

    /** Returns to the keyguard's default set, after locking or unlocking. */
    fun resetGroupActionsOverride() {
        groupActionsOverride = null
    }

    /**
     * Shows a group switch at once and returns the target group, or null.
     *
     * The app still owns the switch (it has to move the current group and bake
     * the next frame), but that takes a bake. Showing the target here is what
     * makes the tap feel acknowledged instead of ignored.
     */
    fun beginGroupSwitch(context: Context, delta: Int): GroupedWallpaperGroupFile? {
        val state = GroupedWallpaperStateFile.read(context) ?: return null
        val target = targetGroup(state, delta) ?: return null
        if (target.id == state.groupId) return null
        pendingSwitch = PendingSwitch(
            targetGroupId = target.id,
            targetNumber = target.number,
            targetName = target.name,
            fromNumber = state.groupNumber,
            fromName = state.groupName,
        )
        pendingSwitchAt = SystemClock.elapsedRealtime()
        scheduleTimeout()
        Log.i(TAG, "notification.switch from=${state.groupId} to=${target.id}")
        refresh(context)
        return target
    }

    /**
     * Shows the lock at once and records the request for the app.
     *
     * @return whether there is a group to lock.
     */
    fun beginGroupLock(context: Context): Boolean {
        val state = GroupedWallpaperStateFile.read(context) ?: return false
        if (state.groupId.isEmpty()) return false
        // The file is the durable half: the app adopts it even if it was not
        // listening, so a lock tapped while it slept is never lost.
        GroupedWallpaperStateFile.writeLockRequest(context, state.groupId)
        pendingLockGroupId = state.groupId
        pendingLockAt = SystemClock.elapsedRealtime()
        scheduleTimeout()
        Log.i(TAG, "notification.lock group=${state.groupId}")
        refresh(context)
        return true
    }

    /** Re-posts the bar from the state on disk. */
    fun refresh(context: Context) {
        if (GroupedLiveWallpaperService.isRunning) {
            GroupedLiveWallpaperService.refreshNotification()
            return
        }
        val state = GroupedWallpaperStateFile.read(context) ?: return
        update(context, state, state.currentSlot)
    }

    private fun scheduleTimeout() {
        handler.removeCallbacks(clearStaleState)
        handler.postDelayed(clearStaleState, PENDING_SWITCH_TIMEOUT_MILLIS)
    }

    /** The group a switch from [state] lands on, skipping disabled ones. */
    private fun targetGroup(state: GroupedWallpaperFileState, delta: Int): GroupedWallpaperGroupFile? {
        val groups = state.groups
        if (groups.isEmpty()) return null
        val index = groups.indexOfFirst { it.id == state.groupId }
        // From group 0, "next" enters at the first group and "previous" at the last,
        // exactly like the engine's own rotation.
        val start = if (index >= 0) index else if (delta > 0) -1 else 0
        val raw = (start + delta) % groups.size
        return groups[if (raw < 0) raw + groups.size else raw]
    }

    /**
     * The switch the bar should still show, or null once it has arrived.
     *
     * Cleared here (not only on a timer) so a state that names the target ends the
     * feedback in the same pass that reads it.
     */
    private fun pendingSwitchFor(state: GroupedWallpaperFileState): PendingSwitch? {
        val pending = pendingSwitch ?: return null
        if (state.groupId == pending.targetGroupId || SystemClock.elapsedRealtime() - pendingSwitchAt > PENDING_SWITCH_TIMEOUT_MILLIS) {
            pendingSwitch = null
            return null
        }
        return pending
    }

    /** Whether the bar should offer the locked or the unlocked lock icon. */
    private fun lockedFor(state: GroupedWallpaperFileState): Boolean {
        if (state.switchLocked) {
            // The lock is persisted: a pending one for the same group has done its
            // job and must not outlive it.
            pendingLockGroupId = null
            return true
        }
        if (pendingLockGroupId == null) return false
        if (SystemClock.elapsedRealtime() - pendingLockAt > PENDING_LOCK_TIMEOUT_MILLIS) {
            pendingLockGroupId = null
            return false
        }
        return true
    }

    /** Drops the pending overlays, so a fresh service starts from the state. */
    fun resetPending() {
        pendingSwitch = null
        pendingLockGroupId = null
        handler.removeCallbacks(clearStaleState)
    }

    private fun isKeyguardLocked(context: Context): Boolean = (context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager).isKeyguardLocked

    /** The button set on screen: the user's switch, or the keyguard's default. */
    private fun usesGroupActions(context: Context): Boolean = groupActionsOverride ?: isKeyguardLocked(context)

    /**
     * Everything the bar shows, as one string.
     *
     * The service re-reads `state.json` on every frame load, and re-posting an
     * unchanged bar hundreds of times a day is what made MIUI rate-limit the
     * app's notifications (and then hide them on the lock screen). Posting only
     * when this key changes keeps the bar identical on screen while the counter
     * stays quiet.
     */
    fun contentKey(context: Context, state: GroupedWallpaperFileState, slot: GroupedWallpaperSlotFile?): String = buildString {
        append(state.status).append('|')
        append(state.groupNumber).append('|')
        append(state.groupName).append('|')
        // The limit greys the "previous" button, so it is part of what the bar
        // shows: without it a changed limit would not re-post the bar.
        append(state.historyLimit).append('|')
        // The stack can be exhausted without the limit changing.
        append(state.canPrevious).append('|')
        // The lock greys the group buttons, so it is part of what the bar shows.
        // A pending lock is part of it too: the tap has to show at once.
        append(lockedFor(state)).append('|')
        // The switch feedback lasts a bake, and ends when the target arrives.
        val pending = pendingSwitchFor(state)
        append(pending?.targetGroupId ?: "").append('|')
        append(usesGroupActions(context)).append('|')
        append(slot?.id ?: -1).append('|')
        append(slot?.entryId ?: -1).append('|')
        append(slot?.title ?: "")
    }

    /**
     * Posts or updates the notification for [state].
     *
     * [slot] is the photo on screen, which can be a slot the renderer promoted
     * natively before Dart wrote a new state. It is null when nothing is baked.
     */
    fun update(context: Context, state: GroupedWallpaperFileState, slot: GroupedWallpaperSlotFile?) {
        if (state.status == GroupedWallpaperFileState.STATUS_DISABLED) {
            cancel(context)
            return
        }
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return

        val notification = build(context, state, slot) ?: return
        try {
            manager.notify(NOTIFICATION_ID, notification)
        } catch (t: Throwable) {
            // A missing POST_NOTIFICATIONS grant or a disabled channel must never
            // take the wallpaper service down.
            Log.w(TAG, "failed to post the grouped wallpaper notification", t)
        }
    }

    /**
     * Builds the notification for [state], or null when the wallpaper is off.
     *
     * [GroupedLiveWallpaperService] passes it to `startForeground`; [update] posts
     * the same notification outside the foreground-service path.
     */
    fun build(context: Context, state: GroupedWallpaperFileState, slot: GroupedWallpaperSlotFile?): Notification? {
        if (state.status == GroupedWallpaperFileState.STATUS_DISABLED) return null
        ensureChannel(context)
        appContext = context.applicationContext

        val groupActions = usesGroupActions(context)
        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(contentIntent(context))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            // The content is the wallpaper's own group and photo name, so it can
            // stay readable on the lock screen instead of being redacted.
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            // Android 12+ otherwise holds a foreground-service notification back
            // for about ten seconds, which reads as "the lock screen has no bar".
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setCustomContentView(buildViews(context, big = false, groupActions = groupActions, state = state, slot = slot))
            .setCustomBigContentView(buildViews(context, big = true, groupActions = groupActions, state = state, slot = slot))
            .build()
    }

    /**
     * Cancels the notification.
     *
     * This cannot remove a foreground-service notification: the service has to
     * call `stopForeground` first, which it does when the wallpaper is turned off.
     */
    fun cancel(context: Context) {
        try {
            NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
        } catch (t: Throwable) {
            Log.w(TAG, "failed to cancel the grouped wallpaper notification", t)
        }
    }

    /**
     * Tells the user the wallpaper stopped, and where to bring it back.
     *
     * Only the fallback: when the wallpaper can be bound silently there is nothing
     * to announce. It shares the bar's channel so the two do not split into two
     * entries in the system's notification settings.
     */
    fun postRestoreHint(context: Context) {
        ensureChannel(context)
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.grouped_wallpaper_restore_hint_title))
            .setContentText(context.getString(R.string.grouped_wallpaper_restore_hint_text))
            .setContentIntent(pageIntent(context, GROUPS_ROUTE, pageRequestCode(GROUPS_ROUTE)))
            .addAction(0, context.getString(R.string.grouped_wallpaper_restore_hint_action), chooserIntent(context))
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .build()
        try {
            manager.notify(RESTORE_HINT_ID, notification)
        } catch (t: Throwable) {
            // A missing POST_NOTIFICATIONS grant must never fail the restore path.
            Log.w(TAG, "failed to post the grouped wallpaper restore hint", t)
        }
    }

    /** Drops the hint, because the wallpaper is bound again or the user acted on it. */
    fun cancelRestoreHint(context: Context) {
        try {
            NotificationManagerCompat.from(context).cancel(RESTORE_HINT_ID)
        } catch (t: Throwable) {
            Log.w(TAG, "failed to cancel the grouped wallpaper restore hint", t)
        }
    }

    /**
     * Opens the system's live wallpaper list.
     *
     * The generic chooser is used rather than the per-component preview: MIUI closes
     * that preview immediately, so the action would look like it did nothing.
     */
    private fun chooserIntent(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        10,
        Intent(WallpaperManager.ACTION_LIVE_WALLPAPER_CHOOSER).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /**
     * Opens the immersive view of the photo on screen, like the three-finger
     * gesture does: the app puts the playing group's page below the view, so back
     * walks to the wallpaper page instead of closing the app.
     */
    private fun contentIntent(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .putExtra(MainActivity.EXTRA_KEY_PAGE, VIEW_ROUTE)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun actionIntent(context: Context, action: String, requestCode: Int): PendingIntent = PendingIntent.getBroadcast(
        context,
        requestCode,
        Intent(context, GroupedWallpaperActionReceiver::class.java).setAction(action),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /**
     * Opens an app page from a button.
     *
     * The bar cannot broadcast this: the page has to be pushed over the app, so
     * the intent is the same cold-start route the notification's content uses.
     */
    private fun pageIntent(context: Context, page: String, requestCode: Int): PendingIntent = PendingIntent.getActivity(
        context,
        requestCode,
        Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .putExtra(MainActivity.EXTRA_KEY_PAGE, page)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun buildViews(
        context: Context,
        big: Boolean,
        groupActions: Boolean,
        state: GroupedWallpaperFileState,
        slot: GroupedWallpaperSlotFile?,
    ): RemoteViews {
        val layout = if (big) R.layout.grouped_wallpaper_notification_big else R.layout.grouped_wallpaper_notification_normal
        val views = RemoteViews(context.packageName, layout)
        val pending = pendingSwitchFor(state)
        val switching = pending != null
        val ready = state.status == GroupedWallpaperFileState.STATUS_READY && !switching
        val fallback = context.getString(R.string.grouped_wallpaper_notification_fallback_title)

        val badge = when {
            pending != null -> pending.targetNumber
            slot == null -> null
            else -> state.groupNumber
        }
        views.setTextViewText(
            R.id.grouped_notification_status,
            if (badge == null) context.getString(R.string.grouped_wallpaper_notification_badge_empty) else badge.toString(),
        )
        views.setInt(R.id.grouped_notification_status, "setBackgroundColor", badgeColor(badge ?: state.groupNumber))
        views.setTextViewText(
            R.id.grouped_notification_title,
            if (switching) {
                context.getString(R.string.grouped_wallpaper_switching_title)
            } else {
                state.groupName.ifBlank { fallback }
            },
        )
        views.setTextViewText(
            R.id.grouped_notification_text,
            when {
                pending != null -> context.getString(
                    R.string.grouped_wallpaper_switching_text,
                    pending.fromNumber,
                    pending.fromName.ifBlank { fallback },
                    pending.targetNumber,
                    pending.targetName.ifBlank { fallback },
                )
                slot == null -> context.getString(R.string.grouped_wallpaper_notification_no_photo)
                else -> slot.title.ifBlank { fallback }
            },
        )

        val buttons = if (groupActions) {
            levelButtons(context, big, state, ready, switching)
        } else {
            // With recording off the engine refuses "previous", so the bar greys
            // the button instead of offering an action that does nothing.
            entryButtons(context, big, ready, canPrevious = ready && state.canPrevious)
        }
        for (button in buttons) {
            views.setImageViewResource(button.viewId, button.iconRes)
            views.setContentDescription(button.viewId, button.contentDescription)
            views.setViewVisibility(button.viewId, View.VISIBLE)
            views.setInt(button.viewId, "setAlpha", if (button.enabled) 255 else 100)
            val pendingIntent = when {
                !button.enabled -> null
                button.page != null -> pageIntent(context, button.page, pageRequestCode(button.page))
                button.action != null -> actionIntent(context, button.action, requestCode(button.action))
                else -> null
            }
            views.setOnClickPendingIntent(button.viewId, pendingIntent)
        }
        return views
    }

    /**
     * Unlocked layout: photo actions, plus the copy/record placeholders.
     *
     * The placeholders keep Aves-ST's icons but stay disabled until the feature
     * exists, exactly as the batch plan requires.
     */
    private fun entryButtons(context: Context, big: Boolean, ready: Boolean, canPrevious: Boolean): List<NotificationButton> {
        val previous = NotificationButton(
            R.id.grouped_notification_button_1,
            R.drawable.baseline_pre_24,
            ACTION_PREVIOUS_ARTWORK,
            context.getString(R.string.grouped_wallpaper_action_previous),
            enabled = canPrevious,
        )
        val next = NotificationButton(
            R.id.grouped_notification_button_2,
            R.drawable.baseline_next_24,
            ACTION_NEXT_ARTWORK,
            context.getString(R.string.grouped_wallpaper_action_next),
            enabled = ready,
        )
        val copy = NotificationButton(
            R.id.grouped_notification_button_3,
            R.drawable.baseline_copy_all_24,
            null,
            context.getString(R.string.grouped_wallpaper_action_copy),
            enabled = false,
        )
        val used = NotificationButton(
            R.id.grouped_notification_button_4,
            R.drawable.baseline_auto_stories_24,
            null,
            context.getString(R.string.grouped_wallpaper_action_used),
            page = HISTORY_ROUTE,
        )
        if (!big) return listOf(previous, next, copy, used)
        return listOf(
            NotificationButton(
                R.id.grouped_notification_button_1,
                R.drawable.baseline_menu_open_24,
                ACTION_SWITCH_ACTIONS,
                context.getString(R.string.grouped_wallpaper_action_switch_actions),
            ),
            NotificationButton(
                R.id.grouped_notification_button_2,
                R.drawable.baseline_pre_24,
                ACTION_PREVIOUS_ARTWORK,
                context.getString(R.string.grouped_wallpaper_action_previous),
                enabled = canPrevious,
            ),
            NotificationButton(
                R.id.grouped_notification_button_3,
                R.drawable.baseline_next_24,
                ACTION_NEXT_ARTWORK,
                context.getString(R.string.grouped_wallpaper_action_next),
                enabled = ready,
            ),
            NotificationButton(
                R.id.grouped_notification_button_4,
                R.drawable.baseline_copy_all_24,
                null,
                context.getString(R.string.grouped_wallpaper_action_copy),
                enabled = false,
            ),
            NotificationButton(
                R.id.grouped_notification_button_5,
                R.drawable.baseline_auto_stories_24,
                null,
                context.getString(R.string.grouped_wallpaper_action_used),
                page = HISTORY_ROUTE,
            ),
        )
    }

    /**
     * Locked layout: group actions and the group lock.
     *
     * The lock is the group-switch lock, not a freeze: tapping it while unlocked
     * locks the group at once, and tapping it while locked opens the page that
     * asks for the PIN. The group buttons grey out as soon as the lock is set, so
     * the bar never offers a switch the app would refuse.
     */
    private fun levelButtons(context: Context, big: Boolean, state: GroupedWallpaperFileState, ready: Boolean, switching: Boolean): List<NotificationButton> {
        val locked = lockedFor(state)
        val canSwitch = !locked && !switching
        val previousGroup = NotificationButton(
            R.id.grouped_notification_button_1,
            R.drawable.baseline_arrow_downward_24,
            ACTION_PREVIOUS_GROUP,
            context.getString(R.string.grouped_wallpaper_action_previous_group),
            enabled = canSwitch,
        )
        val nextGroup = NotificationButton(
            R.id.grouped_notification_button_2,
            R.drawable.baseline_arrow_upward_24,
            ACTION_NEXT_GROUP,
            context.getString(R.string.grouped_wallpaper_action_next_group),
            enabled = canSwitch,
        )
        val lock = NotificationButton(
            R.id.grouped_notification_button_3,
            if (locked) R.drawable.baseline_lock_24 else R.drawable.baseline_lock_open_24,
            ACTION_TOGGLE_GROUP_LOCK,
            context.getString(if (locked) R.string.grouped_wallpaper_action_unlock else R.string.grouped_wallpaper_action_lock),
            enabled = locked || ready,
        )
        val next = NotificationButton(
            R.id.grouped_notification_button_4,
            R.drawable.baseline_next_24,
            ACTION_NEXT_ARTWORK,
            context.getString(R.string.grouped_wallpaper_action_next),
            enabled = ready,
        )
        if (!big) return listOf(previousGroup, nextGroup, lock, next)
        return listOf(
            NotificationButton(
                R.id.grouped_notification_button_1,
                R.drawable.baseline_menu_open_24,
                ACTION_SWITCH_ACTIONS,
                context.getString(R.string.grouped_wallpaper_action_switch_actions),
            ),
            NotificationButton(
                R.id.grouped_notification_button_2,
                R.drawable.baseline_arrow_downward_24,
                ACTION_PREVIOUS_GROUP,
                context.getString(R.string.grouped_wallpaper_action_previous_group),
                enabled = canSwitch,
            ),
            NotificationButton(
                R.id.grouped_notification_button_3,
                R.drawable.baseline_arrow_upward_24,
                ACTION_NEXT_GROUP,
                context.getString(R.string.grouped_wallpaper_action_next_group),
                enabled = canSwitch,
            ),
            NotificationButton(
                R.id.grouped_notification_button_4,
                if (locked) R.drawable.baseline_lock_24 else R.drawable.baseline_lock_open_24,
                ACTION_TOGGLE_GROUP_LOCK,
                context.getString(if (locked) R.string.grouped_wallpaper_action_unlock else R.string.grouped_wallpaper_action_lock),
                enabled = locked || ready,
            ),
            NotificationButton(
                R.id.grouped_notification_button_5,
                R.drawable.baseline_next_24,
                ACTION_NEXT_ARTWORK,
                context.getString(R.string.grouped_wallpaper_action_next),
                enabled = ready,
            ),
        )
    }

    private fun requestCode(action: String): Int = when (action) {
        ACTION_PREVIOUS_ARTWORK -> 1
        ACTION_NEXT_ARTWORK -> 2
        ACTION_PREVIOUS_GROUP -> 3
        ACTION_NEXT_GROUP -> 4
        ACTION_TOGGLE_GROUP_LOCK -> 5
        else -> 6
    }

    /**
     * A stable request code per page, so two page buttons never share one
     * `PendingIntent` and overwrite each other's route.
     */
    private fun pageRequestCode(page: String): Int = when (page) {
        HISTORY_ROUTE -> 7
        VIEW_ROUTE -> 8
        else -> 9
    }

    private fun badgeColor(number: Int): Int = badgeColors[(number.coerceAtLeast(0)) % badgeColors.size]
}
