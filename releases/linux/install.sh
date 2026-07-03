#!/bin/bash

set -e

APP_DIR="/opt/fyaudio"
BIN_DIR="/usr/local/bin"
DESKTOP_DIR="/usr/share/applications"

echo "==============================================="
echo "    FyAudio - 多终端WiFi蓝牙同步音频播放系统"
echo "==============================================="
echo ""

echo "[1/5] 创建安装目录..."
sudo mkdir -p "$APP_DIR"
sudo mkdir -p "$BIN_DIR"

echo "[2/5] 复制后端服务..."
sudo cp "fy_audio_backend" "$APP_DIR/fy_audio_backend"
sudo chmod +x "$APP_DIR/fy_audio_backend"

echo "[3/5] 创建启动脚本..."
cat > /tmp/fyaudio_backend.sh << 'EOF'
#!/bin/bash
/opt/fyaudio/fy_audio_backend > /var/log/fyaudio.log 2>&1 &
EOF
sudo mv /tmp/fyaudio_backend.sh "$APP_DIR/fyaudio_backend.sh"
sudo chmod +x "$APP_DIR/fyaudio_backend.sh"

echo "[4/5] 创建桌面快捷方式..."
cat > /tmp/fyaudio.desktop << 'EOF'
[Desktop Entry]
Name=FyAudio
Comment=多终端WiFi蓝牙同步音频播放系统
Exec=/opt/fyaudio/fy_audio_player
Icon=audio-speakers
Terminal=false
Type=Application
Categories=AudioVideo;Player;
EOF
sudo mv /tmp/fyaudio.desktop "$DESKTOP_DIR/fyaudio.desktop"
sudo chmod +x "$DESKTOP_DIR/fyaudio.desktop"

echo "[5/5] 设置开机自启..."
cat > /tmp/fyaudio.service << 'EOF'
[Unit]
Description=FyAudio Backend Service
After=network.target

[Service]
Type=simple
ExecStart=/opt/fyaudio/fyaudio_backend.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
sudo mv /tmp/fyaudio.service "/etc/systemd/system/fyaudio.service"
sudo systemctl daemon-reload
sudo systemctl enable fyaudio

echo ""
echo "安装完成！"
echo ""
echo "注意：Flutter桌面应用需要在Linux主机上单独构建。"
echo "请将Linux版Flutter构建产物复制到 $APP_DIR/ 目录下。"
echo ""
echo "启动后端服务：sudo systemctl start fyaudio"
echo "查看日志：cat /var/log/fyaudio.log"