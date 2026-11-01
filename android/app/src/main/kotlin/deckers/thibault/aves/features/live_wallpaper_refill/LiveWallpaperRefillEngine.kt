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
import android.os.Handler
import android.os.Looper
import android.util.Log
import app.loup.streams_channel.StreamsChannel
import deckers.thibault.aves.channel.calls.DeviceHandler
import deckers.thibault.aves.channel.calls.GeocodingHandler
import deckers.thibault.aves.channel.calls.MediaFetchObjectHandler
import deckers.thibault.aves.channel.calls.MediaStoreHandler
import deckers.thibault.aves.channel.calls.MetadataFetchHandler
import deckers.thibault.aves.channel.calls.StorageHandler
import deckers.thibault.aves.channel.streams.darttoplatform.ImageByteStreamHandler
import deckers.thibault.aves.channel.streams.darttoplatform.MediaStoreStreamHandler
import deckers.thibault.aves.features.grouped_wallpaper.GroupedWallpaperHandler
import deckers.thibault.aves.features.muzei_wallpaper.LiveWallpaperHandler
import deckers.thibault.aves.utils.FlutterUtils
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Warm Flutter engine that serves headless wallpaper refills for both wallpapers.
 *
 * Booting an engine and initializing the Dart services costs several seconds,
 * while the bake itself takes about two. Creating a fresh engine for every tap
 * made a double-tap burst take over five seconds per artwork, so the engine is
 * reused across a burst and released after a short idle window. The Dart side
 * keeps its controllers for the same reason.
 *
 * One engine serves both targets: the run carries its target, and the platform
 * channels of both features are registered so whichever wallpaper asks gets its
 * state root, surface size and reload.
 *
 * The worker still owns the process decision (WorkManager); this object only
 * amortizes the engine. A lock (`WallpaperStateStore.runExclusive`) keeps the
 * app UI isolate and this one from baking into the same slot.
 */
object LiveWallpaperRefillEngine {
    private const val TAG = "AvesLiveWallpaper"

    /** Covers a double-tap burst; keeps a second isolate alive for a while. */
    private const val IDLE_TIMEOUT_MS = 60_000L

    /**
     * How long the engine stays warm while the wallpaper service is running.
     *
     * A tap on the wallpaper is served by this engine whenever the app is not in
     * the foreground, and the service outlives the app, so the 60 s burst window
     * only guaranteed a cold start for the next tap. Bounded so an idle phone
     * still drops the isolate.
     */
    private const val KEEP_WARM_TIMEOUT_MS = 5 * 60_000L

    /** One-line switch: turn the keep-warm window off if it ever misbehaves. */
    private const val KEEP_WARM_ENABLED = true

    private const val INIT_TIMEOUT_MS = 30_000L

    /** A slow device bakes a couple of effects; well beyond that is a bug. */
    private const val REFILL_TIMEOUT_MS = 120_000L

    private val mainHandler = Handler(Looper.getMainLooper())

    /** Serializes `refill` calls: one Dart isolate cannot run two bakes at once. */
    private val mutex = Mutex()

    @Volatile
    private var inUse = false

    private var engine: FlutterEngine? = null
    private var initialized = CompletableDeferred<Unit>()

    /** Whether a wallpaper service asked this engine to stay warm. */
    @Volatile
    private var warm = false

    private val idleStop: Runnable = Runnable {
        if (inUse) {
            mainHandler.postDelayed(idleStop, idleTimeoutMs())
        } else {
            release()
        }
    }

    private fun idleTimeoutMs(): Long = if (warm) KEEP_WARM_TIMEOUT_MS else IDLE_TIMEOUT_MS

    /**
     * Keeps the engine alive while a live wallpaper is drawing.
     *
     * The service stays in the process as long as the wallpaper is set, so tying
     * the warm window to it removes the cold start of every tap made while the
     * app is closed, without leaving an isolate alive on an idle phone.
     */
    fun holdWarm(hold: Boolean) {
        warm = hold && KEEP_WARM_ENABLED
        mainHandler.removeCallbacks(idleStop)
        if (!inUse) mainHandler.postDelayed(idleStop, idleTimeoutMs())
        Log.d(TAG, "refill.engine warm=$warm")
    }

    /** Drops the warm engine at once, e.g. when the screen goes off. */
    fun releaseIfIdle() {
        if (inUse) return
        mainHandler.removeCallbacks(idleStop)
        release()
    }

