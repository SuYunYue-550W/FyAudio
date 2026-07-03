// FyAudio Android 主界面
package com.fyaudio.syncplayer

import android.Manifest
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import com.fyaudio.syncplayer.network.NetworkManager
import com.fyaudio.syncplayer.audio.AudioCaptureManager
import com.fyaudio.syncplayer.audio.AudioPlayerManager
import com.fyaudio.syncplayer.bluetooth.BluetoothManager
import com.fyaudio.syncplayer.sync.SyncManager
import com.fyaudio.syncplayer.ui.theme.FyAudioTheme

class MainViewModel : ViewModel() {
    private val _deviceId = MutableStateFlow("")
    val deviceId: StateFlow<String> = _deviceId

    private val _role = MutableStateFlow("receiver")
    val role: StateFlow<String> = _role

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying

    private val _volume = MutableStateFlow(80)
    val volume: StateFlow<Int> = _volume

    private val _manualOffset = MutableStateFlow(0)
    val manualOffset: StateFlow<Int> = _manualOffset

    private val _syncLatency = MutableStateFlow(0)
    val syncLatency: StateFlow<Int> = _syncLatency

    private val _devices = MutableStateFlow<List<DeviceInfo>>(emptyList())
    val devices: StateFlow<List<DeviceInfo>> = _devices

    private val _bluetoothConnected = MutableStateFlow(false)
    val bluetoothConnected: StateFlow<Boolean> = _bluetoothConnected

    // Managers
    lateinit var networkManager: NetworkManager
    lateinit var audioCaptureManager: AudioCaptureManager
    lateinit var audioPlayerManager: AudioPlayerManager
    lateinit var bluetoothManager: BluetoothManager
    lateinit var syncManager: SyncManager

    fun initialize(context: android.content.Context) {
        _deviceId.value = "FY-${android.os.Build.SERIAL.take(12).uppercase()}"
        _role.value = "receiver"

        // 初始化各模块
        networkManager = NetworkManager(
            context = context,
            deviceId = _deviceId.value,
            deviceName = android.os.Build.MODEL,
            platform = "android",
            onDeviceOnline = { device -> updateDevice(device) },
            onDeviceOffline = { deviceId -> removeDevice(deviceId) },
            onAudioFrame = { frame -> syncManager.feedFrame(frame) },
            onVolumeSync = { vol -> _volume.value = vol }
        )

        syncManager = SyncManager(
            onPlayableFrame = { frame ->
                audioPlayerManager.playFrame(frame)
            },
            onStatsUpdate = { stats ->
                _syncLatency.value = stats.estimatedRTT
            }
        )

        audioPlayerManager = AudioPlayerManager(context)
        bluetoothManager = BluetoothManager(context)

        networkManager.start()
    }

    fun setRole(newRole: String) {
        _role.value = newRole
        networkManager.setRole(newRole)

        if (newRole == "source") {
            audioCaptureManager?.let {
                viewModelScope.launch { it.startCapture() }
            }
        }
    }

    fun startPlayback() {
        _isPlaying.value = true
        audioPlayerManager.start()
        syncManager.startPlaying()
    }

    fun stopPlayback() {
        _isPlaying.value = false
        audioPlayerManager.stop()
        syncManager.pausePlaying()
    }

    fun setVolume(vol: Int) {
        _volume.value = vol.coerceIn(0, 100)
        audioPlayerManager.setVolume(_volume.value)
        networkManager.sendVolumeSync(_volume.value)
    }

    fun setManualOffset(offset: Int) {
        _manualOffset.value = offset.coerceIn(-200, 200)
        syncManager.setManualOffset(_manualOffset.value)
    }

    private fun updateDevice(device: DeviceInfo) {
        val current = _devices.value.toMutableList()
        val idx = current.indexOfFirst { it.deviceId == device.deviceId }
        if (idx >= 0) current[idx] = device else current.add(device)
        _devices.value = current
    }

    private fun removeDevice(deviceId: String) {
        _devices.value = _devices.value.filter { it.deviceId != deviceId }
    }

    override fun onCleared() {
        super.onCleared()
        networkManager.stop()
        audioCaptureManager?.stopCapture()
        audioPlayerManager.stop()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
class MainActivity : ComponentActivity() {
    private lateinit var viewModel: MainViewModel
    private var mediaProjectionManager: MediaProjectionManager? = null
    private var audioCaptureManager: AudioCaptureManager? = null

    private val projectionPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == RESULT_OK && result.data != null) {
            audioCaptureManager?.startCapture(result.data!!)
        } else {
            Toast.makeText(this, "需要屏幕录制权限才能采集系统音频", Toast.LENGTH_LONG).show()
        }
    }

    private val bluetoothPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val allGranted = permissions.values.all { it }
        if (allGranted) {
            viewModel.bluetoothManager.enable()
        }
    }

    private val recordAudioPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            requestMediaProjection()
        } else {
            Toast.makeText(this, "需要录音权限", Toast.LENGTH_SHORT).show()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        viewModel = MainViewModel()
        viewModel.initialize(this)

        audioCaptureManager = AudioCaptureManager(this).also {
            viewModel.audioCaptureManager = it
        }

        mediaProjectionManager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        setContent {
            FyAudioTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    MainScreen(
                        viewModel = viewModel,
                        onRequestCapturePermission = { requestMediaProjection() },
                        onRequestBluetoothPermission = { requestBluetoothPermission() }
                    )
                }
            }
        }
    }

    private fun requestMediaProjection() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            == PackageManager.PERMISSION_GRANTED
        ) {
            mediaProjectionManager?.let {
                projectionPermissionLauncher.launch(it.createScreenCaptureIntent())
            }
        } else {
            recordAudioPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    private fun requestBluetoothPermission() {
        val permissions = arrayOf(
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.ACCESS_FINE_LOCATION
        )
        bluetoothPermissionLauncher.launch(permissions)
    }

    override fun onDestroy() {
        super.onDestroy()
        viewModel.onCleared()
    }
}
