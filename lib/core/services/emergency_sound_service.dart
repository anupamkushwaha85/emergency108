import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Singleton service for playing emergency-related sounds.
///
/// Provides two looping tones:
/// - **Emergency Ring**: Telephone-style ring for driver incoming assignment
/// - **Dispatch Tone**: Urgent pulsing beep for user pre-dispatch countdown
class EmergencySoundService {
  static final EmergencySoundService _instance = EmergencySoundService._internal();
  factory EmergencySoundService() => _instance;
  EmergencySoundService._internal();

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;

  /// Play continuous telephone ring for driver incoming emergency.
  Future<void> playEmergencyRing() async {
    if (_isPlaying) return;
    _isPlaying = true;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      await _player.play(AssetSource('audio/emergency_ring.wav'));
      debugPrint('🔔 Emergency ring started');
    } catch (e) {
      debugPrint('⚠️ Failed to play emergency ring: $e');
      _isPlaying = false;
    }
  }

  /// Play continuous urgent tone for user pre-dispatch countdown.
  Future<void> playDispatchTone() async {
    if (_isPlaying) return;
    _isPlaying = true;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(0.8);
      await _player.play(AssetSource('audio/dispatch_tone.wav'));
      debugPrint('🔔 Dispatch tone started');
    } catch (e) {
      debugPrint('⚠️ Failed to play dispatch tone: $e');
      _isPlaying = false;
    }
  }

  /// Stop any currently playing sound.
  Future<void> stop() async {
    if (!_isPlaying) return;
    try {
      await _player.stop();
      debugPrint('🔕 Sound stopped');
    } catch (e) {
      debugPrint('⚠️ Failed to stop sound: $e');
    } finally {
      _isPlaying = false;
    }
  }

  bool get isPlaying => _isPlaying;

  /// Dispose the player (call only on app teardown).
  void dispose() {
    _player.dispose();
  }
}
