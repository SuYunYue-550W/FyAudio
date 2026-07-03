// Android 网络通信模块
package com.fyaudio.syncplayer.network

import android.content.Context
import android.util.Log
import kotlinx.coroutines.*
import java.net.*
import com.fyaudio.syncplayer.protocol.*
import com.fyaudio.syncplayer.model.*

class NetworkManager(
    private val context: Context,
    private val deviceId: String,
    private val deviceName: String,
    private val platform: String,
    private val onDeviceOnline: (DeviceInfo) -> Unit,
    private val onDeviceOffline: (String) -> Unit,
    private val onAudioFrame: (AudioFrame) -> Unit,
    private val onVolumeSync: (Int) -> Unit
) {
    companion object {
        private const val TAG = "FyAudio-Network"
        const val PORT_AUDIO = 5001
        const val PORT_CONTROL = 5002
    }

    private var controlSocket: DatagramSocket? = null
    private var audioSocket: DatagramSocket? = null
    private var isRunning = false
    private var currentRole = "receiver"
    private var localIP = ""

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    init {
        localIP = getLocalIP()
    }

    // =========================================================================
    // 启动
    // =========================================================================

    fun start() {
        if (isRunning) return
        isRunning = true

        // 绑定控制端口
        try {
            controlSocket = DatagramSocket(PORT_CONTROL).apply {
                broadcast = true
                soTimeout = 1000
            }
        } catch (e: Exception) {
            Log.e(TAG, "控制端口绑定失败", e)
        }

        // 仅Receiver模式绑定音频端口
        if (currentRole != "source") {
            try {
                audioSocket = DatagramSocket(PORT_AUDIO).apply {
                    receiveBufferSize = 1024 * 1024
                    soTimeout = 100
                }
            } catch (e: Exception) {
                Log.e(TAG, "音频端口绑定失败", e)
            }
        }

        // 启动接收
        scope.launch { receiveControlLoop() }
        scope.launch { receiveAudioLoop() }

        // 发送上线广播和发现
        scope.launch {
            delay(100)
            sendOnlineBroadcast()
            sendDiscover()
        }

        // 心跳定时器
        scope.launch {
            while (isRunning) {
                delay(3000)
                sendHeartbeat()
            }
        }

        Log.i(TAG, "网络服务已启动, IP: $localIP")
    }

    // =========================================================================
    // 控制消息接收
    // =========================================================================

    private suspend fun receiveControlLoop() = withContext(Dispatchers.IO) {
        val buffer = ByteArray(4096)

        while (isRunning) {
            try {
                controlSocket?.let { socket ->
                    val packet = DatagramPacket(buffer, buffer.size)
                    try {
                        socket.receive(packet)
                        handleControlPacket(packet)
                    } catch (e: SocketTimeoutException) {
                        // 正常超时，继续
                    } catch (e: Exception) {
                        Log.e(TAG, "接收控制消息异常", e)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "控制接收循环异常", e)
            }
        }
    }

    private fun handleControlPacket(packet: DatagramPacket) {
        val data = packet.data.copyOf(packet.length)
        val parsed = ControlPacket.parse(data) ?: return

        when (parsed.msgType) {
            MsgType.MSG_ONLINE, MsgType.MSG_DISCOVER -> {
                val info = DeviceInfo.fromJson(parsed.payloadJson)
                if (info.deviceId != deviceId) {
                    onDeviceOnline(info)
                    if (parsed.msgType == MsgType.MSG_DISCOVER) {
                        // 回复在线
                        scope.launch { sendOnlineTo(packet.address.hostAddress ?: "") }
                    }
                }
            }
            MsgType.MSG_OFFLINE -> {
                val json = parsed.payloadJson
                val id = json.optString("device_id")
                if (id.isNotEmpty()) onDeviceOffline(id)
            }
            MsgType.MSG_VOLUME_SYNC -> {
                val vol = parsed.payloadJson.optInt("volume")
                onVolumeSync(vol)
            }
            MsgType.MSG_SET_SOURCE -> {
                Log.d(TAG, "收到设置音源指令")
            }
        }
    }

    // =========================================================================
    // 音频流接收
    // =========================================================================

    private suspend fun receiveAudioLoop() = withContext(Dispatchers.IO) {
        val buffer = ByteArray(65536) // 64KB

        while (isRunning) {
            try {
                audioSocket?.let { socket ->
                    val packet = DatagramPacket(buffer, buffer.size)
                    try {
                        socket.receive(packet)
                        val frame = AudioFramePacket.parse(packet.data, packet.length)
                        if (frame != null) {
                            onAudioFrame(AudioFrame(frame.timestamp, frame.payload))
                        }
                    } catch (e: SocketTimeoutException) {
                        // 正常
                    } catch (e: Exception) {
                        Log.e(TAG, "音频接收异常", e)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "音频接收循环异常", e)
            }
        }
    }

    // =========================================================================
    // 发送
    // =========================================================================

    fun sendOnlineBroadcast() {
        val deviceInfo = DeviceInfo(
            deviceId = deviceId,
            deviceName = deviceName,
            platform = platform,
            role = currentRole,
            ip = localIP,
            isSource = currentRole == "source"
        )
        val packet = ControlPacket(MsgType.MSG_ONLINE, deviceInfo.toJson())
        broadcast(packet.serialize())
    }

    private suspend fun sendOnlineTo(targetIP: String) {
        val deviceInfo = DeviceInfo(
            deviceId = deviceId,
            deviceName = deviceName,
            platform = platform,
            role = currentRole,
            ip = localIP,
            isSource = currentRole == "source"
        )
        val packet = ControlPacket(MsgType.MSG_ONLINE, deviceInfo.toJson())
        sendTo(packet.serialize(), targetIP, PORT_CONTROL)
    }

    fun sendDiscover() {
        val packet = ControlPacket(MsgType.MSG_DISCOVER, mapOf<String, Any>())
        broadcast(packet.serialize())
    }

    fun sendHeartbeat() {
        val payload = mapOf(
            "device_id" to deviceId,
            "is_source" to (currentRole == "source"),
            "audio_state" to "playing"
        )
        val packet = ControlPacket(MsgType.MSG_HEARTBEAT, payload)
        broadcast(packet.serialize())
    }

    fun sendSetSource(sourceId: String, sourceName: String) {
        val payload = mapOf("source_id" to sourceId, "source_name" to sourceName)
        val packet = ControlPacket(MsgType.MSG_SET_SOURCE, payload)
        broadcast(packet.serialize())
    }

    fun sendVolumeSync(volume: Int) {
        val payload = mapOf("device_id" to deviceId, "volume" to volume)
        val packet = ControlPacket(MsgType.MSG_VOLUME_SYNC, payload)
        broadcast(packet.serialize())
    }

    private fun broadcast(data: ByteArray) {
        try {
            val address = InetAddress.getByName("255.255.255.255")
            val packet = DatagramPacket(data, data.size, address, PORT_CONTROL)
            controlSocket?.send(packet)
        } catch (e: Exception) {
            Log.e(TAG, "广播失败", e)
        }
    }

    private suspend fun sendTo(data: ByteArray, ip: String, port: Int) {
        withContext(Dispatchers.IO) {
            try {
                val address = InetAddress.getByName(ip)
                val packet = DatagramPacket(data, data.size, address, port)
                controlSocket?.send(packet)
            } catch (e: Exception) {
                Log.e(TAG, "单播失败: $ip", e)
            }
        }
    }

    // =========================================================================
    // 音频流发送（Source模式）
    // =========================================================================

    fun sendAudioFrame(timestamp: Long, payload: ByteArray) {
        if (currentRole != "source") return
        try {
            val frame = AudioFramePacket(timestamp, payload)
            val address = InetAddress.getByName("255.255.255.255")
            val packet = DatagramPacket(frame.serialize(), frame.serializedSize, address, PORT_AUDIO)
            audioSocket?.send(packet)
        } catch (e: Exception) {
            Log.e(TAG, "音频帧发送失败", e)
        }
    }

    // =========================================================================
    // 辅助
    // =========================================================================

    fun setRole(role: String) {
        val changed = currentRole != role
        currentRole = role

        if (changed) {
            // 重新绑定端口（Source不监听音频，Receiver不发送音频）
            audioSocket?.close()
            audioSocket = null

            if (role != "source") {
                try {
                    audioSocket = DatagramSocket(PORT_AUDIO).apply {
                        receiveBufferSize = 1024 * 1024
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "音频端口绑定失败", e)
                }
            }

            sendOnlineBroadcast()
        }
    }

    private fun getLocalIP(): String {
        return try {
            val sock = DatagramSocket()
            sock.connect(InetAddress.getByName("8.8.8.8"), 80)
            val ip = sock.localAddress.hostAddress ?: "127.0.0.1"
            sock.close()
            ip
        } catch (e: Exception) {
            "127.0.0.1"
        }
    }

    fun stop() {
        isRunning = false
        scope.cancel()

        // 发送离线
        val payload = mapOf("device_id" to deviceId)
        val packet = ControlPacket(MsgType.MSG_OFFLINE, payload)
        try {
            broadcast(packet.serialize())
        } catch (e: Exception) { /* ignore */ }

        controlSocket?.close()
        audioSocket?.close()
    }
}
