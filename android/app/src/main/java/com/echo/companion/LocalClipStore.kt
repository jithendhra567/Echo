package com.echo.companion

import android.content.Context
import com.echo.companion.protocol.ClipDto
import org.json.JSONArray

/** Persists clipboard history on the phone for offline capture and merge-on-connect. */
class LocalClipStore(context: Context) {
    private val prefs = context.getSharedPreferences("echo_clips", Context.MODE_PRIVATE)
    private val key = "clips_json"
    private val maxClips = 80

    fun load(): List<ClipDto> {
        val raw = prefs.getString(key, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            buildList {
                for (i in 0 until arr.length()) {
                    add(ClipDto.fromJson(arr.getJSONObject(i)))
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun save(clips: List<ClipDto>) {
        val trimmed = clips
            .sortedByDescending { it.createdAt }
            .distinctBy { contentKey(it) }
            .take(maxClips)
        val arr = JSONArray()
        trimmed.forEach { arr.put(it.toJson()) }
        prefs.edit().putString(key, arr.toString()).apply()
    }

    fun upsert(clip: ClipDto): List<ClipDto> {
        val merged = merge(load(), listOf(clip))
        save(merged)
        return merged
    }

    companion object {
        fun contentKey(clip: ClipDto): String {
            val body = clip.text?.trim().orEmpty().ifEmpty {
                clip.contentBase64?.take(128).orEmpty()
            }
            return "${clip.contentType}|$body"
        }

        fun merge(vararg lists: List<ClipDto>): List<ClipDto> {
            val byContent = LinkedHashMap<String, ClipDto>()
            lists.asList()
                .flatten()
                .sortedByDescending { it.createdAt }
                .forEach { clip ->
                    val key = contentKey(clip)
                    if (key == "${clip.contentType}|" || key.isBlank()) {
                        byContent.putIfAbsent(clip.id, clip)
                    } else {
                        byContent.putIfAbsent(key, clip)
                    }
                }
            return byContent.values.sortedByDescending { it.createdAt }
        }
    }
}
