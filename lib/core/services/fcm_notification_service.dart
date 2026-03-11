import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Service for handling Firebase Cloud Messaging push notifications
class FCMNotificationService {
  // Singleton pattern
  static final FCMNotificationService _instance = FCMNotificationService._internal();
  factory FCMNotificationService() => _instance;
  FCMNotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'emergency_channel', // id
    'Emergency Alerts', // title
    description: 'This channel is used for high-priority emergency alerts that wake the phone.', // description
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Initialize FCM and request permissions
  Future<String?> initialize() async {
    try {
      // Request permission (required for iOS, optional for Android)
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('✅ User granted notification permission');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        debugPrint('⚠️ User granted provisional notification permission');
      } else {
        debugPrint('❌ User declined notification permission');
        return null;
      }

      // Initialize Local Notifications
      const AndroidInitializationSettings initSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initSettings = InitializationSettings(android: initSettingsAndroid);
      await _localNotifications.initialize(initSettings);

      // Create Android Channel
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      // Get FCM token
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        debugPrint('📱 FCM Token: ${token.substring(0, 20)}...');
        return token;
      }

      debugPrint('❌ Failed to get FCM token');
      return null;
    } catch (e) {
      debugPrint('❌ FCM initialization error: $e');
      return null;
    }
  }

  // Stream controller to broadcast foreground messages to UI
  final _foregroundMessageController = StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get onForegroundMessage => _foregroundMessageController.stream;

  /// Setup foreground notification handler
  void setupForegroundHandler() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('🔔 Foreground notification received');
      debugPrint('Title: ${message.notification?.title}');
      debugPrint('Body: ${message.notification?.body}');
      debugPrint('Data: ${message.data}');

      // Play local notification if we are in the foreground but the system doesn't show OS alerts
      if (message.notification != null) {
        _localNotifications.show(
          message.hashCode,
          message.notification?.title,
          message.notification?.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              importance: _channel.importance,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
              playSound: true,
              enableVibration: true,
            ),
          ),
        );
      }

      // Broadcast to listeners (e.g. HomeScreen)
      _foregroundMessageController.add(message);
    });
  }

  /// Background message handler (must be top-level function)
  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    debugPrint('🔔 Background notification received');
    debugPrint('Title: ${message.notification?.title}');
    debugPrint('Body: ${message.notification?.body}');
    debugPrint('Data: ${message.data}');
  }

  /// Setup notification tap handler (when app is in background/terminated)
  void setupNotificationTapHandler(Function(Map<String, dynamic> data) onTap) {
    // Handle notification tap when app was in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('🔔 Notification tapped (app in background)');
      debugPrint('Data: ${message.data}');
      onTap(message.data);
    });

    // Handle notification tap when app was terminated
    _firebaseMessaging.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        debugPrint('🔔 Notification tapped (app was terminated)');
        debugPrint('Data: ${message.data}');
        onTap(message.data);
      }
    });
  }

  /// Refresh FCM token (call this periodically or when token changes)
  Future<String?> refreshToken() async {
    try {
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        debugPrint('🔄 FCM Token refreshed: ${token.substring(0, 20)}...');
        return token;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Failed to refresh FCM token: $e');
      return null;
    }
  }

  /// Subscribe to a topic (useful for broadcast notifications)
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      debugPrint('✅ Subscribed to topic: $topic');
    } catch (e) {
      debugPrint('❌ Failed to subscribe to topic $topic: $e');
    }
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      debugPrint('✅ Unsubscribed from topic: $topic');
    } catch (e) {
      debugPrint('❌ Failed to unsubscribe from topic $topic: $e');
    }
  }
}
