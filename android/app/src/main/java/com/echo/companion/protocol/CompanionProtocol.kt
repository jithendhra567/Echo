package com.echo.companion.protocol

import org.json.JSONArray
import org.json.JSONObject

data class PairingPayload(
    val version: Int,
    val host: String,
    val port: Int,
    val token: String,
    val hostName: String,
) {
    val wsUrl: String get() = "ws://$host:$port"

    companion object {
        fun parse(raw: String): PairingPayload? {
            val uri = android.net.Uri.parse(raw.trim())
            if (uri.scheme != "echo") return null
            if (uri.host != "pair" && !uri.path.isNullOrEmpty() && uri.path != "/pair") {
                // allow echo://pair?...
            }
            val host = uri.getQueryParameter("host") ?: return null
            val port = uri.getQueryParameter("port")?.toIntOrNull() ?: return null
            val token = uri.getQueryParameter("token") ?: return null
            if (token.isBlank()) return null
            val version = uri.getQueryParameter("v")?.toIntOrNull() ?: 1
            val name = uri.getQueryParameter("name") ?: "Mac"
            return PairingPayload(version, host, port, token, name)
        }
    }
}

data class ClipDto(
    val id: String,
    val contentType: String,
    val text: String?,
    val contentBase64: String?,
    val sourceAppName: String?,
    val createdAt: Double,
    val isPinned: Boolean,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("contentType", contentType)
        put("text", text)
        put("contentBase64", contentBase64)
        put("sourceAppName", sourceAppName)
        put("createdAt", createdAt)
        put("isPinned", isPinned)
    }

    companion object {
        fun fromJson(o: JSONObject): ClipDto = ClipDto(
            id = o.optString("id"),
            contentType = o.optString("contentType", "plain_text"),
            text = o.optString("text").takeIf { it.isNotEmpty() },
            contentBase64 = o.optString("contentBase64").takeIf { it.isNotEmpty() },
            sourceAppName = o.optString("sourceAppName").takeIf { it.isNotEmpty() },
            createdAt = o.optDouble("createdAt", 0.0),
            isPinned = o.optBoolean("isPinned", false),
        )
    }
}

data class AppDto(
    val bundleId: String,
    val name: String,
    val isRunning: Boolean,
    val iconBase64: String?,
) {
    companion object {
        fun fromJson(o: JSONObject): AppDto = AppDto(
            bundleId = o.optString("bundleId"),
            name = o.optString("name"),
            isRunning = o.optBoolean("isRunning", true),
            iconBase64 = o.optString("iconBase64").takeIf { it.isNotEmpty() },
        )
    }
}

sealed class CompanionMessage {
    data class Hello(val token: String, val deviceName: String) : CompanionMessage()
    data class HelloOk(val deviceId: String, val hostName: String) : CompanionMessage()
    data class ClipHistory(val clips: List<ClipDto>) : CompanionMessage()
    data class ClipPush(val clip: ClipDto) : CompanionMessage()
    data class AppsList(val apps: List<AppDto>) : CompanionMessage()
    data class StreamStart(val bundleId: String) : CompanionMessage()
    data class StreamFrame(val width: Int, val height: Int, val jpegBase64: String) : CompanionMessage()
    data object StreamStop : CompanionMessage()
    data class Input(
        val kind: String,
        val x: Double? = null,
        val y: Double? = null,
        val dx: Double? = null,
        val dy: Double? = null,
        val key: String? = null,
    ) : CompanionMessage()
    data class Error(val message: String) : CompanionMessage()
    data object Ping : CompanionMessage()
    data object Pong : CompanionMessage()

    fun toJson(): String {
        val o = JSONObject()
        when (this) {
            is Hello -> {
                o.put("type", "hello")
                o.put("token", token)
                o.put("deviceName", deviceName)
            }
            is HelloOk -> {
                o.put("type", "hello_ok")
                o.put("deviceId", deviceId)
                o.put("hostName", hostName)
            }
            is ClipHistory -> {
                o.put("type", "clip_history")
                val arr = JSONArray()
                clips.forEach { arr.put(it.toJson()) }
                o.put("clips", arr)
            }
            is ClipPush -> {
                o.put("type", "clip_push")
                o.put("clip", clip.toJson())
            }
            is AppsList -> {
                o.put("type", "apps_list")
                // outbound rarely needed
            }
            is StreamStart -> {
                o.put("type", "stream_start")
                o.put("bundleId", bundleId)
            }
            is StreamFrame -> {
                o.put("type", "stream_frame")
                o.put("width", width)
                o.put("height", height)
                o.put("data", jpegBase64)
            }
            StreamStop -> o.put("type", "stream_stop")
            is Input -> {
                o.put("type", "input")
                o.put("kind", kind)
                x?.let { o.put("x", it) }
                y?.let { o.put("y", it) }
                dx?.let { o.put("dx", it) }
                dy?.let { o.put("dy", it) }
                key?.let { o.put("key", it) }
            }
            is Error -> {
                o.put("type", "error")
                o.put("message", message)
            }
            Ping -> o.put("type", "ping")
            Pong -> o.put("type", "pong")
        }
        return o.toString()
    }

    companion object {
        fun parse(raw: String): CompanionMessage? {
            return try {
                val o = JSONObject(raw)
                when (o.getString("type")) {
                    "hello_ok" -> HelloOk(o.getString("deviceId"), o.getString("hostName"))
                    "clip_history" -> {
                        val arr = o.getJSONArray("clips")
                        val list = buildList {
                            for (i in 0 until arr.length()) add(ClipDto.fromJson(arr.getJSONObject(i)))
                        }
                        ClipHistory(list)
                    }
                    "clip_push" -> ClipPush(ClipDto.fromJson(o.getJSONObject("clip")))
                    "apps_list" -> {
                        val arr = o.getJSONArray("apps")
                        val list = buildList {
                            for (i in 0 until arr.length()) add(AppDto.fromJson(arr.getJSONObject(i)))
                        }
                        AppsList(list)
                    }
                    "stream_frame" -> StreamFrame(
                        o.getInt("width"),
                        o.getInt("height"),
                        o.getString("data"),
                    )
                    "error" -> Error(o.optString("message", "Unknown error"))
                    "pong" -> Pong
                    "ping" -> Ping
                    else -> null
                }
            } catch (_: Exception) {
                null
            }
        }
    }
}
