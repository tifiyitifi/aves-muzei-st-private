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

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import deckers.thibault.aves.features.live_wallpaper_refill.LiveWallpaperRefillScheduler
import deckers.thibault.aves.features.live_wallpaper_refill.LiveWallpaperTarget

/**
 * Runs the grouped wallpaper notification's actions.
 *
 * A live wallpaper has no Activity and may not be running when the notification
 * is tapped, so actions are broadcasts rather than direct calls. "Next photo"
 * first tries the live renderer (instant, like a double tap); everything else
 * goes to the mounted app when it is listening and to the headless worker when
 * it is not.
 */
class GroupedWallpaperActionReceiver : BroadcastReceiver() {
    private companion object {
        const val TAG = "AvesGroupedWallpaper"

        const val COMMAND_PREVIOUS_ARTWORK = "previousArtwork"
        const val COMMAND_NEXT_ARTWORK = "nextArtwork"
        const val COMMAND_PREVIOUS_GROUP = "previousGroup"
        const val COMMAND_NEXT_GROUP = "nextGroup"
        const val COMMAND_PAUSE = "pause"
        const val COMMAND_RESUME = "resume"
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            GroupedWallpaperNotification.ACTION_NEXT_ARTWORK -> nextArtwork(context)
            GroupedWallpaperNotification.ACTION_PREVIOUS_ARTWORK -> command(context, COMMAND_PREVIOUS_ARTWORK)
            GroupedWallpaperNotification.ACTION_PREVIOUS_GROUP -> command(context, COMMAND_PREVIOUS_GROUP)
            GroupedWallpaperNotification.ACTION_NEXT_GROUP -> command(context, COMMAND_NEXT_GROUP)
            GroupedWallpaperNotification.ACTION_TOGGLE_PAUSE -> togglePause(context)
            GroupedWallpaperNotification.ACTION_SWITCH_GROUP -> GroupedWallpaperAppBridge.requestGroupPage()
        }
    }

    /**
     * Promotes the prefetched slot without waiting for a bake.
     *
     * The promotion already wrote `runtime.json`, so a running app only has to
     * refill; without one the background worker does it. When the renderer
     * cannot move (frozen, or the slot is not uploaded yet), the engine's own
     * command takes over and the action is never silently lost.
     */
    private fun nextArtwork(context: Context) {
        if (GroupedWallpaperRenderBus.advance()) {
            if (!GroupedWallpaperAppBridge.requestSync()) {
                LiveWallpaperRefillScheduler.enqueueTapRefill(context, LiveWallpaperTarget.GROUPED)
            }
            return
        }
        command(context, COMMAND_NEXT_ARTWORK)
    }

    private fun togglePause(context: Context) {
        val paused = GroupedWallpaperStateFile.read(context)?.paused == true
        command(context, if (paused) COMMAND_RESUME else COMMAND_PAUSE)
    }

    private fun command(context: Context, command: String) {
        if (GroupedWallpaperAppBridge.requestCommand(command)) return
        Log.d(TAG, "notification command $command: no listening app, using the background refill")
        LiveWallpaperRefillScheduler.enqueueCommand(context, LiveWallpaperTarget.GROUPED, command)
    }
}
