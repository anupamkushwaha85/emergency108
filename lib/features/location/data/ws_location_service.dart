import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'dart:convert';
import '../../../../core/services/auth_session_service.dart';

/// WebSocket-based location service for the driver app.
///
/// Connects to the Spring Boot STOMP endpoint using [stomp_dart_client] v1.0.3
/// and sends location updates via WebSocket instead of repeated HTTP POST calls.
///
/// The STOMP channel is also used to receive real-time commands from the
/// backend (e.g. emergency assignment push notifications) in the future.
///
/// Usage:
///   final service = WsLocationService(backendUrl: 'http://10.0.2.2:8080');
///   await service.startTracking();
///   // on cleanup:
///   service.stopTracking();
class WsLocationService {
  final String backendUrl;

  /// Called on every GPS position update — useful for updating the driver
  /// marker on the mission map without a separate stream subscription.
  final void Function(Position position)? onPositionUpdate;

  /// Called when a real-time emergency assignment or cancellation is received
  final void Function(String message)? onAssignmentUpdate;

  /// Called every time a location needs to be sent to the backend — both on
  /// GPS movement AND the 30-second stationary heartbeat timer.
  ///
  /// Use this to call REST PUT /api/driver/location as a fallback alongside
  /// STOMP so that both old and new backend deployments stay in sync.
  final void Function(double lat, double lng)? onLocationSend;

  StompClient? _stompClient;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _heartbeatTimer;
  Position? _lastPosition;
  bool _isTracking = false;
  WsLocationService({
    required this.backendUrl,
    this.onPositionUpdate,
    this.onAssignmentUpdate,
    this.onLocationSend,
  });

  /// Start tracking: connect WebSocket + begin GPS stream.
  /// Must be called after the driver has started a shift.
  Future<void> startTracking() async {
    if (_isTracking) return;
    _isTracking = true;

    final token = await AuthSessionService().readAuthToken();
    if (token == null) {
      debugPrint('🔴 [WsLocationService] No auth token — cannot connect');
      return;
    }

    // Extract driverId from JWT 'sub' claim
    String extractedDriverId = '';
    try {
      final parts = token.split('.');
      if (parts.length >= 2) {
        final payload = base64Url.normalize(parts[1]);
        final String decoded = utf8.decode(base64Url.decode(payload));
        final Map<String, dynamic> data = json.decode(decoded);
        extractedDriverId = data['sub']?.toString() ?? '';
      }
    } catch (e) {
      debugPrint('🔴 [WsLocationService] JWT parse error: $e');
    }

    _stompClient = StompClient(
      config: StompConfig.sockJS(
        url: '$backendUrl/ws',
        // Token passed as STOMP connect header (future JWT WebSocket auth)
        stompConnectHeaders: {
          'Authorization': 'Bearer $token',
          'driverId': extractedDriverId // pass it securely or locally
        },
        reconnectDelay: const Duration(seconds: 5),
        onConnect: _onConnected,
        onDisconnect: (StompFrame _) {
          debugPrint('🟡 [WsLocationService] Disconnected from broker');
        },
        onWebSocketError: (dynamic error) {
          debugPrint('🔴 [WsLocationService] WebSocket error: $error');
        },
        onStompError: (StompFrame frame) {
          debugPrint('🔴 [WsLocationService] STOMP error: ${frame.headers}');
        },
        // FIX: STOMP debug messages are extremely verbose (every heartbeat,
        // every frame). Guard with kDebugMode so release builds are silent.
        onDebugMessage: (String msg) {
          if (kDebugMode) debugPrint('[STOMP] $msg');
        },
      ),
    );

    _stompClient!.activate();
  }

  void _onConnected(StompFrame frame) {
    debugPrint('🟢 [WsLocationService] Connected to STOMP broker');
    
    // Retrieve driverId from headers we set during connect
    final extractedDriverId = _stompClient?.config.stompConnectHeaders?['driverId'] ?? '';
    
    if (extractedDriverId.isNotEmpty) {
      debugPrint('🟢 [WsLocationService] Subscribing to /topic/driver/$extractedDriverId/assignments');
      // Subscribe to driver-specific assignment channel (Real-time Foreground Push)
      _stompClient?.subscribe(
        destination: '/topic/driver/$extractedDriverId/assignments',
        callback: (StompFrame frame) {
          if (frame.body != null) {
            try {
              final decoded = json.decode(frame.body!);
              debugPrint('📥 [WsLocationService] Received assignment update: ${frame.body}');
              onAssignmentUpdate?.call(decoded is String ? decoded : json.encode(decoded));
            } catch (e) {
              debugPrint('🔴 [WsLocationService] Assignment payload parse error: $e');
            }
          }
        },
      );
    } else {
      debugPrint('🔴 [WsLocationService] Could not extract driverId for subscription');
    }

    _startGpsStream();
  }

  void _startGpsStream() {
    _positionSubscription?.cancel();
    _heartbeatTimer?.cancel();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      // Only emit when moved at least 5 metres — avoids spamming stationary updates
      distanceFilter: 5,
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) {
        _lastPosition = position;
        onPositionUpdate?.call(position); // UI state update only
        _sendLocation(position.latitude, position.longitude);
        debugPrint('📍 [WsLocationService] ${position.latitude}, ${position.longitude}');
      },
      onError: (Object error) {
        debugPrint('🔴 [WsLocationService] GPS stream error: $error');
      },
    );

    // Stationary heartbeat: send current position every 30 s over the existing
    // STOMP socket — essentially free (no new TCP connection, just a STOMP SEND
    // frame on the already-open WebSocket).
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_lastPosition != null) {
        debugPrint('💓 [WsLocationService] Heartbeat — resending last position via STOMP + REST');
        _sendLocation(_lastPosition!.latitude, _lastPosition!.longitude);
      } else {
        // First tick and no GPS yet — request a single fix
        Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        ).then((position) {
          _lastPosition = position;
          _sendLocation(position.latitude, position.longitude);
          debugPrint('💓 [WsLocationService] Initial heartbeat position acquired');
        }).catchError((e) {
          debugPrint('🔴 [WsLocationService] Heartbeat position error: $e');
        });
      }
    });
  }

  /// Unified location send: fires STOMP frame on the open socket AND
  /// notifies [onLocationSend] so the caller can also call REST as a fallback.
  void _sendLocation(double lat, double lng) {
    _sendLocationViaStompIfConnected(lat, lng);
    onLocationSend?.call(lat, lng);
  }

  /// Send location to the backend via the open STOMP connection.
  /// Falls back silently if the socket is not yet connected (e.g. during
  /// the first few seconds after startTracking is called).
  void _sendLocationViaStompIfConnected(double lat, double lng) {
    if (_stompClient == null || !(_stompClient!.connected)) return;
    try {
      _stompClient!.send(
        destination: '/app/driver.location',
        body: '{"lat":$lat,"lng":$lng}',
      );
    } catch (e) {
      debugPrint('🔴 [WsLocationService] STOMP send error: $e');
    }
  }

  /// Stop tracking and disconnect from WebSocket.
  void stopTracking() {
    _isTracking = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _lastPosition = null;
    _stompClient?.deactivate();
    _stompClient = null;
    debugPrint('🔵 [WsLocationService] Stopped tracking');
  }

  bool get isTracking => _isTracking;
  bool get isConnected => _stompClient?.connected ?? false;
}
