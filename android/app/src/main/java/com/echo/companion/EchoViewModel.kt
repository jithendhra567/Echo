package com.echo.companion

import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.util.Base64
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.echo.companion.net.EchoSocketClient
import com.echo.companion.protocol.AppDto
import com.echo.companion.protocol.ClipDto
import com.echo.companion.protocol.CompanionMessage
import com.echo.companion.protocol.PairingPayload
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class EchoUiState(
    val connection: EchoSocketClient.State = EchoSocketClient.State.Idle,
    val hostName: String? = null,
    val clips: List<ClipDto> = emptyList(),
    val apps: List<AppDto> = emptyList(),
    val streamBitmap: Bitmap? = null,
    val streamingBundleId: String? = null,
    val error: String? = null,
    val lastPairing: PairingPayload? = null,
)

class EchoViewModel(app: Application) : AndroidViewModel(app) {
    private val prefs = app.getSharedPreferences("echo_pair", Context.MODE_PRIVATE)
    private val localClips = LocalClipStore(app)
    private val clipboard =
        app.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    private val _state = MutableStateFlow(EchoUiState(clips = localClips.load()))
    val state: StateFlow<EchoUiState> = _state.asStateFlow()

    /** After hello_ok we expect Mac history once, then we upload ours and stop the handshake loop. */
    private var awaitingMacHistory = false
    private var suppressClipboardEcho = false
    private var lastPushedText: String? = null

    private val client = EchoSocketClient(
        onMessage = { msg -> viewModelScope.launch { handle(msg) } },
        onState = { s ->
            _state.update { it.copy(connection = s) }
            if (s == EchoSocketClient.State.Connected) {
                awaitingMacHistory = true
            }
        },
    )

    private val clipListener = ClipboardManager.OnPrimaryClipChangedListener {
        if (suppressClipboardEcho) return@OnPrimaryClipChangedListener
        val text = readPrimaryClipText() ?: return@OnPrimaryClipChangedListener
        if (text.isBlank() || text == lastPushedText) return@OnPrimaryClipChangedListener
        ingestLocalCopy(text, sourceAppName = "Android")
    }

    init {
        loadSavedPairing()?.let { payload ->
            _state.update { it.copy(lastPairing = payload) }
        }
        clipboard.addPrimaryClipChangedListener(clipListener)
    }

    override fun onCleared() {
        clipboard.removePrimaryClipChangedListener(clipListener)
        super.onCleared()
    }

    fun connect(payload: PairingPayload) {
        savePairing(payload)
        awaitingMacHistory = true
        _state.update { it.copy(lastPairing = payload, error = null, hostName = payload.hostName) }
        client.connect(payload, deviceName = Build.MODEL)
    }

    fun reconnect() {
        state.value.lastPairing?.let(::connect)
    }

    fun disconnect() {
        client.send(CompanionMessage.StreamStop)
        client.disconnect()
        awaitingMacHistory = false
        _state.update {
            it.copy(
                connection = EchoSocketClient.State.Closed,
                streamBitmap = null,
                streamingBundleId = null,
            )
        }
    }

    /** Manual send from the Echo UI, or system clipboard capture. */
    fun pushClipboardText(text: String) {
        ingestLocalCopy(text.trim(), sourceAppName = "Android")
    }

    fun copyClipToDevice(clip: ClipDto) {
        clip.text?.let { writeDeviceClipboard(it) }
    }

    /** Call when the app returns to foreground — Android only exposes clipboard while focused. */
    fun captureClipboardIfChanged() {
        if (suppressClipboardEcho) return
        val text = readPrimaryClipText() ?: return
        if (text.isBlank() || text == lastPushedText) return
        val already = state.value.clips.firstOrNull()?.text
        if (text == already) return
        ingestLocalCopy(text, sourceAppName = "Android")
    }

    fun startStream(bundleId: String) {
        client.send(CompanionMessage.StreamStop)
        client.send(CompanionMessage.StreamStart(bundleId))
        _state.update { it.copy(streamingBundleId = bundleId, streamBitmap = null, error = null) }
    }

