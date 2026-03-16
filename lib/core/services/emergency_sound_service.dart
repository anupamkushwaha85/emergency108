import 'package:audioplayers/audioplayers.dart';

class EmergencySoundService {
  static final EmergencySoundService _instance = EmergencySoundService._internal();

  factory EmergencySoundService() => _instance;

  EmergencySoundService._internal();

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;

  Future<void> playEmergencyRing() async {
    if (_isPlaying) return;
    _isPlaying = true;

    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      await _player.play(AssetSource('audio/emergency_ring.wav'));
    } catch (_) {
      _isPlaying = false;
    }
  }

  Future<void> playDispatchTone() async {
    if (_isPlaying) return;
    _isPlaying = true;

    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(0.8);
      await _player.play(AssetSource('audio/dispatch_tone.wav'));
    } catch (_) {
      _isPlaying = false;
    }
  }

  Future<void> stop() async {
    if (!_isPlaying) return;

    try {
      await _player.stop();
    } finally {
      _isPlaying = false;
    }
  }

  void dispose() {
    _player.dispose();
  }
}
