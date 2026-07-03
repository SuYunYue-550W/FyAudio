@echo off
chcp 65001 >nul
echo ================================================
echo   FyAudio 华为鸿蒙平台构建脚本
echo   多终端同步音频播放系统
echo ================================================
echo.
echo [环境要求]
echo   1. DevEco Studio 4.0+
echo   2. HarmonyOS SDK API 12+
echo   3. JDK 11+
echo   4. Flutter 3.22+ (含鸿蒙平台支持)
echo.
echo [构建步骤]
echo   1. 打开 DevEco Studio
echo   2. 导入项目：File -> Open -> 选择本项目根目录
echo      路径: d:\Fy audio\windows\fy_audio_player
echo   3. 等待项目同步与依赖下载完成
echo   4. 配置签名信息：
echo      Build -> Generate Signed Bundle / APK
echo   5. 构建 HAP/APP 包：
echo      Build -> Build Bundle(s) / APK(s) -> Build HAP(s)/APP(s)
echo.
echo [产物路径]
echo   HAP 包: build\outputs\default\fy_audio_player-default-signed.hap
echo   APP 包: build\outputs\default\fy_audio_player-default-signed.app
echo.
echo [注意事项]
echo   - 鸿蒙平台蓝牙功能使用模拟模式（flutter_blue_plus 兼容性限制）
echo   - 网络同步功能（UDP 广播/组播）可正常使用
echo   - 需在真机上测试蓝牙与网络功能
echo   - 权限配置详见 module.json5 与 README.md
echo ================================================
pause
