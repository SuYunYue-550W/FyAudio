@echo off
chcp 65001 >nul
title FyAudio - 自动化测试脚本

set "SCRIPT_DIR=%~dp0"
set "APP_DIR=%SCRIPT_DIR%..\build\windows\x64\runner\Release"
set "BACKEND_DIR=%SCRIPT_DIR%..\..\..\common"

echo ================================================
echo     FyAudio 自动化功能性测试
echo ================================================
echo.

echo [1/4] 检查构建产物...
if not exist "%APP_DIR%\fy_audio_player.exe" (
    echo 错误：未找到前端构建产物，请先运行 build.bat
    pause
    exit /b 1
)

if not exist "%BACKEND_DIR%\fy_audio_backend.exe" (
    echo 错误：未找到后端构建产物，请先运行 common\build_go.bat
    pause
    exit /b 1
)

echo 前端: %APP_DIR%\fy_audio_player.exe
echo 后端: %BACKEND_DIR%\fy_audio_backend.exe
echo.

echo [2/4] 启动后端服务 (Source模式)...
start "FyAudio Backend - Source" /min "%BACKEND_DIR%\fy_audio_backend.exe" -role source -name "Source-PC" -platform windows
echo 后端服务已启动 (Source模式)
timeout /t 2 /nobreak >nul

echo.
echo [3/4] 启动前端实例...
echo - 实例1: 音源模式
start "FyAudio Instance 1 - Source" "%APP_DIR%\fy_audio_player.exe"
echo - 实例2: 接收模式
start "FyAudio Instance 2 - Receiver" "%APP_DIR%\fy_audio_player.exe"
echo 前端实例已启动
timeout /t 3 /nobreak >nul

echo.
echo [4/4] 启动第二个后端服务 (Receiver模式)...
start "FyAudio Backend - Receiver" /min "%BACKEND_DIR%\fy_audio_backend.exe" -role receiver -name "Receiver-PC" -platform windows
echo 后端服务已启动 (Receiver模式)
echo.

echo ================================================
echo 测试环境已准备就绪！
echo ================================================
echo.
echo 测试场景：
echo   - 后端服务1 (Source): 监听端口 5001/5002，广播音频
echo   - 后端服务2 (Receiver): 监听端口 5001/5002，接收音频
echo   - 前端实例1: 音源模式，控制音频采集
echo   - 前端实例2: 接收模式，同步播放
echo.
echo 验证步骤：
echo   1. 在实例1中点击「播放」按钮开始发送音频
echo   2. 在实例2中点击「播放」按钮开始接收音频
echo   3. 观察两个实例的同步状态指示器
echo   4. 点击设备发现按钮验证设备发现功能
echo   5. 在实例2中点击「设为音源」按钮验证角色切换
echo.
echo 按任意键停止所有服务...
pause

echo.
echo 正在停止所有服务...
taskkill /IM fy_audio_backend.exe /F >nul 2>&1
taskkill /IM fy_audio_player.exe /F >nul 2>&1
echo 所有服务已停止
echo.
echo 测试完成！
pause