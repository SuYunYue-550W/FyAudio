// Android 主界面
package com.fyaudio.syncplayer.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.fyaudio.syncplayer.MainViewModel
import com.fyaudio.syncplayer.model.DeviceInfo
import com.fyaudio.syncplayer.model.SyncStats

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(
    viewModel: MainViewModel,
    onRequestCapturePermission: () -> Unit,
    onRequestBluetoothPermission: () -> Unit
) {
    val context = LocalContext.current
    var selectedTab by remember { mutableIntStateOf(0) }

    val role by viewModel.role.collectAsState()
    val isPlaying by viewModel.isPlaying.collectAsState()
    val volume by viewModel.volume.collectAsState()
    val devices by viewModel.devices.collectAsState()
    val syncLatency by viewModel.syncLatency.collectAsState()
    val manualOffset by viewModel.manualOffset.collectAsState()
    val deviceId by viewModel.deviceId.collectAsState()
    val bluetoothConnected by viewModel.bluetoothConnected.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.speaker_group, modifier = Modifier.size(28.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("FyAudio", fontWeight = FontWeight.Bold)
                    }
                },
                actions = {
                    // 角色切换
                    SegmentedButton(
                        selected = role == "source",
                        onClick = { viewModel.setRole(if (role == "source") "receiver" else "source") },
                        icon = if (role == "source") Icons.podcasts else Icons.headphones
                    ) {
                        Text(if (role == "source") "🎙️ 音源" else "🎧 接收")
                    }
                    Spacer(Modifier.width(8.dp))
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            // 状态卡片
            StatusCard(
                role = role,
                deviceId = deviceId,
                deviceCount = devices.size,
                syncLatency = syncLatency
            )

            // Tab 选择
            TabRow(selectedTabIndex = selectedTab) {
                Tab(
                    selected = selectedTab == 0,
                    onClick = { selectedTab = 0 },
                    icon = { Icon(Icons.devices, null) },
                    text = { Text("设备") }
                )
                Tab(
                    selected = selectedTab == 1,
                    onClick = { selectedTab = 1 },
                    icon = { Icon(Icons.play_arrow, null) },
                    text = { Text("播放") }
                )
                Tab(
                    selected = selectedTab == 2,
                    onClick = { selectedTab = 2 },
                    icon = { Icon(Icons.bluetooth, null) },
                    text = { Text("蓝牙") }
                )
                Tab(
                    selected = selectedTab == 3,
                    onClick = { selectedTab = 3 },
                    icon = { Icon(Icons.tune, null) },
                    text = { Text("同步") }
                )
            }

            // Tab 内容
            when (selectedTab) {
                0 -> DevicesTab(
                    devices = devices,
                    isSource = role == "source",
                    onSetSource = { device ->
                        // 设为音源
                    }
                )
                1 -> PlaybackTab(
                    volume = volume,
                    isPlaying = isPlaying,
                    onVolumeChange = { viewModel.setVolume(it) },
                    onPlayPause = {
                        if (isPlaying) viewModel.stopPlayback()
                        else viewModel.startPlayback()
                    }
                )
                2 -> BluetoothTab(
                    isConnected = bluetoothConnected,
                    onRequestPermission = onRequestBluetoothPermission
                )
                3 -> SyncTab(
                    latencyMs = syncLatency,
                    offsetMs = manualOffset,
                    onOffsetChange = { viewModel.setManualOffset(it) },
                    onReset = { viewModel.setManualOffset(0) }
                )
            }
        }
    }
}

// ============================================================================
// 状态卡片
// ============================================================================

@Composable
fun StatusCard(
    role: String,
    deviceId: String,
    deviceCount: Int,
    syncLatency: Int
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(12.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    text = if (role == "source") "🎙️ 正在播放" else "🎧 接收中",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "ID: $deviceId",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.outline
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                AssistChip(
                    onClick = {},
                    label = { Text("$deviceCount 台设备") },
                    leadingIcon = { Icon(Icons.devices, null, Modifier.size(18.dp)) }
                )
                AssistChip(
                    onClick = {},
                    label = { Text("${syncLatency}ms") },
                    leadingIcon = { Icon(Icons.speed, null, Modifier.size(18.dp)) }
                )
            }
        }
    }
}

// ============================================================================
// 设备列表 Tab
// ============================================================================

@Composable
fun DevicesTab(
    devices: List<DeviceInfo>,
    isSource: Boolean,
    onSetSource: (DeviceInfo) -> Unit
) {
    if (devices.isEmpty()) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    Icons.radar,
                    Modifier.size(64.dp),
                    tint = MaterialTheme.colorScheme.outline
                )
                Spacer(Modifier.height(16.dp))
                Text("正在搜索局域网设备...")
                Text(
                    "确保所有设备在同一WiFi网络",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.outline
                )
            }
        }
    } else {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(8.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            items(devices) { device ->
                DeviceCard(
                    device = device,
                    isCurrentSource = device.isSource,
                    onSetSource = if (!device.isSource) {
                        { onSetSource(device) }
                    } else null
                )
            }
        }
    }
}

