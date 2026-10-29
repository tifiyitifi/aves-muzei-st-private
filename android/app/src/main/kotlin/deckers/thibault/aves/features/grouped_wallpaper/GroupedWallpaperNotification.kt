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
     */
    const val CHANNEL_ID = "grouped_wallpaper_v3"

    /** Older channels, deleted so an upgraded install does not keep a silent one. */
    private val LEGACY_CHANNEL_IDS = listOf("grouped_wallpaper", "grouped_wallpaper_v2")

    const val NOTIFICATION_ID = 3

    /** The app route of the wallpaper group page. */
    private const val GROUP_PAGE_ROUTE = "/wallpaper_groups"

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
        val lockScreen = (context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager).isKeyguardLocked
        groupActionsOverride = !(groupActionsOverride ?: lockScreen)
    }

    /** Returns to the keyguard's default set, after locking or unlocking. */
    fun resetGroupActionsOverride() {
        groupActionsOverride = null
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

        val lockScreen = (context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager).isKeyguardLocked
        val groupActions = groupActionsOverride ?: lockScreen
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

    private fun contentIntent(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .putExtra(MainActivity.EXTRA_KEY_PAGE, GROUP_PAGE_ROUTE)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun actionIntent(context: Context, action: String, requestCode: Int): PendingIntent = PendingIntent.getBroadcast(
        context,
        requestCode,
        Intent(context, GroupedWallpaperActionReceiver::class.java).setAction(action),
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
            entryButtons(context, big, ready)
        }
        for (button in buttons) {
            views.setImageViewResource(button.viewId, button.iconRes)
            views.setContentDescription(button.viewId, button.contentDescription)
            views.setViewVisibility(button.viewId, View.VISIBLE)
            views.setInt(button.viewId, "setAlpha", if (button.enabled) 255 else 100)
            val action = button.action
            views.setOnClickPendingIntent(
                button.viewId,
                if (button.enabled && action != null) actionIntent(context, action, requestCode(action)) else null,
            )
        }
        return views
    }

    /**
     * Unlocked layout: photo actions, plus the copy/record placeholders.
     *
     * The placeholders keep Aves-ST's icons but stay disabled until the feature
     * exists, exactly as the batch plan requires.
     */
    private fun entryButtons(context: Context, big: Boolean, ready: Boolean): List<NotificationButton> {
        val previous = NotificationButton(
            R.id.grouped_notification_button_1,
            R.drawable.baseline_pre_24,
            ACTION_PREVIOUS_ARTWORK,
            context.getString(R.string.grouped_wallpaper_action_previous),
            enabled = ready,
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
            enabled = false,
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
                enabled = ready,
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
                enabled = false,
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
        )
        val nextGroup = NotificationButton(
            R.id.grouped_notification_button_2,
            R.drawable.baseline_arrow_upward_24,
            ACTION_NEXT_GROUP,
            context.getString(R.string.grouped_wallpaper_action_next_group),
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
            ),
            NotificationButton(
                R.id.grouped_notification_button_3,
                R.drawable.baseline_arrow_upward_24,
                ACTION_NEXT_GROUP,
                context.getString(R.string.grouped_wallpaper_action_next_group),
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

    private fun badgeColor(number: Int): Int = badgeColors[(number.coerceAtLeast(0)) % badgeColors.size]
}
