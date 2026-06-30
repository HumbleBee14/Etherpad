package com.humblebee.etherpad.recording

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.humblebee.etherpad.engine.Synth
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

internal class Recorder(
    private val ctx: Context,
    private val synth: Synth,
    private val scope: CoroutineScope,
) {
    companion object {
        const val MAX_DURATION_MS = 10L * 60L * 1000L
        private const val SUBDIR = "Etherpad"
    }

    var isRecording by mutableStateOf(false)
        private set

    private var capJob: Job? = null
    private var pendingUri: Uri? = null   // Q+: finalize on stop
    private var pendingFile: File? = null // shared on stop

    fun toggle() = if (isRecording) stop() else start()

    private fun start() {
        if (isRecording) return
        val name = "Etherpad-${timestamp()}.wav"
        val opened = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) openMediaStore(name)
                     else openLegacy(name)
        if (opened == null) return
        if (!synth.startRecording(opened)) {
            cleanupFailedStart()
            return
        }
        isRecording = true
        capJob = scope.launch {
            delay(MAX_DURATION_MS)
            stop()
        }
    }

    private fun stop() {
        if (!isRecording) return
        isRecording = false
        capJob?.cancel(); capJob = null
        synth.stopRecording()
        finalizeAndShare()
    }

    private fun openMediaStore(name: String): String? {
        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, name)
            put(MediaStore.Audio.Media.MIME_TYPE, "audio/wav")
            put(MediaStore.Audio.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MUSIC}/$SUBDIR")
            put(MediaStore.Audio.Media.IS_PENDING, 1)
        }
        val resolver = ctx.contentResolver
        val uri = resolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values) ?: return null
        // Native fopen() needs a path, so hand it the MediaStore fd via /proc.
        val pfd = resolver.openFileDescriptor(uri, "w")
        if (pfd == null) {
            resolver.delete(uri, null, null)  // don't orphan the pending row
            return null
        }
        pendingUri = uri
        openFds = pfd  // kept alive for the recording's lifetime
        return "/proc/self/fd/${pfd.fd}"
    }

    private var openFds: android.os.ParcelFileDescriptor? = null

    private fun openLegacy(name: String): String? {
        @Suppress("DEPRECATION")
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC), SUBDIR)
        if (!dir.exists() && !dir.mkdirs()) return null
        val file = File(dir, name)
        pendingFile = file
        return file.absolutePath
    }

    private fun finalizeAndShare() {
        val uri: Uri? = when {
            pendingUri != null -> {
                openFds?.close(); openFds = null
                val values = ContentValues().apply { put(MediaStore.Audio.Media.IS_PENDING, 0) }
                ctx.contentResolver.update(pendingUri!!, values, null, null)
                pendingUri
            }
            pendingFile != null -> {
                androidx.core.content.FileProvider.getUriForFile(
                    ctx, "${ctx.packageName}.fileprovider", pendingFile!!,
                )
            }
            else -> null
        }
        pendingUri = null; pendingFile = null
        if (uri != null) share(uri)
    }

    private fun share(uri: Uri) {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "audio/wav"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        ctx.startActivity(Intent.createChooser(intent, "Share recording").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        })
    }

    private fun cleanupFailedStart() {
        openFds?.close(); openFds = null
        pendingUri?.let { ctx.contentResolver.delete(it, null, null) }
        pendingFile?.delete()
        pendingUri = null; pendingFile = null
    }

    private fun timestamp(): String =
        SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
}
