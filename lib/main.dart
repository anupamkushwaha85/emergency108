
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:async';
import 'dart:ui';
import 'core/theme/app_theme.dart';
import 'core/routing/app_router.dart';
import 'core/services/fcm_notification_service.dart';
import 'core/config/app_config.dart';
import 'core/services/realtime_service.dart';
import 'features/helping_hand/data/helping_hand_repository.dart';
import 'core/services/background_service.dart';
import 'package:workmanager/workmanager.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await FCMNotificationService.handleBackgroundMessage(message);
}

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      Zone.current.handleUncaughtError(
        details.exception,
        details.stack ?? StackTrace.current,
      );
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      Zone.current.handleUncaughtError(error, stack);
      return true;
    };

    // Lock orientation to Portrait Only
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Style system UI overlays to match the app design
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    // Tune image cache for smoother rendering of map tiles / assets
    PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20; // 100 MB

    // Initialize Firebase
    await Firebase.initializeApp();

    // Initialize background task runner
    Workmanager().initialize(callbackDispatcher);
    // Register periodic flush (idempotent)
    registerPeriodicFlush();

    // Setup background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    runApp(const ProviderScope(child: AppInit()));
  }, (Object error, StackTrace stack) {
    debugPrint('Uncaught app error: $error');
    debugPrintStack(stackTrace: stack);
  });
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Emergency 108',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
    );
  }
}

class AppInit extends ConsumerStatefulWidget {
  const AppInit({super.key});

  @override
  ConsumerState<AppInit> createState() => _AppInitState();
}

class _AppInitState extends ConsumerState<AppInit> with WidgetsBindingObserver {
  RealtimeService? _realtime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Delay connecting until first frame to ensure providers are ready
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _realtime = ref.read(realtimeServiceProvider);
      // on connect, flush queued HelpingHand locations
      _realtime?.addOnConnect(() async {
        try {
          final repo = ref.read(helpingHandRepositoryProvider);
          await repo.flushQueuedLocations();
        } catch (_) {}
      });

      final wsUrl = '${AppConfig.wsBaseUrl}/ws';
      _realtime?.connect(url: wsUrl, topic: '/topic/emergency-events');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _realtime?.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // On resume, attempt to flush queued locations
      final repo = ref.read(helpingHandRepositoryProvider);
      repo.flushQueuedLocations();
    }
  }

  @override
  Widget build(BuildContext context) {
    return const MyApp();
  }
}
