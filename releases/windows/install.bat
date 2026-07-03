@echo off
chcp 65001 >nul
title FyAudio Setup

echo ===============================================
echo     FyAudio - Multi-device Sync Audio Player
echo ===============================================
echo.

set "SCRIPT_DIR=%~dp0"
set "APP_DIR=%ProgramFiles%\FyAudio"
set "START_MENU=%APPDATA%\Microsoft\Windows\Start Menu\Programs\FyAudio"

echo [1/4] Creating installation directory...
mkdir "%APP_DIR%" >nul 2>&1
mkdir "%START_MENU%" >nul 2>&1

echo [2/4] Copying application files...
xcopy "%SCRIPT_DIR%data" "%APP_DIR%\data\" /E /Y /I /Q >nul
copy "%SCRIPT_DIR%flutter_windows.dll" "%APP_DIR%\flutter_windows.dll" >nul
copy "%SCRIPT_DIR%fy_audio_player.exe" "%APP_DIR%\fy_audio_player.exe" >nul
copy "%SCRIPT_DIR%fy_audio_backend.exe" "%APP_DIR%\fy_audio_backend.exe" >nul
copy "%SCRIPT_DIR%permission_handler_windows_plugin.dll" "%APP_DIR%\permission_handler_windows_plugin.dll" >nul
copy "%SCRIPT_DIR%screen_retriever_plugin.dll" "%APP_DIR%\screen_retriever_plugin.dll" >nul
copy "%SCRIPT_DIR%system_tray_plugin.dll" "%APP_DIR%\system_tray_plugin.dll" >nul
copy "%SCRIPT_DIR%window_manager_plugin.dll" "%APP_DIR%\window_manager_plugin.dll" >nul
if exist "%SCRIPT_DIR%flutter_blue_plus_windows_plugin.dll" (
    copy "%SCRIPT_DIR%flutter_blue_plus_windows_plugin.dll" "%APP_DIR%\flutter_blue_plus_windows_plugin.dll" >nul
)

echo [3/4] Creating Start Menu shortcut...
powershell -Command "$WshShell = New-Object -ComObject WScript.Shell; $Shortcut = $WshShell.CreateShortcut('%START_MENU%\FyAudio.lnk'); $Shortcut.TargetPath = '%APP_DIR%\fy_audio_player.exe'; $Shortcut.WorkingDirectory = '%APP_DIR%'; $Shortcut.Description = 'FyAudio - Multi-device Sync Audio Player'; $Shortcut.Save()"

echo [4/4] Creating Desktop shortcut...
powershell -Command "$WshShell = New-Object -ComObject WScript.Shell; $Shortcut = $WshShell.CreateShortcut('%USERPROFILE%\Desktop\FyAudio.lnk'); $Shortcut.TargetPath = '%APP_DIR%\fy_audio_player.exe'; $Shortcut.WorkingDirectory = '%APP_DIR%'; $Shortcut.Description = 'FyAudio - Multi-device Sync Audio Player'; $Shortcut.Save()"

echo.
echo Installation completed!
echo Application installed to: %APP_DIR%
echo Shortcuts added to Start Menu and Desktop.
echo.
pause