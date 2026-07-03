// Android 蓝牙 A2DP 管理
package com.fyaudio.syncplayer.bluetooth

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.util.Log
import kotlinx.coroutines.*
import java.util.*

@SuppressLint("MissingPermission")
class BluetoothManager(private val context: Context) {
    companion object {
        private const val TAG = "FyAudio-Bluetooth"
        private val A2DP_UUID = UUID.fromString("0000110D-0000-1000-8000-00805F9B34FB")
    }

    private val bluetoothAdapter: BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()
    private var a2dpProxy: BluetoothA2dp? = null
    private var connectedDevice: BluetoothDevice? = null

    private var isEnabled = false
    private var isScanning = false
    private var reconnectJob: Job? = null
    private var reconnectAddress: String? = null

    var onDeviceConnected: (() -> Unit)? = null
    var onDeviceDisconnected: (() -> Unit)? = null

    val isConnected: Boolean get() = connectedDevice != null

    // =========================================================================
    // 开关控制
    // =========================================================================

    fun enable() {
        isEnabled = true
        if (bluetoothAdapter?.isEnabled == true) {
            setupA2DP()
        }
    }

    fun disable() {
        isEnabled = false
        disconnect()
    }

    // =========================================================================
    // A2DP 代理
    // =========================================================================

    private fun setupA2DP() {
        bluetoothAdapter?.getProfileProxy(
            context,
            object : BluetoothProfile.ServiceListener {
                override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                    if (profile == BluetoothProfile.A2DP) {
                        @Suppress("UNCHECKED_CAST")
                        a2dpProxy = proxy as BluetoothA2dp
                        Log.i(TAG, "A2DP 服务已连接")
                    }
                }

                override fun onServiceDisconnected(profile: Int) {
                    a2dpProxy = null
                }
            },
            BluetoothProfile.A2DP
        )
    }

    // =========================================================================
    // 扫描
    // =========================================================================

    fun startScan(timeoutMs: Long = 10000, onDeviceFound: (BluetoothDevice) -> Unit) {
        if (isScanning) return
        isScanning = true

        // Android 扫描蓝牙设备需要 ACCESS_FINE_LOCATION 权限
        // 从 Android 12+ 改用 BLUETOOTH_SCAN（但仍需要一些权限组合）
        val scanner = bluetoothAdapter?.bluetoothLeScanner
        if (scanner != null) {
            // BLE 扫描（适用于部分A2DP设备）
            // TODO: 实现 BLE 扫描回调
            isScanning = false
            return
        }

        // 传统蓝牙扫描（配对过的设备）
        val bondedDevices = bluetoothAdapter?.bondedDevices?.toList() ?: emptyList()
        bondedDevices.forEach { device ->
            onDeviceFound(device)
        }
        isScanning = false
    }

    fun stopScan() {
        isScanning = false
        bluetoothAdapter?.bluetoothLeScanner?.stopScan(null)
    }

    // =========================================================================
    // 连接 A2DP
    // =========================================================================

    fun connect(address: String) {
        if (!isEnabled) {
            Log.w(TAG, "蓝牙未启用")
            return
        }

        val device = bluetoothAdapter?.getRemoteDevice(address) ?: run {
            Log.e(TAG, "设备不存在: $address")
            return
        }

        Log.i(TAG, "正在连接 A2DP: ${device.name}")

        // 关闭之前的连接
        disconnect()

        // 方式一：使用 BluetoothA2dp.connect()
        // 需要 API 33+ (Android 13) BLUETOOTH_CONNECT 权限
        try {
            a2dpProxy?.let { proxy ->
                // API 33+ 使用
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                    // proxy.connect(device) // Android 13+ API
                } else {
                    // 旧版：通过反射调用 connect
                    val method = BluetoothA2dp::class.java.getMethod(
                        "connect", BluetoothDevice::class.java
                    )
                    method.invoke(proxy, device)
                }
                connectedDevice = device
                onDeviceConnected?.invoke()
                scheduleReconnect(address)
            } ?: run {
                // 方式二：直接配对
                device.createBond()
                connectedDevice = device
                onDeviceConnected?.invoke()
            }
        } catch (e: Exception) {
            Log.e(TAG, "A2DP 连接失败", e)
        }
    }

    fun disconnect() {
        reconnectJob?.cancel()
        connectedDevice?.let { device ->
            try {
                a2dpProxy?.let { proxy ->
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                        // proxy.disconnect(device) // Android 13+
                    } else {
                        val method = BluetoothA2dp::class.java.getMethod(
                            "disconnect", BluetoothDevice::class.java
                        )
                        method.invoke(proxy, device)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "断开连接失败", e)
            }
        }
        connectedDevice = null
        onDeviceDisconnected?.invoke()
    }

    // =========================================================================
    // 音量
    // =========================================================================

    fun setVolume(volume: Int) {
        // Android A2DP 音量由系统控制
        // 通过 AudioManager 调整主音量
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val targetVolume = (volume / 100f * maxVolume).toInt()
        audioManager.setStreamVolume(
            AudioManager.STREAM_MUSIC,
            targetVolume,
            AudioManager.FLAG_SHOW_UI
        )
    }

    // =========================================================================
    // 自动重连
    // =========================================================================

    private fun scheduleReconnect(address: String) {
        reconnectJob?.cancel()
        reconnectAddress = address

        reconnectJob = CoroutineScope(Dispatchers.Main).launch {
            while (isActive && !isConnected && isEnabled) {
                delay(5000)
                if (!isConnected && isEnabled) {
                    Log.i(TAG, "尝试自动重连...")
                    connect(address)
                }
            }
        }
    }

    // =========================================================================
    // 获取已配对设备
    // =========================================================================

    fun getPairedDevices(): List<BluetoothDevice> {
        return bluetoothAdapter?.bondedDevices?.toList() ?: emptyList()
    }
}
