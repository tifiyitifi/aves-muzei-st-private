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

package deckers.thibault.aves.features.muzei_wallpaper

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.GLUtils
import android.util.Log
import deckers.thibault.aves.R
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/**
 * State-driven wallpaper renderer.
 *
 * Adapted from Muzei's `render/MuzeiBlurRenderer.kt` and `render/GLPictureSet.kt`
 * (https://github.com/muzei/muzei, Apache-2.0) for the texture upload, cover-fit
 * crop and reload contract. The Flutter side bakes `slots/<id>/sharp.png`, and
 * this renderer only uploads that bitmap; effects, gestures and crossfades land
 * in the next milestones.
 */
class WallpaperRenderer(
    private val context: Context,
    private val requestRender: () -> Unit,
) : GLSurfaceView.Renderer {
    companion object {
        private const val TAG = "AvesLiveWallpaper"

        private const val VERTEX_SHADER = """
            attribute vec4 aPosition;
            attribute vec2 aTexCoord;
            varying vec2 vTexCoord;
            void main() {
                gl_Position = aPosition;
                vTexCoord = aTexCoord;
            }
        """

        private const val FRAGMENT_SHADER = """
            precision mediump float;
            uniform sampler2D uTexture;
            varying vec2 vTexCoord;
            void main() {
                gl_FragColor = texture2D(uTexture, vTexCoord);
            }
        """
    }

    private val store = WallpaperStateStore.forContext(context)

    /** Disk reads and PNG decodes never run on the GL thread. */
    private val loader = Executors.newSingleThreadExecutor()

    private val reloadInFlight = AtomicBoolean(false)
    private val reloadAgain = AtomicBoolean(false)

    @Volatile
    private var destroyed = false

    @Volatile
    private var pending: LoadedState? = null

    private var program = 0
    private var texture = 0
    private var aPosition = -1
    private var aTexCoord = -1
    private var uTexture = -1

    private var viewWidth = 1
    private var viewHeight = 1
    private var textureWidth = 1
    private var textureHeight = 1

    private val vertexBuffer: FloatBuffer = ByteBuffer
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

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        Log.d(TAG, "surface.created")
        destroyed = false
        try {
            program = createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
            aPosition = GLES20.glGetAttribLocation(program, "aPosition")
            aTexCoord = GLES20.glGetAttribLocation(program, "aTexCoord")
            uTexture = GLES20.glGetUniformLocation(program, "uTexture")
            // The spike is a neutral placeholder while the first state loads; a
            // real artwork replaces it as soon as the loader finishes.
            loadSpikeTexture()
            WallpaperRenderBus.attach(this)
            requestReload()
        } catch (t: Throwable) {
            Log.e(TAG, "renderer init failed, falling back to solid color", t)
            program = 0
        }
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        Log.d(TAG, "surface.changed w=$width h=$height")
        viewWidth = width.coerceAtLeast(1)
        viewHeight = height.coerceAtLeast(1)
        GLES20.glViewport(0, 0, viewWidth, viewHeight)
        updateTexCoords()
    }

    override fun onDrawFrame(gl: GL10?) {
        pending?.let { loaded ->
            pending = null
            uploadTexture(loaded)
        }

        GLES20.glClearColor(0.05f, 0.06f, 0.08f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        if (program == 0 || texture == 0) {
            return
        }

        GLES20.glUseProgram(program)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
        GLES20.glUniform1i(uTexture, 0)

        vertexBuffer.position(0)
        GLES20.glEnableVertexAttribArray(aPosition)
        GLES20.glVertexAttribPointer(aPosition, 2, GLES20.GL_FLOAT, false, 0, vertexBuffer)

        texCoordBuffer.position(0)
        GLES20.glEnableVertexAttribArray(aTexCoord)
        GLES20.glVertexAttribPointer(aTexCoord, 2, GLES20.GL_FLOAT, false, 0, texCoordBuffer)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        GLES20.glDisableVertexAttribArray(aPosition)
        GLES20.glDisableVertexAttribArray(aTexCoord)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0)
    }

    /**
     * Asks the loader thread to read `state.json` and decode the current slot.
     *
     * Called from the Flutter channel (any thread) and from the bus. Coalesces
     * concurrent requests: at most one decode runs, and a request that arrives
     * during it is replayed once.
     */
    fun requestReload() {
        if (destroyed) return
        if (!reloadInFlight.compareAndSet(false, true)) {
            reloadAgain.set(true)
            return
        }
        try {
            loader.execute {
                val loaded = loadState()
                if (destroyed) {
                    loaded?.bitmap?.recycle()
                    reloadInFlight.set(false)
                    return@execute
                }
                pending = loaded
                reloadInFlight.set(false)
                requestRender()
                if (reloadAgain.compareAndSet(true, false)) {
                    requestReload()
                }
            }
        } catch (e: java.util.concurrent.RejectedExecutionException) {
            // The engine was destroyed between the check and the submit.
            reloadInFlight.set(false)
            Log.d(TAG, "reload ignored after renderer shutdown")
        }
    }

    fun destroy() {
        Log.d(TAG, "renderer.destroy")
        destroyed = true
        WallpaperRenderBus.detach(this)
        loader.shutdownNow()
        pending?.bitmap?.recycle()
        pending = null
        if (texture != 0) {
            GLES20.glDeleteTextures(1, intArrayOf(texture), 0)
            texture = 0
        }
        if (program != 0) {
            GLES20.glDeleteProgram(program)
            program = 0
        }
    }

    private fun loadState(): LoadedState? {
        return try {
            val state = store.readState() ?: return null
            val sharp = state.currentSharp ?: return null
            val bitmap = BitmapFactory.decodeFile(sharp.absolutePath) ?: run {
                Log.e(TAG, "failed to decode ${sharp.absolutePath}")
                return null
            }
            LoadedState(state.generation, state.current, state.next, bitmap)
        } catch (t: Throwable) {
            Log.e(TAG, "failed to load wallpaper state", t)
            null
        }
    }

    private fun uploadTexture(loaded: LoadedState) {
        val bitmap: Bitmap = loaded.bitmap
        if (bitmap.isRecycled || bitmap.width <= 0 || bitmap.height <= 0) {
            bitmap.recycle()
            return
        }
        if (texture != 0) {
            GLES20.glDeleteTextures(1, intArrayOf(texture), 0)
        }
        texture = createTexture(bitmap)
        textureWidth = bitmap.width
        textureHeight = bitmap.height
        updateTexCoords()
        bitmap.recycle()
        try {
            store.writeRuntime(
                WallpaperRuntime(
                    generation = loaded.generation,
                    current = loaded.current,
                    next = loaded.next,
                ),
            )
        } catch (t: Throwable) {
            Log.w(TAG, "failed to write runtime", t)
        }
        Log.d(TAG, "texture.loaded generation=${loaded.generation} slot=${loaded.current} w=$textureWidth h=$textureHeight")
    }

    private fun loadSpikeTexture() {
        val bitmap = BitmapFactory.decodeResource(context.resources, R.drawable.live_wallpaper_spike)
        if (bitmap == null) {
            Log.e(TAG, "spike bitmap could not be decoded")
            return
        }
        textureWidth = bitmap.width
        textureHeight = bitmap.height
        texture = createTexture(bitmap)
        bitmap.recycle()
        updateTexCoords()
        Log.d(TAG, "texture.spike w=$textureWidth h=$textureHeight")
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

    private fun updateTexCoords() {
        val viewAspect = viewWidth.toFloat() / viewHeight.toFloat()
        val textureAspect = textureWidth.toFloat() / textureHeight.toFloat()

        var u0 = 0f
        var u1 = 1f
        var v0 = 0f
        var v1 = 1f
        if (textureAspect > viewAspect) {
            val visible = viewAspect / textureAspect
            u0 = (1f - visible) / 2f
            u1 = 1f - u0
        } else {
            val visible = textureAspect / viewAspect
            v0 = (1f - visible) / 2f
            v1 = 1f - v0
        }

        // Bitmap row 0 is the top row; map it to the top of the quad.
        texCoordBuffer.position(0)
        texCoordBuffer.put(floatArrayOf(u0, v1, u1, v1, u0, v0, u1, v0))
        texCoordBuffer.position(0)
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

    private data class LoadedState(
        val generation: Int,
        val current: Int,
        val next: Int,
        val bitmap: Bitmap,
    )
}
