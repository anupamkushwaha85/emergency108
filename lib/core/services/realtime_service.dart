import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';

typedef OnConnect = void Function();

class RealtimeService {
  StompClient? _client;
  final List<OnConnect> _onConnect = [];
  bool _connected = false;

  void addOnConnect(OnConnect cb) => _onConnect.add(cb);

  void removeOnConnect(OnConnect cb) => _onConnect.remove(cb);

  void connect({required String url, String? topic}) {
    if (_connected) return;
    _client = StompClient(
      config: StompConfig(
        url: url,
        onConnect: (StompFrame frame) {
          _connected = true;
          for (final cb in _onConnect) {
            try {
              cb();
            } catch (_) {}
          }
          if (topic != null) {
            _client?.subscribe(destination: topic, callback: (frame) {
              // frame handling left to callers who will register subscriptions
            });
          }
        },
        onWebSocketError: (dynamic error) {
          _connected = false;
        },
        onDisconnect: (frame) {
          _connected = false;
        },
      ),
    );
    _client?.activate();
  }

  void disconnect() {
    _client?.deactivate();
    _connected = false;
  }

  bool get isConnected => _connected;
}

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  return RealtimeService();
});

