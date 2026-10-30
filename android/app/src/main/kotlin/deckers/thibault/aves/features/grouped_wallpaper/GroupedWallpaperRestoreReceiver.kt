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

/**
 * Restores the grouped wallpaper when the app's package is replaced.
 *
 * This is the moment an OEM may reset the wallpaper to its default, and the app
 * is not running to notice: see [GroupedWallpaperRestore] for why the restore is
 * silent and when it is allowed. A force-stopped package receives no broadcast,
 * which is why the app also checks on start.
 */
class GroupedWallpaperRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        // The wallpaper manager is a binder call, so it never belongs on the
        // receiver's main thread; `goAsync` keeps the process alive until it ends.
        val pending = goAsync()
        val appContext = context.applicationContext
        Thread {
            try {
                GroupedWallpaperRestore.restoreAfterReplace(appContext)
            } finally {
                pending.finish()
            }
        }.start()
    }
}
