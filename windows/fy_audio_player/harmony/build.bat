@echo off
chcp 65001 >nul
echo ================================================
echo   FyAudio 华为鸿蒙构建脚本
echo ================================================
echo.
echo 注意：华为鸿蒙应用构建需要以下环境：
echo   1. DevEco Studio 4.0+
echo   2. HarmonyOS SDK API 12+
echo   3. JDK 11+
echo.
echo 构建步骤：
echo   1. 打开 DevEco Studio
echo   2. 导入项目：File -> Open -> 选择本项目根目录
echo   3. 配置签名信息：Build -> Generate Signed Bundle / APK
echo   4. 构建：Build -> Build Bundle(s) / APK(s) -> Build APK(s)
echo.
echo 产物路径：build\outputs\apk\release\fy_audio_player_harmony.apk
echo ================================================
pause