class AppConfig {
  static const String appName = 'FyAudio';
  static const String appVersion = '1.0.0';
  static const String appDescription = '多终端WiFi蓝牙同步音频播放系统';

  static const int portAudio = 5001;
  static const int portControl = 5002;
  static const int portSync = 5003;

  static const int sampleRate = 44100;
  static const int channels = 2;
  static const int frameDurationMs = 20;

  static const int bufferMinMs = 20;
  static const int bufferDefaultMs = 40;
  static const int bufferMaxMs = 200;

  static const int heartbeatIntervalMs = 3000;
  static const int heartbeatTimeoutMs = 10000;

  static const int maxBufferFrames = 200;

  static const String defaultDeviceName = 'FyAudio Device';

  static const List<String> supportedCodecs = ['pcm', 'aac', 'opus', 'mp3'];
}