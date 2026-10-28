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
 * Draws one baked photo, or a grey placeholder when there is none.
 *
 * The engine bakes a single cover-cropped PNG per frame, so there is no slot
 * queue, no crossfade and no effect texture here: the renderer uploads
 * `current.png`, pans it with the launcher offset and otherwise stays idle. All
 * file reads and PNG decodes happen on a loader thread; the GL thread only
 * uploads the decoded bitmap, so a slow disk never stalls a frame.
 */
class GroupedWallpaperRenderer(
    private val context: Context,
    private val requestRender: () -> Unit,
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
            varying vec2 vTexCoord;
            void main() {
                gl_FragColor = texture2D(uTexture, vTexCoord);
            }
        """
    }

    private class LoadedFrame(val generation: Int, val photo: String, val bitmap: Bitmap?)

    /** Disk reads and PNG decodes never run on the GL thread. */
    private val loader = Executors.newSingleThreadExecutor()

    private val reloadInFlight = AtomicBoolean(false)
    private val reloadAgain = AtomicBoolean(false)

    @Volatile
    private var destroyed = false

    /** Decoded by [loader], uploaded by the GL thread. */
    @Volatile
    private var pending: LoadedFrame? = null

    @Volatile
    private var offsetX = 0.5f

    private var program = 0
    private var aPosition = -1
    private var aTexCoord = -1
    private var uTexture = -1

    private var viewWidth = 1
    private var viewHeight = 1

    private var photoTexture = 0
    private var photoAspect = 1f
    private var hasPhoto = false
    private var currentGeneration = Int.MIN_VALUE
    private var currentPhoto = ""

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
        Log.d(TAG, "surface.created")
        destroyed = false
        // A new EGL context invalidates every texture id from the previous one.
        photoTexture = 0
        placeholderTexture = 0
        hasPhoto = false
        currentGeneration = Int.MIN_VALUE
        currentPhoto = ""
        try {
            program = createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
            aPosition = GLES20.glGetAttribLocation(program, "aPosition")
            aTexCoord = GLES20.glGetAttribLocation(program, "aTexCoord")
            uTexture = GLES20.glGetUniformLocation(program, "uTexture")
            GLES20.glDisable(GLES20.GL_DEPTH_TEST)
            GLES20.glClearColor(
                ((PLACEHOLDER_BACKGROUND shr 16) and 0xFF) / 255f,
                ((PLACEHOLDER_BACKGROUND shr 8) and 0xFF) / 255f,
                (PLACEHOLDER_BACKGROUND and 0xFF) / 255f,
                1f,
            )
            placeholderTexture = createTexture(createPlaceholderBitmap())
            GroupedWallpaperRenderBus.attach(this)
            requestReload()
        } catch (t: Throwable) {
            // A driver that refuses the program still gets the grey background
            // instead of a black or frozen surface.
            Log.e(TAG, "renderer init failed, falling back to the background color", t)
            program = 0
            photoTexture = 0
            placeholderTexture = 0
        }
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

        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        if (program == 0) return

        if (hasPhoto && photoTexture != 0) {
            GroupedWallpaperViewport.texCoords(texCoords, photoAspect, viewWidth.toFloat() / viewHeight.toFloat(), offsetX)
            texCoordBuffer.put(texCoords).position(0)
            drawQuad(fullVertexBuffer, texCoordBuffer, photoTexture)
        } else if (placeholderTexture != 0) {
            drawQuad(placeholderVertexBuffer, placeholderTexCoords, placeholderTexture)
        }
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
                    loaded?.bitmap?.recycle()
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

    fun destroy() {
        destroyed = true
        GroupedWallpaperRenderBus.detach(this)
        loader.shutdownNow()
    }

    private fun loadFrame(): LoadedFrame {
        val state = GroupedWallpaperStateFile.read(context)
        val photo = GroupedWallpaperStateFile.photoFile(context, state)
        if (photo == null) return LoadedFrame(state?.generation ?: -1, "", null)
        val bitmap = decode(photo)
        return LoadedFrame(state?.generation ?: -1, state?.photo ?: "", bitmap)
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
        BitmapFactory.decodeFile(file.absolutePath, options)
    } catch (t: Throwable) {
        // A corrupt bake shows the placeholder instead of crashing the service.
        Log.w(TAG, "failed to decode ${file.name}", t)
        null
    }

    private fun consumePending() {
        val loaded = pending ?: return
        pending = null
        if (loaded.generation == currentGeneration && loaded.photo == currentPhoto) {
            loaded.bitmap?.recycle()
            return
        }
        currentGeneration = loaded.generation
        currentPhoto = loaded.photo
        val bitmap = loaded.bitmap
        if (bitmap == null) {
            hasPhoto = false
            return
        }
        try {
            if (photoTexture == 0) photoTexture = createTexture(bitmap)
            else upload(photoTexture, bitmap)
            photoAspect = bitmap.width.toFloat() / bitmap.height.toFloat().coerceAtLeast(1f)
            hasPhoto = true
        } finally {
            bitmap.recycle()
        }
    }

    private fun drawQuad(vertices: FloatBuffer, coords: FloatBuffer, texture: Int) {
        GLES20.glUseProgram(program)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
        GLES20.glUniform1i(uTexture, 0)
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
