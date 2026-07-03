# FyAudio 华为鸿蒙平台构建指南

## 环境要求

| 工具 | 版本要求 |
|------|----------|
| DevEco Studio | 4.0+ |
| HarmonyOS SDK | API 12+ |
| JDK | 11+ |
| Flutter | 3.22+ |

## 构建步骤

### 1. 安装 DevEco Studio

从华为官方网站下载安装：
https://developer.huawei.com/consumer/cn/deveco-studio/

### 2. 配置 HarmonyOS SDK

打开 DevEco Studio，进入 Settings -> Appearance & Behavior -> System Settings -> HarmonyOS SDK
- 选择 SDK Platforms 标签
- 勾选 HarmonyOS API 12 及以上版本
- 点击 Apply 安装

### 3. 导入项目

- 打开 DevEco Studio
- File -> Open -> 选择项目根目录 `d:\Fy audio\windows\fy_audio_player`
- 等待项目同步完成

### 4. 配置签名信息

由于华为应用市场要求应用必须签名，需要配置签名信息：

1. 打开 Build -> Generate Signed Bundle / APK
2. 选择 APK 格式
3. 点击 Create new... 创建签名文件（.keystore）
4. 填写签名信息：
   - Key store path: 选择保存位置
   - Key store password: 设置密码
   - Key alias: 设置别名
   - Key password: 设置密码
5. 点击 OK 保存

### 5. 构建 APK

- Build -> Build Bundle(s) / APK(s) -> Build APK(s)
- 构建完成后，APK 文件位于：`build\outputs\apk\release\`

## 注意事项

### 蓝牙功能

由于鸿蒙平台的蓝牙 API 与 Android 不完全兼容，蓝牙功能在鸿蒙平台上使用模拟模式。
如需完整蓝牙功能，请参考华为鸿蒙官方文档集成 `ohos.bluetooth` 模块。

### 网络同步

鸿蒙平台支持 UDP 广播和组播，网络同步功能可以正常使用。

### 权限配置

确保在 `module.json5` 中配置必要权限：

```json
{
  "module": {
    "name": "entry",
    "type": "entry",
    "description": "$string:module_desc",
    "mainElement": "EntryAbility",
    "deviceTypes": ["phone", "tablet"],
    "deliveryWithInstall": true,
    "installationFree": false,
    "metadata": [],
    "requestPermissions": [
      {
        "name": "ohos.permission.INTERNET"
      },
      {
        "name": "ohos.permission.ACCESS_NETWORK_STATE"
      },
      {
        "name": "ohos.permission.BLUETOOTH"
      },
      {
        "name": "ohos.permission.BLUETOOTH_ADMIN"
      },
      {
        "name": "ohos.permission.LOCATION"
      }
    ]
  }
}
```

## 已知问题

- 部分 Flutter 插件可能需要额外适配鸿蒙平台
- 建议在真机上进行测试，确保蓝牙和网络功能正常工作