    fun stopStream() {
        client.send(CompanionMessage.StreamStop)
        _state.update { it.copy(streamingBundleId = null, streamBitmap = null) }
    }

    fun sendTap(nx: Double, ny: Double) {
        client.send(CompanionMessage.Input(kind = "tap", x = nx, y = ny))
    }

    fun sendScroll(dx: Double, dy: Double, nx: Double, ny: Double) {
        client.send(CompanionMessage.Input(kind = "scroll", x = nx, y = ny, dx = dx, dy = dy))
    }

    fun sendKey(text: String) {
        client.send(CompanionMessage.Input(kind = "key", key = text))
    }

    private fun ingestLocalCopy(text: String, sourceAppName: String) {
        if (text.isBlank()) return
        val clip = ClipDto(
            id = java.util.UUID.randomUUID().toString(),
            contentType = if (looksLikeUrl(text)) "url" else "plain_text",
            text = text,
            contentBase64 = null,
            sourceAppName = sourceAppName,
            createdAt = System.currentTimeMillis() / 1000.0,
            isPinned = false,
        )
        val merged = localClips.upsert(clip)
        lastPushedText = text
        _state.update { it.copy(clips = merged) }
        if (client.isOpen()) {
            client.send(CompanionMessage.ClipPush(clip))
        }
        // Only write back if clipboard doesn't already hold this text (avoids echo loops).
        if (readPrimaryClipText() != text) {
            writeDeviceClipboard(text)
        }
    }

    private fun handle(message: CompanionMessage) {
        when (message) {
            is CompanionMessage.HelloOk -> {
                awaitingMacHistory = true
                _state.update { it.copy(hostName = message.hostName, error = null) }
            }
            is CompanionMessage.ClipHistory -> {
                val merged = LocalClipStore.merge(localClips.load(), message.clips)
                localClips.save(merged)
                _state.update { it.copy(clips = merged) }

                if (awaitingMacHistory) {
                    awaitingMacHistory = false
                    // Upload phone-side history so Mac can merge offline copies.
                    client.send(CompanionMessage.ClipHistory(merged))
                }
            }
            is CompanionMessage.ClipPush -> {
                val merged = localClips.upsert(message.clip)
                _state.update { it.copy(clips = merged) }
                message.clip.text?.let { writeDeviceClipboard(it) }
            }
            is CompanionMessage.AppsList -> {
                _state.update { it.copy(apps = message.apps) }
            }
            is CompanionMessage.StreamFrame -> {
                val bytes = Base64.decode(message.jpegBase64, Base64.DEFAULT)
                val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return
                _state.update { it.copy(streamBitmap = bmp) }
            }
            is CompanionMessage.Error -> {
                _state.update { it.copy(error = message.message) }
            }
            CompanionMessage.Ping -> client.send(CompanionMessage.Pong)
            else -> Unit
        }
    }

    private fun writeDeviceClipboard(text: String) {
        suppressClipboardEcho = true
        lastPushedText = text
        clipboard.setPrimaryClip(ClipData.newPlainText("Echo", text))
        // Listener may fire synchronously; clear flag on next loop.
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            suppressClipboardEcho = false
        }
    }

    private fun readPrimaryClipText(): String? {
        val clip = clipboard.primaryClip ?: return null
        if (clip.itemCount == 0) return null
        return clip.getItemAt(0).coerceToText(getApplication()).toString().trim().ifEmpty { null }
    }

    private fun looksLikeUrl(text: String): Boolean {
        val t = text.lowercase()
        return t.startsWith("http://") || t.startsWith("https://")
    }

    private fun savePairing(payload: PairingPayload) {
        prefs.edit()
            .putString("host", payload.host)
            .putInt("port", payload.port)
            .putString("token", payload.token)
            .putString("name", payload.hostName)
            .putInt("v", payload.version)
            .apply()
    }

    private fun loadSavedPairing(): PairingPayload? {
        val host = prefs.getString("host", null) ?: return null
        val token = prefs.getString("token", null) ?: return null
        val port = prefs.getInt("port", 8742)
        val name = prefs.getString("name", "Mac") ?: "Mac"
        val v = prefs.getInt("v", 1)
        return PairingPayload(v, host, port, token, name)
    }
}
