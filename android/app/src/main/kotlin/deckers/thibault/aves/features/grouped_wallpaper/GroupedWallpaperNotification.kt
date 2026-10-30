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
 * group actions (previous/next group, freeze, next photo). The expanded bar's
 * first button switches between the two sets, like the reference bar, so group
 * actions are reachable while unlocked too. The badge carries the group number,
 * the title the group name and the subtitle the photo on screen, so the
 * notification is useful without opening the app.
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
    const val ACTION_TOGGLE_PAUSE = "deckers.thibault.aves.grouped_wallpaper.TOGGLE_PAUSE"

    /** Switches the button set; it no longer opens the group page. */
    const val ACTION_SWITCH_ACTIONS = "deckers.thibault.aves.grouped_wallpaper.SWITCH_ACTIONS"

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
        append(state.paused).append('|')
        // The limit greys the "previous" button, so it is part of what the bar
        // shows: without it a changed limit would not re-post the bar.
        append(state.historyLimit).append('|')
        // The lock greys the group buttons, so it is part of what the bar shows.
        append(state.switchLocked).append('|')
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
        val ready = state.status == GroupedWallpaperFileState.STATUS_READY

        val number = state.groupNumber
        views.setTextViewText(
            R.id.grouped_notification_status,
            if (slot == null) context.getString(R.string.grouped_wallpaper_notification_badge_empty) else number.toString(),
        )
        views.setInt(R.id.grouped_notification_status, "setBackgroundColor", badgeColor(number))
        views.setTextViewText(
            R.id.grouped_notification_title,
            state.groupName.ifBlank { context.getString(R.string.grouped_wallpaper_notification_fallback_title) },
        )
        views.setTextViewText(
            R.id.grouped_notification_text,
            if (slot == null) {
                context.getString(R.string.grouped_wallpaper_notification_no_photo)
            } else {
                slot.title.ifBlank { context.getString(R.string.grouped_wallpaper_notification_fallback_title) }
            },
        )

        val buttons = if (groupActions) {
            levelButtons(context, big, state, ready)
        } else {
            // With recording off the engine refuses "previous", so the bar greys
            // the button instead of offering an action that does nothing.
            entryButtons(context, big, ready, canPrevious = ready && state.historyLimit > 0)
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
     * Locked layout: group actions and the freeze toggle.
     *
     * A frozen wallpaper shows the closed lock, so the same button resumes it;
     * a playing wallpaper shows the open lock and freezes it, like Aves-ST's
     * guard-level lock.
     */
    private fun levelButtons(context: Context, big: Boolean, state: GroupedWallpaperFileState, ready: Boolean): List<NotificationButton> {
        val previousGroup = NotificationButton(
            R.id.grouped_notification_button_1,
            R.drawable.baseline_arrow_downward_24,
            ACTION_PREVIOUS_GROUP,
            context.getString(R.string.grouped_wallpaper_action_previous_group),
            enabled = !state.switchLocked,
        )
        val nextGroup = NotificationButton(
            R.id.grouped_notification_button_2,
            R.drawable.baseline_arrow_upward_24,
            ACTION_NEXT_GROUP,
            context.getString(R.string.grouped_wallpaper_action_next_group),
            enabled = !state.switchLocked,
        )
        val freeze = NotificationButton(
            R.id.grouped_notification_button_3,
            if (state.paused) R.drawable.baseline_lock_24 else R.drawable.baseline_lock_open_24,
            ACTION_TOGGLE_PAUSE,
            context.getString(if (state.paused) R.string.grouped_wallpaper_action_resume else R.string.grouped_wallpaper_action_freeze),
            enabled = ready,
        )
        val next = NotificationButton(
            R.id.grouped_notification_button_4,
            R.drawable.baseline_next_24,
            ACTION_NEXT_ARTWORK,
            context.getString(R.string.grouped_wallpaper_action_next),
            enabled = ready,
        )
        if (!big) return listOf(previousGroup, nextGroup, freeze, next)
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
                enabled = !state.switchLocked,
            ),
            NotificationButton(
                R.id.grouped_notification_button_3,
                R.drawable.baseline_arrow_upward_24,
                ACTION_NEXT_GROUP,
                context.getString(R.string.grouped_wallpaper_action_next_group),
                enabled = !state.switchLocked,
            ),
            NotificationButton(
                R.id.grouped_notification_button_4,
                if (state.paused) R.drawable.baseline_lock_24 else R.drawable.baseline_lock_open_24,
                ACTION_TOGGLE_PAUSE,
                context.getString(if (state.paused) R.string.grouped_wallpaper_action_resume else R.string.grouped_wallpaper_action_freeze),
                enabled = ready,
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
        ACTION_TOGGLE_PAUSE -> 5
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