@Composable
fun DeviceCard(
    device: DeviceInfo,
    isCurrentSource: Boolean,
    onSetSource: (() -> Unit)?
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = if (isCurrentSource)
                MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.5f)
            else MaterialTheme.colorScheme.surface
        )
    ) {
        ListItem(
            leadingContent = {
                CircleAvatar { Text(device.platformIcon) }
            },
            headlineContent = {
                Row {
                    Text(device.deviceName)
                    if (isCurrentSource) {
                        Spacer(Modifier.width(8.dp))
                        AssistChip(
                            onClick = {},
                            label = { Text("音源", style = MaterialTheme.typography.labelSmall) }
                        )
                    }
                }
            },
            supportingContent = {
                Text("${device.ip} | ${device.platform}")
            },
            trailingContent = {
                if (onSetSource != null) {
                    FilledTonalButton(onClick = onSetSource) { Text("设为音源") }
                } else {
                    Icon(
                        if (device.isSource) Icons.podcasts else Icons.headphones,
                        null,
                        tint = MaterialTheme.colorScheme.primary
                    )
                }
            }
        )
    }
}

// ============================================================================
// 播放 Tab
// ============================================================================

@Composable
fun PlaybackTab(
    volume: Int,
    isPlaying: Boolean,
    onVolumeChange: (Int) -> Unit,
    onPlayPause: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // 播放按钮
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant
            )
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                FilledIconButton(
                    onClick = onPlayPause,
                    modifier = Modifier.size(72.dp)
                ) {
                    Icon(
                        if (isPlaying) Icons.stop else Icons.play_arrow,
                        null,
                        modifier = Modifier.size(48.dp)
                    )
                }
                Spacer(Modifier.height(8.dp))
                Text(
                    if (isPlaying) "正在播放" else "已停止",
                    style = MaterialTheme.typography.titleMedium
                )
            }
        }

        // 音量控制
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.volume_down, null)
                    Text("音量: $volume%", fontWeight = FontWeight.Bold)
                    Icon(Icons.volume_up, null)
                }
                Slider(
                    value = volume.toFloat(),
                    onValueChange = { onVolumeChange(it.toInt()) },
                    valueRange = 0f..100f,
                    steps = 99
                )
            }
        }
    }
}

// ============================================================================
// 蓝牙 Tab
// ============================================================================

@Composable
fun BluetoothTab(
    isConnected: Boolean,
    onRequestPermission: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Card {
            ListItem(
                headlineContent = { Text("蓝牙 A2DP") },
                supportingContent = {
                    Text(if (isConnected) "已连接蓝牙音箱" else "未连接")
                },
                leadingContent = {
                    Icon(
                        Icons.bluetooth,
                        null,
                        tint = if (isConnected) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.outline
                    )
                },
                trailingContent = {
                    if (!isConnected) {
                        FilledTonalButton(onClick = onRequestPermission) {
                            Text("扫描")
                        }
                    }
                }
            )
        }

        Card {
            ListItem(
                headlineContent = { Text("使用说明") },
                supportingContent = {
                    Column {
                        Text("• 蓝牙用于本地音频输出，不做跨设备传输")
                        Text("• 建议使用支持 A2DP 的蓝牙音响")
                        Text("• 多个音响建议使用树莓派网关方案")
                    }
                },
                leadingContent = { Icon(Icons.info_outline, null) }
            )
        }
    }
}

// ============================================================================
// 同步 Tab
// ============================================================================

@Composable
fun SyncTab(
    latencyMs: Int,
    offsetMs: Int,
    onOffsetChange: (Int) -> Unit,
    onReset: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // 同步状态
        Card(
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
            )
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center
                ) {
                    Box(
                        modifier = Modifier
                            .size(12.dp)
                            .padding(2.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Surface(
                            modifier = Modifier.fillMaxSize(),
                            color = if (latencyMs < 80) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.error,
                            shape = MaterialTheme.shapes.small
                        ) {}
                    }
                    Spacer(Modifier.width(8.dp))
                    Text(
                        if (latencyMs > 0) "同步中" else "等待音频流",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                }
                Spacer(Modifier.height(8.dp))
                Text("延迟: ${latencyMs}ms | 补偿: ${offsetMs}ms")
            }
        }

        // 手动补偿
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("手动延迟补偿", fontWeight = FontWeight.Bold)
                    Text("${offsetMs}ms", color = MaterialTheme.colorScheme.primary)
                }
                Text(
                    "调整以补偿不同蓝牙音响的硬件延迟",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.outline
                )
                Slider(
                    value = offsetMs.toFloat(),
                    onValueChange = { onOffsetChange(it.toInt()) },
                    valueRange = -200f..200f,
                    steps = 399
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly
                ) {
                    OutlinedButton(onClick = { onOffsetChange(offsetMs - 10) }) { Text("-10ms") }
                    OutlinedButton(onClick = onReset) { Text("归零") }
                    OutlinedButton(onClick = { onOffsetChange(offsetMs + 10) }) { Text("+10ms") }
                }
            }
        }
    }
}
