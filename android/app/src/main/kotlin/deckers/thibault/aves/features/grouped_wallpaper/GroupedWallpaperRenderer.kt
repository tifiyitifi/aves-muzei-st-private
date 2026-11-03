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

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.GLUtils
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.min

/**
 * Draws the baked queue and promotes slots on a wallpaper tap.
 *
 * The engine bakes `previous → current → next`, so a step in either direction
 * switches to a texture that is already uploaded: the renderer records what it
 * did in `runtime.json` and asks the app (or the background worker) to refill the
 * frame it left behind. Neither a double tap nor the bar's "previous" waits for
 * Flutter, and stepping back and forth through the usage history is instant.
 *
 * File reads and PNG decodes happen on a loader thread; the GL thread only
 * uploads the decoded bitmaps, so a slow disk never stalls a frame.
 */
class GroupedWallpaperRenderer(
    private val context: Context,
    private val requestRender: () -> Unit,
    private val onAdvanced: () -> Unit,
    private val onFrameLoaded: () -> Unit,
    /**
     * Whether this renderer answers the app's live-wallpaper commands.
     *
     * The picker preview builds the same renderer over the same state, so letting
     * it attach would make the bar promote a surface nobody sees and hide the
     * real engine's reload. Only the engine drawing the system wallpaper attaches.
     */
    private val attachToBus: Boolean = true,
) : GLSurfaceView.Renderer {
    private companion object {
        const val TAG = "AvesGroupedWallpaper"

        /** Conservative `GL_MAX_TEXTURE_SIZE` floor, matching the Dart baker. */
        const val MAX_TEXTURE_SIZE = 4096

        const val PLACEHOLDER_SIZE = 256

        /** Neutral grey behind the placeholder glyph. */
        const val PLACEHOLDER_BACKGROUND = 0xFF303338.toInt()

        const val PLACEHOLDER_FOREGROUND = 0xFF8A8F98.toInt()

        const val VERTEX_SHADER = """
            attribute vec4 aPosition;
            attribute vec2 aTexCoord;
            varying vec2 vTexCoord;
            void main() {
                gl_Position = aPosition;
                vTexCoord = aTexCoord;
            }
        """

        const val FRAGMENT_SHADER = """
            precision mediump float;
            uniform sampler2D uTexture;
            uniform float uAlpha;
            varying vec2 vTexCoord;
            void main() {
                gl_FragColor = vec4(texture2D(uTexture, vTexCoord).rgb, uAlpha);
            }
        """

        /** Temporary kill switch: false ships the plain, instant switch. */
        const val CROSSFADE_ENABLED = true

        /**
         * How often a reload may chase a slot whose file exists but whose texture
         * is still missing. A corrupt bake must not reload in a loop forever.
         */
        const val MAX_RELOAD_RETRIES = 3
    }

    /** What the loader thread decoded for one reload. */
    private class LoadedFrame(
        val state: GroupedWallpaperFileState,
        val bitmaps: Map<Int, Bitmap>,
        /** The decoy frame decoded for the lock surface, when it changed. */
        val lockBitmap: Bitmap?,
        val lockEntryId: Int,
        val lockPhoto: String,
        /** The surface epoch the `uploaded` snapshot belongs to. */
        val epoch: Int,
        /** The effect image picked when the bitmaps were decoded. */
        val lockScreen: Boolean,
    )

    private class UploadedSlot(val entryId: Int, val photo: String, val texture: Int, val aspect: Float)

    /**
     * The texture's real width/height ratio.
     *
     * A frame is baked for the surface, so on a portrait phone it is portrait
     * too. Treating anything narrower than the view as square would sample a
     * horizontal window out of a frame that already matches the view, cropping the
     * sides of every non-panning wallpaper.
     */
    private fun aspectOf(bitmap: Bitmap): Float = bitmap.width.toFloat() / bitmap.height.coerceAtLeast(1)

    /** A frame fading out under the one that replaced it. */
    private class Fading(val id: Int, val slot: UploadedSlot, val startedAt: Long, val durationMs: Int)

    /** Disk reads and PNG decodes never run on the GL thread. */
    private val loader = Executors.newSingleThreadExecutor()

    private val reloadInFlight = AtomicBoolean(false)
    private val reloadAgain = AtomicBoolean(false)

    @Volatile
    private var destroyed = false

    /**
     * Bumped whenever frames the renderer had are gone from the current context.
     *
     * An in-flight reload captured `uploaded` from before that loss; consuming it
     * as-is would make it skip slots the context never uploaded. Only a real loss
     * bumps it: a surface that comes back with its textures does not.
     */
    @Volatile
    private var surfaceEpoch = 0

    /**
     * Makes the [surfaceEpoch] and [uploaded] snapshot atomic.
     *
     * [loadFrame] reads both on the loader thread while [onSurfaceCreated] bumps
     * the epoch and empties `uploaded` on the GL thread: reading them one at a
     * time could pair a new epoch with the old snapshot.
     */
    private val surfaceLock = Any()

    /** Decoded by [loader], uploaded by the GL thread. */
    @Volatile
    private var pending: LoadedFrame? = null

    /**
     * What the GL thread already uploaded, as slot id to entry id and file.
     *
     * A history step changes `current` alone, so the loader must not decode the
     * frames of the two neighbours again: that decode is the whole difference
     * between an instant step and a visible one.
     *
     * Derived from [textures] by [publishFrames] and never assigned anywhere
     * else: the two maps drifting apart is what makes a reload skip a slot that
     * has no texture and leave a hole.
     */
    @Volatile
    private var uploaded: Map<Int, Pair<Int, String>> = emptyMap()

    /** The last state read from disk, used for gestures and the runtime. */
    @Volatile
    private var state: GroupedWallpaperFileState? = null

    /**
     * The one decoy texture the split lock surface draws.
     *
     * The lock screen has no queue, so it does not enter [textures] (which is
     * keyed by promotable slot id) and no retention or promotion path touches it.
     * It is kept while the group splits its surfaces and dropped when they join.
     */
    @Volatile
    private var lockUploaded: UploadedSlot? = null

    /** What [lockUploaded] was decoded from, so a reload can skip re-decoding. */
    @Volatile
    private var lockUploadedEntryId: Int = -1
    @Volatile
    private var lockUploadedPhoto: String = ""

    /** The slot on screen; a local promotion moves it before Dart writes. */
    @Volatile
    private var displayed: Int = -1

    /**
     * The slot the latest state, or a local promotion, wants on screen.
     *
     * [displayed] may differ while that slot's texture is missing and the
     * wallpaper falls back to a neighbour; keeping the intent separately is what
     * makes the fallback temporary instead of sticky.
     */
    @Volatile
    private var desired: Int = -1

    /** [displayed] is a stand-in because [desired] was not drawable yet. */
    @Volatile
    private var fallback = false

    /**
     * The `(generation, desired)` a reload is chasing, and how many it tried.
     *
     * Guarded by [advanceLock]: a promotion resets it while a reload writes it.
     */
    private var retryKey: Pair<Int, Int>? = null
    private var retryCount = 0

    /** Slot ids whose texture is uploaded, so a promotion never targets a hole. */
    @Volatile
    private var readySlots: Set<Int> = emptySet()

    /**
     * Guards a promotion: a tap arrives on the main thread while a reload is
     * consumed on the GL thread, and both may promote.
     */
    private val advanceLock = Any()

    /** Taps that arrived before a slot was uploaded; replayed as slots land. */
    private val advanceRequests = GroupedAdvanceRequestQueue()

    @Volatile
    private var offsetX = 0.5f

    /** The lock screen is drawn; the lock effect image applies. */
    @Volatile
    private var lockScreenVisible = false

    private var program = 0
    private var aPosition = -1
    private var aTexCoord = -1
    private var uTexture = -1
    private var uAlpha = -1

    private var viewWidth = 1
    private var viewHeight = 1

    private val textures = mutableMapOf<Int, UploadedSlot>()

    /**
     * The frame fading out; its texture stays uploaded until the fade ends.
     *
     * Only the GL thread touches it, since only it owns the texture ids.
     */
    private var fading: Fading? = null

    /**
     * The slot a promotion left behind, to fade from on the next GL frame.
     *
     * A promotion runs on the main thread, which must not touch the textures, so
     * it only records the intent and the GL thread starts the fade.
     */
    @Volatile
    private var pendingFadeFrom: Int = -1

    private var placeholderTexture = 0

    private val texCoords = FloatArray(8)

    private val fullVertexBuffer: FloatBuffer = ByteBuffer
        .allocateDirect(4 * 2 * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()
        .apply {
            put(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f))
            position(0)
        }

    private val texCoordBuffer: FloatBuffer = ByteBuffer
        .allocateDirect(4 * 2 * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()

    private val placeholderVertexBuffer: FloatBuffer = ByteBuffer
        .allocateDirect(4 * 2 * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()

    private val placeholderTexCoords: FloatBuffer = ByteBuffer
        .allocateDirect(4 * 2 * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()
        .apply {
            // Bitmap row 0 is the top row, so the top of the quad samples v=1.
            put(floatArrayOf(0f, 1f, 1f, 1f, 0f, 0f, 1f, 0f))
            position(0)
        }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        destroyed = false
        // A surface (re)creation is not necessarily a new EGL context. This
        // GLWallpaperService keeps one context for the life of the engine: its
        // `EglHelper.start()` reuses the context it already has, and `finish()`
        // only runs when the GL thread exits. So after a hide and show, the
        // texture ids still name live objects, and clearing them is what used to
        // force a re-decode and show the grey placeholder on every return.
        //
        // Ask the driver which frames survived instead of assuming they all
        // died. The epoch is bumped in the same critical section that publishes
        // the surviving snapshot, and [loadFrame] reads both under the same lock,
        // so a reload that started earlier is either still valid or discarded as
        // a whole: the order alone is not enough, a loader could see the new
        // epoch and still read the pre-clear `uploaded`.
        val lost = dropLostFrames()
        publishFrames(bumpEpoch = lost.isNotEmpty())
        Log.d(TAG, "surface.created epoch=$surfaceEpoch kept=${textures.keys.sorted()} lost=$lost")
        try {
            // Only a lost program is rebuilt: recompiling on every surface would
            // throw away the same shaders the context still owns.
            if (!GLES20.glIsProgram(program)) {
                program = createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
                aPosition = GLES20.glGetAttribLocation(program, "aPosition")
                aTexCoord = GLES20.glGetAttribLocation(program, "aTexCoord")
                uTexture = GLES20.glGetUniformLocation(program, "uTexture")
                uAlpha = GLES20.glGetUniformLocation(program, "uAlpha")
            }
            GLES20.glDisable(GLES20.GL_DEPTH_TEST)
            GLES20.glClearColor(
                ((PLACEHOLDER_BACKGROUND shr 16) and 0xFF) / 255f,
                ((PLACEHOLDER_BACKGROUND shr 8) and 0xFF) / 255f,
                (PLACEHOLDER_BACKGROUND and 0xFF) / 255f,
                1f,
            )
            if (!GLES20.glIsTexture(placeholderTexture)) {
                placeholderTexture = createTexture(createPlaceholderBitmap())
            }
            if (attachToBus) GroupedWallpaperRenderBus.attach(this)
            requestReload()
        } catch (t: Throwable) {
            // A driver that refuses the program still gets the grey background
            // instead of a black or frozen surface.
            Log.e(TAG, "renderer init failed, falling back to the background color", t)
            program = 0
            placeholderTexture = 0
        }
    }

    /**
     * Drops the frames the current context does not know, and returns their slots.
     *
     * A lost frame is not deleted: its id belongs to another context, so
     * `glDeleteTextures` would at best do nothing and at worst free a name the
     * new context just handed out.
     */
    private fun dropLostFrames(): List<Int> {
        val lost = textures.filterValues { !GLES20.glIsTexture(it.texture) }.keys.toList()
        for (id in lost) textures.remove(id)
        // The decoy belongs to the same context: a lost texture must be decoded
        // again, or the lock screen would fall back to the home frame.
        val decoy = lockUploaded
        if (decoy != null && !GLES20.glIsTexture(decoy.texture)) {
            lockUploaded = null
            lockUploadedEntryId = -1
            lockUploadedPhoto = ""
        }
        // A fading frame belongs to the same context; one that did not survive
        // must not be drawn from a dead id.
        val fade = fading
        if (fade != null && !GLES20.glIsTexture(fade.slot.texture)) fading = null
        return lost
    }

    /**
     * Publishes [textures] as the source of truth the loader reads.
     *
     * `uploaded` and `readySlots` are derived here and nowhere else, so they can
     * never describe a frame that is not on the GPU. A new epoch is only handed
     * out together with the snapshot it belongs to, which is what makes an
     * in-flight reload's skips safe to trust or safe to discard.
     */
    private fun publishFrames(bumpEpoch: Boolean = false) {
        synchronized(surfaceLock) {
            if (bumpEpoch) surfaceEpoch++
            uploaded = textures.mapValues { (_, slot) -> slot.entryId to slot.photo }
        }
        readySlots = textures.keys.toSet()
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        Log.d(TAG, "surface.changed w=$width h=$height")
        viewWidth = width.coerceAtLeast(1)
        viewHeight = height.coerceAtLeast(1)
        GLES20.glViewport(0, 0, viewWidth, viewHeight)
        updatePlaceholderQuad()
        requestRender()
    }

    override fun onDrawFrame(gl: GL10?) {
        consumePending()
        startPendingFade()

        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        if (program == 0) return

        // The split lock surface draws its own single frame, not the home queue.
        // There is nothing to fade between: the two pictures are independent.
        // While the group is split, a missing decoy must fall back to the
        // placeholder, never to the home frame: doing so would reveal exactly
        // what the lock screen is meant to mask.
        val currentState = state
        val splitLock = lockScreenVisible && currentState != null && (currentState.lock != null || currentState.lockRangeId.isNotEmpty())
        if (splitLock) {
            val decoy = lockUploaded
            if (decoy != null) {
                drawSlot(decoy, alpha = 1f)
            } else if (placeholderTexture != 0) {
                drawQuad(placeholderVertexBuffer, placeholderTexCoords, placeholderTexture, alpha = 1f)
            }
            return
        }

        val current = textures[displayed]
        val fade = fading
        if (fade != null) {
            if (current == null) {
                // Nothing replaced the outgoing frame yet: keep it on screen
                // instead of dropping to the placeholder.
                drawSlot(fade.slot, alpha = 1f)
                return
            }
            val elapsed = SystemClock.elapsedRealtime() - fade.startedAt
            val t = (elapsed.toFloat() / fade.durationMs).coerceIn(0f, 1f)
            drawSlot(fade.slot, alpha = 1f)
            drawSlot(current, alpha = t)
            if (t >= 1f) releaseFading() else requestRender()
            return
        }
        if (current != null) {
            drawSlot(current, alpha = 1f)
        } else if (placeholderTexture != 0) {
            drawQuad(placeholderVertexBuffer, placeholderTexCoords, placeholderTexture, alpha = 1f)
        }
    }

    /**
     * Draws one frame with the launcher's pan window.
     *
     * The lock screen does not pan: it centers the window instead of leaving it
     * on whichever home page the launcher stopped at.
     */
    private fun drawSlot(slot: UploadedSlot, alpha: Float) {
        val offset = if (lockScreenVisible) 0.5f else offsetX
        GroupedWallpaperViewport.texCoords(texCoords, slot.aspect, viewWidth.toFloat() / viewHeight.toFloat(), offset)
        texCoordBuffer.put(texCoords).position(0)
        drawQuad(fullVertexBuffer, texCoordBuffer, slot.texture, alpha)
    }

    /** Starts the fade a promotion recorded, on the thread that owns the textures. */
    private fun startPendingFade() {
        val from = pendingFadeFrom
        if (from < 0) return
        pendingFadeFrom = -1
        beginFade(from)
    }

    /**
     * Fades from [fromId] to the slot now on screen.
     *
     * The outgoing frame keeps its texture until the new one is fully opaque,
     * which is Muzei's rule for its current picture set, so a mid-fade reload can
     * never blank the wallpaper.
     */
    private fun beginFade(fromId: Int) {
        releaseFading()
        if (!CROSSFADE_ENABLED || !animatorsEnabled()) return
        // The app owns the duration; a missing or zero value switches instantly.
        val duration = state?.transitionMs ?: GroupedWallpaperFileState.DEFAULT_TRANSITION_MS
        if (duration <= 0) return
        if (fromId < 0 || fromId == displayed) return
        val slot = textures.remove(fromId) ?: return
        fading = Fading(fromId, slot, SystemClock.elapsedRealtime(), duration)
        // The released frame leaves `uploaded` with its texture, or the next
        // reload would skip re-uploading it and draw nothing.
        publishFrames()
    }

    private fun releaseFading() {
        val fade = fading ?: return
        fading = null
        deleteTexture(fade.slot.texture)
    }

    /** Whether the system asks for animations, e.g. for motion-sickness users. */
    private fun animatorsEnabled(): Boolean = try {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) != 0f
    } catch (t: Throwable) {
        // A vendor build without the setting still gets the fade.
        true
    }

    /** Re-reads `state.json` on the loader thread. */
    fun requestReload() {
        if (destroyed) return
        if (!reloadInFlight.compareAndSet(false, true)) {
            reloadAgain.set(true)
            return
        }
        try {
            loader.execute {
                val loaded = loadFrame()
                if (destroyed) {
                    loaded?.bitmaps?.values?.forEach { it.recycle() }
                    reloadInFlight.set(false)
                    return@execute
                }
                pending = loaded
                requestRender()
                reloadInFlight.set(false)
                if (reloadAgain.compareAndSet(true, false)) requestReload()
            }
        } catch (e: RejectedExecutionException) {
            // The engine was destroyed between the check and the submit.
            reloadInFlight.set(false)
            Log.d(TAG, "reload ignored after renderer shutdown")
        }
    }

    /** Launcher offset in `0..1`; single-page launchers report `0.5`. */
    fun setOffsetX(value: Float) {
        val next = value.coerceIn(0f, 1f)
        if (offsetX == next) return
        offsetX = next
        requestRender()
    }

    /**
     * Switches to the home or lock effect image.
     *
     * A reload picks the new file, so the effect never needs a second texture per
     * slot: only the surface being drawn is uploaded.
     */
    fun setLockScreenVisible(visible: Boolean) {
        if (lockScreenVisible == visible) return
        lockScreenVisible = visible
        Log.d(TAG, "lockScreen.visible=$visible")
        // The decoy texture is uploaded lazily, but a switch to it must not wait
        // for the reload when it is already there.
        requestRender()
        requestReload()
    }

    /** Whether the renderer is drawing the lock surface. */
    fun isLockScreenVisible(): Boolean = lockScreenVisible

    /** The action bound to a gesture, from the latest `state.json`. */
    fun actionFor(threeFinger: Boolean): String {
        val current = state ?: return if (threeFinger) GroupedWallpaperFileState.ACTION_VIEW_ARTWORK else GroupedWallpaperFileState.ACTION_NEXT_ARTWORK
        return if (threeFinger) current.threeFinger else current.doubleTap
    }

    /**
     * Moves to the prefetched slot, as a wallpaper tap does.
     *
     * Returns false when there is nothing to promote: the group is turned off,
     * the queue is exhausted, the group has a single photo, or the texture of
     * the next slot has not been uploaded yet. The caller then buffers the tap
     * instead of losing it.
     */
    fun promote(): Boolean = synchronized(advanceLock) {
        val current = state ?: return@synchronized false
        if (!current.canPromote) return@synchronized false
        promoteLocked(current.next, back = false)
    }

    /** Steps to the older usage record, as the bar's "previous" asks. */
    fun promotePrevious(): Boolean = synchronized(advanceLock) {
        val current = state ?: return@synchronized false
        if (!current.canRegress) return@synchronized false
        promoteLocked(current.previous, back = true)
    }

    /**
     * Whether the wallpaper may advance at all.
     *
     * A turned-off state has nothing to promote, and a tap must then do nothing
     * instead of buffering a request that fires after the feature is turned back
     * on. A locked range still moves: the lock protects editing, not the photos.
     */
    fun canAdvance(): Boolean = state?.canPromote == true

    /**
     * Whether a tap may be buffered while the prefetched slot is being baked.
     *
     * [canAdvance] is false both for a wallpaper that must not move at all and
     * for one that is merely waiting for the next slot to upload. Only the
     * latter should queue: a request buffered across an off switch would fire
     * long after the user tapped, while a slot that is baking arrives in
     * milliseconds. A locked range still navigates, so it queues like a ready
     * one.
     */
    fun canQueueAdvance(): Boolean {
        val current = state ?: return false
        return current.status == GroupedWallpaperFileState.STATUS_READY || current.status == GroupedWallpaperFileState.STATUS_LOCKED
    }

    /** The slot on screen, for the notification's title. */
    fun displayedSlotId(): Int = displayed

    /**
     * Draws [target] and records the step.
     *
     * [back] tells which side is left empty: the frame on screen becomes the
     * opposite neighbour, and Dart refills the side the step walked away from.
     */
    private fun promoteLocked(target: Int, back: Boolean): Boolean {
        val current = state ?: return false
        if (target < 0) return false
        if (!readySlots.contains(target)) {
            Log.d(TAG, "promote skipped: slot $target is not uploaded yet")
            return false
        }
        val previous = if (back) -1 else current.current
        val next = if (back) current.current else -1
        // The GL thread starts the fade; the main thread must not touch textures.
        pendingFadeFrom = displayed
        displayed = target
        // The tap is the newest intent: a reload that has not adopted the state
        // the tap just wrote must not pull the wallpaper back to `current`.
        desired = target
        fallback = false
        retryKey = null
        retryCount = 0
        state = current.copy(current = target, previous = previous, next = next)
        requestRender()
        // Written synchronously: the app reads the runtime as soon as it hears
        // about the tap, and an asynchronous write would let it bake from the
        // slot the tap already left.
        GroupedWallpaperStateFile.writeRuntime(context, current.generation, target, next, refillRequested = true)
        Log.d(TAG, "promote generation=${current.generation} back=$back current=$target next=$next")
        return true
    }

    /** Buffers a tap whose slot is not uploaded yet, so it is not lost. */
    fun enqueueAdvance() {
        val pending = synchronized(advanceLock) {
            advanceRequests.request(SystemClock.elapsedRealtime())
            advanceRequests.size
        }
        Log.d(TAG, "advance queued pending=$pending")
    }

    /**
     * Replays one buffered tap once a reload has uploaded a promotable slot.
     *
     * A tap can outrun the bake; the reload that follows a refill is the moment
     * it can be served. Further buffered taps wait for their own refill.
     */
    private fun drainPendingAdvance() {
        if (destroyed) return
        val promoted = synchronized(advanceLock) {
            val current = state
            if (advanceRequests.isEmpty || current == null) return@synchronized false
            if (!current.canPromote || !readySlots.contains(current.next)) return@synchronized false
            if (!advanceRequests.consume(SystemClock.elapsedRealtime())) return@synchronized false
            promoteLocked(current.next, back = false)
        }
        if (!promoted) return
        Log.d(TAG, "advance.drain")
        onAdvanced()
    }

    fun destroy() {
        destroyed = true
        GroupedWallpaperRenderBus.detach(this)
        synchronized(advanceLock) { advanceRequests.clear() }
        loader.shutdownNow()
    }

    private fun loadFrame(): LoadedFrame? {
        // Both must belong to the same surface: a rebuild between them would let
        // this reload skip a slot the new context has not uploaded.
        val epoch: Int
        val onScreen: Map<Int, Pair<Int, String>>
        synchronized(surfaceLock) {
            epoch = surfaceEpoch
            onScreen = uploaded
        }
        val lockScreen = lockScreenVisible
        val state = GroupedWallpaperStateFile.read(context) ?: return null
        val bitmaps = mutableMapOf<Int, Bitmap>()
        val skipped = mutableListOf<Int>()
        val failed = mutableListOf<Int>()
        fun loadSlot(slot: GroupedWallpaperSlotFile) {
            val photo = slot.photoFor(lockScreen)
            // The texture is already on the GPU and draws the same file: decoding
            // it again would only delay the frame the user asked for.
            val existing = onScreen[slot.id]
            if (existing != null && existing.first == slot.entryId && existing.second == photo) {
                skipped.add(slot.id)
                return
            }
            val file = GroupedWallpaperStateFile.photoFile(context, photo)
            if (file == null) {
                failed.add(slot.id)
                return
            }
            val bitmap = decode(file)
            if (bitmap == null) failed.add(slot.id) else bitmaps[slot.id] = bitmap
        }
        val limitNeighbours = state.frameRetention.limitsNeighbours(state.scrollEffect)
        // The decoy is only decoded while the lock screen is drawn: it is not
        // part of the home queue, and decoding it on every home reload would cost
        // a bitmap for a frame nobody sees.
        val lockFrame = state.lock
        var lockBitmap: Bitmap? = null
        if (lockScreen && lockFrame != null && (lockUploadedEntryId != lockFrame.entryId || lockUploadedPhoto != lockFrame.photo)) {
            val file = GroupedWallpaperStateFile.photoFile(context, lockFrame.photo)
            if (file == null) {
                Log.w(TAG, "lock.decode.missing entry=${lockFrame.entryId}")
            } else {
                lockBitmap = decode(file)
            }
        }
        // The frame the wallpaper is about to show is decoded first: a limited
        // reload must not queue it behind neighbours it is going to evict. A
        // buffered tap is the other frame worth decoding, or the tap could never
        // be served under this policy.
        val intent = desired.takeIf { state.slot(it) != null } ?: state.current
        val advanceTarget = synchronized(advanceLock) { if (advanceRequests.isEmpty) -1 else state.next }
        val wanted = listOf(intent) + listOfNotNull(advanceTarget.takeIf { it >= 0 && it != intent })
        val order = GroupedFramePolicy.decodeOrder(state.slots.map { it.id }, wanted, limitNeighbours)
        for (id in order) {
            state.slot(id)?.let(::loadSlot)
        }
        if (limitNeighbours && bitmaps.isEmpty() && skipped.isEmpty()) {
            // The one frame worth keeping cannot be decoded: the neighbours are
            // the only alternative to the placeholder, so decode them after all.
            Log.d(TAG, "reload.rescue intent=$intent")
            for (id in state.slots.map { it.id }) {
                if (id != intent) state.slot(id)?.let(::loadSlot)
            }
        }
        // A slot that silently vanishes is what makes the wallpaper look like it
        // went back a photo; the reload log makes the difference between "skipped
        // because it is already on the GPU" and "nothing decoded" readable.
        Log.d(TAG, "reload.loaded epoch=$epoch stateGen=${state.generation} skip=$skipped decode=${bitmaps.keys.sorted()} failed=$failed lock=${lockBitmap != null}")
        return LoadedFrame(state, bitmaps, lockBitmap, lockFrame?.entryId ?: -1, lockFrame?.photo ?: "", epoch, lockScreen)
    }

    private fun decode(file: File): Bitmap? = try {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        var sample = 1
        while (bounds.outWidth / sample > MAX_TEXTURE_SIZE || bounds.outHeight / sample > MAX_TEXTURE_SIZE) {
            sample *= 2
        }
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val bitmap = BitmapFactory.decodeFile(file.absolutePath, options)
        // A missing or corrupt file returns null without throwing, which used to
        // leave no trace at all.
        if (bitmap == null) Log.w(TAG, "decode.null path=${file.name}")
        bitmap
    } catch (t: Throwable) {
        // A corrupt bake shows the placeholder instead of crashing the service.
        Log.w(TAG, "failed to decode ${file.name}", t)
        null
    }

    private fun consumePending() {
        val loaded = pending ?: return
        pending = null
        // A reload can outlive the frames its skips were based on: they were
        // checked against `uploaded` from a context that no longer draws. The
        // decoded bitmaps themselves do not belong to any context, so they are
        // uploaded as usual; the reload requested below fills the slots the
        // stale snapshot made it skip, instead of decoding everything again.
        val staleEpoch = GroupedDisplay.isStaleEpoch(loaded.epoch, surfaceEpoch)
        if (staleEpoch) {
            Log.d(TAG, "reload.stale-epoch loaded=${loaded.epoch} current=$surfaceEpoch")
        }

        val previousGeneration: Int
        val next: GroupedWallpaperFileState
        var stale = false
        // Serialized with a promotion: the two threads must not swap the state
        // and the displayed slot under each other.
        synchronized(advanceLock) {
            previousGeneration = state?.generation ?: Int.MIN_VALUE
            // A reload can race a writer and read a file older than the state
            // already on screen; adopting it would make retention treat the
            // newer slots as garbage.
            stale = GroupedDisplay.isStaleGeneration(loaded.state.generation, previousGeneration)
            if (stale) {
                next = loaded.state
            } else {
                // A newer state can still point at the slot a local promotion
                // just left; keep what is on screen instead of rewinding to it.
                next = keepDisplayedSlot(loaded.state, previousGeneration)
                state = next
            }
        }
        if (stale) {
            // Every genuine write triggers its own reload, so there is nothing to
            // chase; keeping the current frame is better than rewinding.
            loaded.bitmaps.values.forEach { it.recycle() }
            loaded.lockBitmap?.recycle()
            Log.d(TAG, "reload.discard reason=generation loaded=${loaded.state.generation} current=$previousGeneration")
            return
        }

        // The decoy lives outside the home queue: it is one texture, kept while
        // the group splits its surfaces and dropped when they join again. A
        // missing decode keeps the old decoy rather than blanking the lock screen.
        val decoy = next.lock
        if (decoy == null) {
            lockUploaded?.let { deleteTexture(it.texture) }
            lockUploaded = null
            lockUploadedEntryId = -1
            lockUploadedPhoto = ""
        } else {
            val bitmap = loaded.lockBitmap
            if (bitmap != null) {
                try {
                    val aspect = aspectOf(bitmap)
                    val existing = lockUploaded
                    lockUploaded = if (existing == null) {
                        UploadedSlot(loaded.lockEntryId, loaded.lockPhoto, createTexture(bitmap), aspect)
                    } else {
                        upload(existing.texture, bitmap)
                        UploadedSlot(loaded.lockEntryId, loaded.lockPhoto, existing.texture, aspect)
                    }
                    lockUploadedEntryId = loaded.lockEntryId
                    lockUploadedPhoto = loaded.lockPhoto
                } finally {
                    bitmap.recycle()
                }
            }
        }

        for ((id, bitmap) in loaded.bitmaps) {
            val slot = next.slot(id)
            val photo = slot?.photoFor(loaded.lockScreen) ?: ""
            val existing = textures[id]
            // A slot keeps its id while it stays in the queue, so an unchanged
            // file must not be uploaded again.
            if (existing != null && slot != null && existing.entryId == slot.entryId && existing.photo == photo) {
                bitmap.recycle()
                continue
            }
            try {
                val aspect = aspectOf(bitmap)
                if (existing == null) {
                    textures[id] = UploadedSlot(slot?.entryId ?: -1, photo, createTexture(bitmap), aspect)
                } else {
                    upload(existing.texture, bitmap)
                    textures[id] = UploadedSlot(slot?.entryId ?: -1, photo, existing.texture, aspect)
                }
            } finally {
                bitmap.recycle()
            }
        }

        // Keep every frame the new state still draws. `loaded.bitmaps` only holds
        // the frames this reload decoded, and the loader skips the ones already on
        // the GPU, so it cannot tell which frames are alive.
        val uploadedNow = textures.mapValues { (_, slot) -> slot.entryId to slot.photo }
        // The retention switch caps how many frames stay resident. It never
        // overrides the frame about to be shown, and it steps aside while that
        // frame is not drawable: a neighbour is the only alternative to the
        // placeholder then.
        val intent = desired.takeIf { next.slot(it) != null } ?: next.current
        val kept = GroupedFramePolicy.retainedIds(
            slots = next.slots.map { it.id }.toSet(),
            intent = intent,
            limitNeighbours = next.frameRetention.limitsNeighbours(next.scrollEffect),
            drawable = textures.keys,
        )
        val wanted = next.slots.filter { it.id in kept }.associate { it.id to (it.entryId to it.photoFor(loaded.lockScreen)) }
        // A frame on screen, or one still fading out, is never dropped: nothing
        // would replace it. A tap's target survives too, or the reload that just
        // decoded it would evict it before the tap could be served.
        val advanceTarget = synchronized(advanceLock) { if (advanceRequests.isEmpty) -1 else next.next }
        val protected = listOfNotNull(
            displayed.takeIf { it >= 0 },
            pendingFadeFrom.takeIf { it >= 0 },
            fading?.id,
            advanceTarget.takeIf { it >= 0 },
        ).toSet()
        val dropped = GroupedTextureRetention.staleIds(uploadedNow, wanted, protected)
        for (id in dropped) {
            textures.remove(id)?.let { deleteTexture(it.texture) }
        }
        publishFrames()
        if (staleEpoch) {
            // The slots this reload skipped were skipped on the strength of ids
            // that no longer exist: one more pass now skips only what is really
            // uploaded, so the wallpaper does not stay on a neighbour.
            requestReload()
        }

        var retry = false
        var retryDesired = -1
        synchronized(advanceLock) {
            // A tap during the uploads already moved `state` and `displayed` on;
            // deciding from the latest of both keeps the promotion on screen.
            val latest = state ?: next
            val fresh = latest === next && next.generation > previousGeneration
            val decision = GroupedDisplay.decide(
                stateCurrent = latest.current,
                statePrevious = latest.previous,
                stateNext = latest.next,
                displayed = displayed,
                desired = desired,
                fallback = fallback,
                fresh = fresh,
                drawable = textures.keys,
            )
            // A slot change fades, the way a tap does. The GL thread starts it,
            // so the main thread must not touch the textures here.
            if (decision.displayed != displayed && displayed >= 0) pendingFadeFrom = displayed
            if (fallback && !decision.fallback && decision.desired >= 0) {
                Log.d(TAG, "display.restore slot=${decision.desired}")
            }
            displayed = decision.displayed
            desired = decision.desired
            fallback = decision.fallback
            retry = decision.retry
            retryDesired = decision.desired
        }
        Log.d(TAG, "textures.keep=${textures.keys.sorted()} drop=${dropped.sorted()} desired=$desired fallback=$fallback displayed=$displayed")

        scheduleRetry(next, retry, retryDesired, loaded.lockScreen)
        // A buffered tap may be servable now that the new slots are uploaded.
        drainPendingAdvance()
        // A dropped tap used to vanish without a trace; count it instead.
        val expired = synchronized(advanceLock) { advanceRequests.expire(SystemClock.elapsedRealtime()) }
        if (expired > 0) Log.d(TAG, "advance.expired dropped=$expired")
        onFrameLoaded()
    }

    /**
     * Asks for another reload while the state's slot has no texture.
     *
     * A missing texture can be a decode that is still coming (the loader keeps
     * one reload in flight), so retrying is what makes a fallback temporary. A
     * corrupt file must not reload forever: the counter is per
     * `(generation, desired)` and gives up after [MAX_RELOAD_RETRIES].
     */
    private fun scheduleRetry(
        state: GroupedWallpaperFileState,
        retry: Boolean,
        desired: Int,
        lockScreen: Boolean,
    ) {
        if (!retry || desired < 0) {
            synchronized(advanceLock) {
                retryKey = null
                retryCount = 0
            }
            return
        }
        val file = state.slot(desired)?.let { GroupedWallpaperStateFile.photoFile(context, it.photoFor(lockScreen)) }
        if (file == null) {
            // No file will ever arrive through a reload; another bake has to
            // write it first.
            synchronized(advanceLock) {
                retryKey = null
                retryCount = 0
            }
            return
        }
        val key = state.generation to desired
        val attempts = synchronized(advanceLock) {
            if (retryKey != key) {
                retryKey = key
                retryCount = 0
            }
            retryCount += 1
            retryCount
        }
        if (attempts > MAX_RELOAD_RETRIES) {
            Log.w(TAG, "texture.giveup desired=$desired attempts=$attempts")
            return
        }
        Log.d(TAG, "reload.retry desired=$desired attempt=$attempts")
        requestReload()
    }

    /**
     * Keeps the slot on screen when a newer state is behind it.
     *
     * The app can bake from a runtime it read before a promotion landed, so a
     * new state sometimes still points at the slot the tap already left. Keeping
     * the displayed slot and shifting the queue forward avoids the visible
     * rewind, and the runtime is rewritten with the new generation so Dart adopts
     * the move instead of baking from the stale queue again.
     */
    private fun keepDisplayedSlot(newState: GroupedWallpaperFileState, previousGeneration: Int): GroupedWallpaperFileState {
        if (newState.generation <= previousGeneration) return newState
        // A previous/next history step deliberately shows a photo that is older
        // than the one on screen; its queue also starts with the old frame, so
        // the promotion heuristic below would wrongly keep it.
        if (newState.navigated) return newState
        // A fallback is not a promotion: the slot on screen is a stand-in, and
        // the new state's current is still the intended one.
        if (fallback) return newState
        val onScreen = displayed
        if (onScreen < 0) return newState
        // Only the queued next slot can be a promotion this reload missed.
        if (newState.next != onScreen) return newState
        GroupedWallpaperStateFile.writeRuntime(context, newState.generation, onScreen, -1, refillRequested = true)
        Log.d(TAG, "reload kept displayed=$onScreen over current=${newState.current}")
        return newState.copy(current = onScreen, previous = newState.current, next = -1)
    }

    private fun drawQuad(vertices: FloatBuffer, coords: FloatBuffer, texture: Int, alpha: Float) {
        GLES20.glUseProgram(program)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
        GLES20.glUniform1i(uTexture, 0)
        GLES20.glUniform1f(uAlpha, alpha)
        // The incoming frame is translucent over the outgoing one; an opaque
        // frame is drawn unblended so no driver does needless work.
        if (alpha < 1f) {
            GLES20.glEnable(GLES20.GL_BLEND)
            GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        } else {
            GLES20.glDisable(GLES20.GL_BLEND)
        }
        GLES20.glEnableVertexAttribArray(aPosition)
        GLES20.glVertexAttribPointer(aPosition, 2, GLES20.GL_FLOAT, false, 0, vertices)
        GLES20.glEnableVertexAttribArray(aTexCoord)
        GLES20.glVertexAttribPointer(aTexCoord, 2, GLES20.GL_FLOAT, false, 0, coords)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(aPosition)
        GLES20.glDisableVertexAttribArray(aTexCoord)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0)
    }

    /** Keeps the placeholder glyph square, centered and independent of the aspect. */
    private fun updatePlaceholderQuad() {
        val side = min(viewWidth, viewHeight) * 0.26f
        val halfWidth = side / viewWidth
        val halfHeight = side / viewHeight
        placeholderVertexBuffer
            .put(floatArrayOf(-halfWidth, -halfHeight, halfWidth, -halfHeight, -halfWidth, halfHeight, halfWidth, halfHeight))
            .position(0)
    }

    /**
     * A grey rounded frame with a slash: the "no wallpaper" state, drawn at
     * runtime so the service needs no drawable and cannot fail on a missing one.
     */
    private fun createPlaceholderBitmap(): Bitmap {
        val size = PLACEHOLDER_SIZE
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = PLACEHOLDER_FOREGROUND
            style = Paint.Style.STROKE
            strokeWidth = size * 0.045f
            strokeCap = Paint.Cap.ROUND
        }
        val inset = size * 0.18f
        val rect = RectF(inset, inset, size - inset, size - inset)
        val radius = size * 0.12f
        canvas.drawRoundRect(rect, radius, radius, paint)
        canvas.drawLine(rect.left + size * 0.06f, rect.bottom - size * 0.06f, rect.right - size * 0.06f, rect.top + size * 0.06f, paint)
        return bitmap
    }

    private fun createTexture(bitmap: Bitmap): Int {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        val id = textures[0]
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, id)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0)
        return id
    }

    private fun upload(texture: Int, bitmap: Bitmap) {
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0)
    }

    private fun deleteTexture(texture: Int) {
        GLES20.glDeleteTextures(1, intArrayOf(texture), 0)
    }

    private fun createProgram(vertexSource: String, fragmentSource: String): Int {
        val vertexShader = compileShader(GLES20.GL_VERTEX_SHADER, vertexSource)
        val fragmentShader = compileShader(GLES20.GL_FRAGMENT_SHADER, fragmentSource)
        val id = GLES20.glCreateProgram()
        GLES20.glAttachShader(id, vertexShader)
        GLES20.glAttachShader(id, fragmentShader)
        GLES20.glLinkProgram(id)

        val status = IntArray(1)
        GLES20.glGetProgramiv(id, GLES20.GL_LINK_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES20.glGetProgramInfoLog(id)
            GLES20.glDeleteProgram(id)
            throw RuntimeException("program link failed: $log")
        }

        GLES20.glDeleteShader(vertexShader)
        GLES20.glDeleteShader(fragmentShader)
        return id
    }

    private fun compileShader(type: Int, source: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)

        val status = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES20.glGetShaderInfoLog(shader)
            GLES20.glDeleteShader(shader)
            throw RuntimeException("shader compile failed: $log")
        }
        return shader
    }
}
