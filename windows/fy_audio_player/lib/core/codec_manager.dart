import 'scene_manager.dart';
import 'package:flutter/material.dart';

enum AudioCodecType { pcm, aac, opus, mp3 }

class FrontCodecManager {
  AudioCodecType currentCodec = AudioCodecType.aac;

  void matchSceneCodec(SceneMode mode) {
    switch (mode) {
      case SceneMode.music:
        currentCodec = AudioCodecType.aac;
        break;
      case SceneMode.video:
        currentCodec = AudioCodecType.aac;
        break;
      case SceneMode.game:
        currentCodec = AudioCodecType.opus;
        break;
      case SceneMode.room:
        currentCodec = AudioCodecType.aac;
        break;
      case SceneMode.weakNet:
        currentCodec = AudioCodecType.mp3;
        break;
      case SceneMode.night:
        currentCodec = AudioCodecType.aac;
        break;
    }
  }

  String getCodecName() {
    switch (currentCodec) {
      case AudioCodecType.pcm:
        return 'PCM 无损';
      case AudioCodecType.aac:
        return 'AAC 高音质';
      case AudioCodecType.opus:
        return 'OPUS 低延迟';
      case AudioCodecType.mp3:
        return 'MP3 高压缩';
    }
  }

  String getCodecDescription() {
    switch (currentCodec) {
      case AudioCodecType.pcm:
        return '原始音频流，无压缩';
      case AudioCodecType.aac:
        return '音质与延迟均衡';
      case AudioCodecType.opus:
        return '极低延迟，游戏专属';
      case AudioCodecType.mp3:
        return '高压缩率，弱网适配';
    }
  }

  Color getCodecColor() {
    switch (currentCodec) {
      case AudioCodecType.pcm:
        return const Color(0xff52c41a);
      case AudioCodecType.aac:
        return const Color(0xff1890ff);
      case AudioCodecType.opus:
        return const Color(0xff722ed1);
      case AudioCodecType.mp3:
        return const Color(0xfffa8c16);
    }
  }
}