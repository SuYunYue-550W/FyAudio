// Android 数据模型
package com.fyaudio.syncplayer.model

import org.json.JSONObject

data class DeviceInfo(
    val deviceId: String,
    val deviceName: String,
    val platform: String,
    val role: String,
    val ip: String,
    val sampleRate: Int = 44100,
    val channels: Int = 2,
    val capabilities: List<String> = emptyList(),
    val bluetoothConnected: Boolean = false,
    val isSource: Boolean = false,
    val volume: Int = 80,
    val latencyCompensate: Int = 0,
    val version: String = "1.0.0"
) {
    companion object {
        fun fromJson(json: JSONObject): DeviceInfo {
            return DeviceInfo(
                deviceId = json.optString("device_id", ""),
                deviceName = json.optString("device_name", ""),
                platform = json.optString("platform", ""),
                role = json.optString("role", "receiver"),
                ip = json.optString("ip", ""),
                sampleRate = json.optInt("audio_sample_rate", 44100),
                channels = json.optInt("audio_channels", 2),
                capabilities = json.optJSONArray("capabilities")?.let { arr ->
                    (0 until arr.length()).map { arr.getString(it) }
                } ?: emptyList(),
                bluetoothConnected = json.optBoolean("bluetooth_connected", false),
                isSource = json.optBoolean("is_source", false),
                volume = json.optInt("volume", 80),
                latencyCompensate = json.optInt("latency_compensate", 0),
                version = json.optString("version", "1.0.0")
            )
        }
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("device_id", deviceId)
        put("device_name", deviceName)
        put("platform", platform)
        put("role", role)
        put("ip", ip)
        put("audio_sample_rate", sampleRate)
        put("audio_channels", channels)
        put("capabilities", capabilities)
        put("bluetooth_connected", bluetoothConnected)
        put("is_source", isSource)
        put("volume", volume)
        put("latency_compensate", latencyCompensate)
        put("version", version)
    }

    val platformIcon: String
        get() = when (platform) {
            "windows" -> "🖥️"
            "mac" -> "🍎"
            "android" -> "📱"
            "raspberrypi" -> "🍓"
            else -> "📟"
        }

    val hasBluetooth: Boolean get() = capabilities.contains("bluetooth")
    val hasSpeaker: Boolean get() = capabilities.contains("speaker")
}

data class AudioFrame(
    val timestamp: Long,
    val payload: ByteArray
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as AudioFrame
        return timestamp == other.timestamp && payload.contentEquals(other.payload)
    }

    override fun hashCode(): Int {
        var result = timestamp.hashCode()
        result = 31 * result + payload.contentHashCode()
        return result
    }
}

data class SyncStats(
    val bufferFrames: Int = 0,
    val estimatedRTT: Int = 0,
    val windowMs: Int = 40,
    val offsetMs: Int = 0,
    val isPlaying: Boolean = false,
    val droppedFrames: Long = 0,
    val totalFrames: Long = 0
) {
    val dropRate: Float
        get() = if (totalFrames > 0) droppedFrames.toFloat() / totalFrames else 0f
}
