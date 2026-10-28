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
import deckers.thibault.aves.channel.calls.Coresult.Companion.safe
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler

/**
 * Foreground side of the shared background pipeline.
 *
 * The app is the only place that can hand the worker a `vm:entry-point` callback
 * handle, and one handle serves both wallpapers, so registration lives here
 * instead of in either feature. The worker itself talks to the same channel from
 * its own engine; the method sets never overlap.
 */
class LiveWallpaperRefillHandler(private val context: Context) : MethodCallHandler {
    companion object {
        const val CHANNEL = LiveWallpaperRefillScheduler.CHANNEL
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "registerCallback" -> safe(call, result, ::registerCallback)
            else -> result.notImplemented()
        }
    }

    private fun registerCallback(call: MethodCall, result: MethodChannel.Result) {
        val handle = call.argument<Number>("callbackHandle")?.toLong() ?: 0L
        LiveWallpaperRefillScheduler.registerCallback(context, handle)
        result.success(null)
    }
}
