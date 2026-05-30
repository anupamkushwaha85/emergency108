import 'package:dio/dio.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/local_store.dart';
import '../config/app_config.dart';
import 'package:emergency108_app/core/services/auth_session_service.dart';

const String _flushTask = 'flushHelpingHandLocations';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == _flushTask || task == Workmanager.iOSBackgroundTask) {
      final local = LocalStore();
      final queued = await local.getQueuedLocations();
      if (queued.isEmpty) return Future.value(true);

      final auth = AuthSessionService();
      final token = await auth.readAuthToken();

      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');

      final dio = Dio(BaseOptions(
        baseUrl: AppConfig.backendUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ));

      final delivered = <String>[];

      for (final item in queued) {
        final clientId = item['clientRequestId'] as String?;
        try {
          final resp = await dio.post('/helping-hand/location',
              queryParameters: userId != null ? {'userId': userId} : null,
              data: item);
          if (resp.statusCode != null && resp.statusCode! >= 200 && resp.statusCode! < 300) {
            if (clientId != null) delivered.add(clientId);
          } else {
            // Stop on first non-2xx to preserve ordering
            break;
          }
        } catch (_) {
          // Stop and retry later
          break;
        }
      }

      if (delivered.isNotEmpty) {
        await local.removeQueuedLocations(delivered);
      }
    }

    return Future.value(true);
  });
}

Future<void> registerPeriodicFlush() async {
  // Register a periodic background task. Android minimum interval is 15 minutes.
  await Workmanager().registerPeriodicTask(
    _flushTask, // unique name
    _flushTask, // task name
    frequency: const Duration(minutes: 15),
    initialDelay: const Duration(seconds: 30),
    constraints: Constraints(networkType: NetworkType.connected),
  );
}