    /** Runs one refill, reusing the engine of the previous run when possible. */
    suspend fun refill(context: Context, target: LiveWallpaperTarget, advance: Boolean, command: String? = null): Boolean = mutex.withLock {
        inUse = true
        mainHandler.removeCallbacks(idleStop)
        try {
            ensureEngine(context)
            val current = engine ?: throw IllegalStateException("the refill engine is not initialized")
            withTimeout(REFILL_TIMEOUT_MS) { invokeRefill(current, target, advance, command) }
        } finally {
            inUse = false
            mainHandler.postDelayed(idleStop, idleTimeoutMs())
        }
    }

    private suspend fun ensureEngine(context: Context) {
        if (engine != null) return
        initialized = CompletableDeferred()
        withTimeout(INIT_TIMEOUT_MS) {
            FlutterUtils.initFlutterEngine(
                context,
                LiveWallpaperRefillScheduler.SHARED_PREFERENCES_KEY,
                LiveWallpaperRefillScheduler.PREF_CALLBACK_HANDLE_KEY,
            ) { created ->
                engine = created
                // Runs on the UI thread before the Dart entrypoint can execute,
                // so the entrypoint's first channel call is always served.
                registerChannels(context, created)
            }
            initialized.await()
        }
    }

    private fun registerChannels(context: Context, engine: FlutterEngine) {
        val messenger = engine.dartExecutor
        // Same platform surface the analysis worker exposes: source queries and
        // EXIF-aware decoding run in the headless isolate.
        MethodChannel(messenger, DeviceHandler.CHANNEL).setMethodCallHandler(DeviceHandler(context))
        MethodChannel(messenger, GeocodingHandler.CHANNEL).setMethodCallHandler(GeocodingHandler(context))
        MethodChannel(messenger, MediaFetchObjectHandler.CHANNEL).setMethodCallHandler(MediaFetchObjectHandler(context))
        MethodChannel(messenger, MediaStoreHandler.CHANNEL).setMethodCallHandler(MediaStoreHandler(context))
        MethodChannel(messenger, MetadataFetchHandler.CHANNEL).setMethodCallHandler(MetadataFetchHandler(context))
        MethodChannel(messenger, StorageHandler.CHANNEL).setMethodCallHandler(StorageHandler(context))
        StreamsChannel(messenger, ImageByteStreamHandler.CHANNEL).setStreamHandlerFactory { args -> ImageByteStreamHandler(context, args) }
        StreamsChannel(messenger, MediaStoreStreamHandler.CHANNEL).setStreamHandlerFactory { args -> MediaStoreStreamHandler(context, args) }

        // Both wallpaper lifecycle channels: a refill needs the surface size and
        // reports the state change so the running renderer reloads.
        MethodChannel(messenger, LiveWallpaperHandler.CHANNEL).setMethodCallHandler(LiveWallpaperHandler(context))
        MethodChannel(messenger, GroupedWallpaperHandler.CHANNEL).setMethodCallHandler(GroupedWallpaperHandler(context, servesSyncRequests = false))

        MethodChannel(messenger, LiveWallpaperRefillScheduler.CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialized" -> {
                    initialized.complete(Unit)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private suspend fun invokeRefill(engine: FlutterEngine, target: LiveWallpaperTarget, advance: Boolean, command: String?): Boolean =
        suspendCancellableCoroutine { cont ->
            // Platform messages may only be sent from the main thread.
            val channel = MethodChannel(engine.dartExecutor, LiveWallpaperRefillScheduler.CHANNEL)
            mainHandler.post {
                try {
                    channel.invokeMethod(
                        "refill",
                        mapOf(
                            LiveWallpaperRefillWorker.KEY_TARGET to target.id,
                            LiveWallpaperRefillWorker.KEY_ADVANCE to advance,
                            LiveWallpaperRefillWorker.KEY_COMMAND to command,
                        ),
                        object : MethodChannel.Result {
                            override fun success(result: Any?) {
                                if (cont.isActive) cont.resume(result == true)
                            }

                            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                                if (cont.isActive) cont.resumeWithException(IllegalStateException("$errorCode: $errorMessage"))
                            }

                            override fun notImplemented() {
                                if (cont.isActive) cont.resumeWithException(IllegalStateException("refill is not implemented"))
                            }
                        },
                    )
                } catch (t: Throwable) {
                    if (cont.isActive) cont.resumeWithException(t)
                }
            }
        }

    private fun release() {
        val current = engine ?: return
        engine = null
        initialized = CompletableDeferred()
        mainHandler.post {
            try {
                current.destroy()
            } catch (t: Throwable) {
                Log.w(TAG, "failed to destroy the refill engine", t)
            }
        }
        Log.d(TAG, "refill.engine released")
    }
}
